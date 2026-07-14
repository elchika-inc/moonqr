export { halveRGBA, multiScaleDecode } from "./multiscale.js";
export type { MultiScaleOutcome, RGBAImage } from "./multiscale.js";
export type { DecodeResult } from "./decode-core.js";

import { startCamera } from "./camera.js";
import { FrameCapturer, sourceToRGBA } from "./canvas.js";
import { decodeMultiScale, type DecodeResult } from "./decode-core.js";
import { createWorkerHandle, type WorkerHandle } from "./worker-handle.js";
import type { WorkerResponse } from "./worker.js";

export interface QrScannerOptions {
  /** "environment"（背面・既定）または "user" */
  preferredCamera?: "environment" | "user";
  /** 1秒あたりの最大スキャン回数（既定 25） */
  maxScansPerSecond?: number;
  /** 反転色QRも試す（既定 true） */
  invert?: boolean;
  /** エラー通知（カメラ切断・Worker クラッシュ等）。握りつぶさない */
  onError?: (error: Error) => void;
}

const DEFAULT_MAX_SCANS_PER_SECOND = 25;

// ライブフレームがNフレーム連続で読み取りに失敗したら、その1回だけマルチスケール
// ピラミッドへエスカレーションする閾値（既定15）。
//
// 理由（perf）: 毎フレームマルチスケール（ピラミッド全段の構築+試行）を行うと数十ms級の
// コストが常時掛かり続け、実効フレームレートを損なう。そのためライブフレームは基本的に
// 等倍1回のみを試す高速パスとし、マルチスケールは「等倍では読めないケース」——遠くに
// 小さく写ったQRや、モニター越しに撮影したQR（サブピクセル格子がボックス平均縮小でしか
// 除去できない。詳細は multiscale.ts 冒頭コメント）——を救済するための例外的な手段として
// 温存する。エスカレーション試行を1回行ったら結果の成否に関わらずカウンタをリセットし、
// 以後は再び等倍の高速パスに戻る（連続してマルチスケールに居座ってフレームレートを
// 落とし続けることを防ぐ）。
const DEFAULT_ESCALATE_AFTER_FAILURES = 15;

/**
 * カメラ映像からQRコードを継続的に読み取るスキャナ。
 *
 * ループは requestAnimationFrame ベースで、maxScansPerSecond でスロットルする。
 * 実際のデコードはWorkerへオフロードする（フレームバッファはtransferでゼロコピー）。
 * Worker/OffscreenCanvasが使えない環境（テスト・古いブラウザ）では同スレッド実行に
 * 透過的にフォールバックする。
 */
export class QrScanner {
  private readonly video: HTMLVideoElement;
  private readonly onResult: (result: DecodeResult) => void;
  private readonly preferredCamera: "environment" | "user";
  private readonly maxScansPerSecond: number;
  private readonly invert: boolean;
  private readonly onError: (error: Error) => void;
  private readonly escalateAfterFailures = DEFAULT_ESCALATE_AFTER_FAILURES;

  private readonly capturer = new FrameCapturer();
  private stream: MediaStream | null = null;
  private worker: WorkerHandle | null = null;
  private rafId: number | null = null;
  // start()前・stop()後はtrue。stop()の冪等性の要（2回目以降は何もしない）。
  private stopped = true;
  private pending = false;
  private lastScanAt = -Infinity;
  private consecutiveFailures = 0;
  private nextRequestId = 0;

  constructor(
    video: HTMLVideoElement,
    onResult: (result: DecodeResult) => void,
    options: QrScannerOptions = {},
  ) {
    this.video = video;
    this.onResult = onResult;
    this.preferredCamera = options.preferredCamera ?? "environment";
    this.maxScansPerSecond = options.maxScansPerSecond ?? DEFAULT_MAX_SCANS_PER_SECOND;
    this.invert = options.invert ?? true;
    // onErrorは既定でも「握りつぶさない」契約を満たすため、未指定時はconsole.errorへ
    // 出す（黙って捨てない）。
    this.onError =
      options.onError ??
      ((error) => {
        console.error("[QrScanner]", error);
      });
  }

  /** getUserMedia → video 再生 → Worker 起動 → ループ開始。失敗は reject */
  async start(): Promise<void> {
    if (!this.stopped) return; // 二重start防止
    this.stopped = false;
    try {
      this.stream = await startCamera(this.video, { facingMode: this.preferredCamera });
    } catch (error) {
      this.stopped = true;
      throw error; // 握りつぶさずそのままreject
    }

    if (this.stopped) {
      // start() の途中(getUserMedia待ち)でstop()が呼ばれた場合、取得できたストリームを
      // 直ちに解放してリークを防ぐ。
      for (const track of this.stream.getTracks()) track.stop();
      this.stream = null;
      return;
    }

    this.worker = this.createWorker();
    this.scheduleNextFrame();
  }

  /** ストリーム・Worker・タイマーを全解放（冪等） */
  stop(): void {
    if (this.stopped) return; // 冪等: 2回目以降は何もしない
    this.stopped = true;
    if (this.rafId !== null) {
      cancelAnimationFrame(this.rafId);
      this.rafId = null;
    }
    this.worker?.terminate();
    this.worker = null;
    if (this.stream) {
      for (const track of this.stream.getTracks()) track.stop();
      this.stream = null;
    }
    // カメラのライブ表示インジケータが残留するブラウザがあるため、srcObjectも切る。
    this.video.srcObject = null;
    this.pending = false;
    // 再start()した際に前回セッションのエスカレーション状態を持ち越さない。
    this.consecutiveFailures = 0;
    this.lastScanAt = -Infinity;
  }

  private createWorker(): WorkerHandle {
    const worker = createWorkerHandle();
    worker.onmessage = (event) => this.handleWorkerMessage(event.data);
    worker.onerror = (event) => this.handleWorkerCrash(event);
    return worker;
  }

  /** Worker クラッシュ時: 自動再起動しつつ onError へ surface する（握りつぶさない）。 */
  private handleWorkerCrash(event: ErrorEvent | Event): void {
    this.pending = false;
    const message = event instanceof ErrorEvent ? event.message : "unknown worker error";
    this.onError(new Error(`Scanner worker crashed: ${message}`, { cause: event }));
    if (this.stopped) return;
    this.worker?.terminate();
    this.worker = this.createWorker();
  }

  private scheduleNextFrame(): void {
    if (this.stopped) return;
    this.rafId = requestAnimationFrame(() => this.onFrame());
  }

  private onFrame(): void {
    if (this.stopped) return;
    const now = performance.now();
    const minInterval = 1000 / this.maxScansPerSecond;
    if (!this.pending && now - this.lastScanAt >= minInterval) {
      this.lastScanAt = now;
      this.captureAndDecode();
    }
    this.scheduleNextFrame();
  }

  private captureAndDecode(): void {
    const width = this.video.videoWidth;
    const height = this.video.videoHeight;
    if (!width || !height || !this.worker) return; // まだ映像フレームが来ていない

    const frame = this.capturer.capture(this.video, width, height);
    const buffer = frame.data.buffer as ArrayBuffer;
    const multiscale = this.consecutiveFailures >= this.escalateAfterFailures;
    const id = this.nextRequestId++;
    this.pending = true;
    this.worker.postMessage({ id, buffer, width, height, invert: this.invert, multiscale }, [
      buffer,
    ]);
  }

  private handleWorkerMessage(response: WorkerResponse): void {
    this.pending = false;
    if (response.result) {
      this.consecutiveFailures = 0;
      this.onResult(response.result);
      return;
    }
    // エスカレーション試行だった場合は成否に関わらずリセットする（居座り防止。
    // DEFAULT_ESCALATE_AFTER_FAILURES のコメント参照）。
    if (this.consecutiveFailures >= this.escalateAfterFailures) {
      this.consecutiveFailures = 0;
    } else {
      this.consecutiveFailures++;
    }
  }

  /** 静止画の一発読取（マルチスケール込み） */
  static async scanImage(
    source: HTMLImageElement | HTMLCanvasElement | ImageBitmap | Blob,
  ): Promise<DecodeResult | null> {
    const { data, width, height } = await sourceToRGBA(source);
    return decodeMultiScale(data, { width, height, invert: true });
  }

  /** カメラが利用可能か（getUserMedia の有無・HTTPS 文脈） */
  static async hasCamera(): Promise<boolean> {
    if (typeof navigator === "undefined" || !navigator.mediaDevices?.getUserMedia) return false;
    if (typeof window !== "undefined" && window.isSecureContext === false) return false;
    return true;
  }
}
