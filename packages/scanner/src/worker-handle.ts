// Worker起動の抽象化。実Workerが使える環境ではBlob URL化した自己完結スクリプトで
// 起動し、使えない環境（テスト用jsdom・古いブラウザ・CSPでblob:を禁止する環境等）では
// 同スレッド実行にフォールバックする。呼び出し側（index.ts）は WorkerHandle という
// 単一のインターフェースだけを見ればよく、どちらが動いているかを意識しない
// （フォールバックは透過的——エラーとしてonErrorへ出さない。仕様上「Worker/OffscreenCanvas
// が使えない環境」は想定内の正常系であり、握りつぶすべきエラーとは性質が異なるため）。
import { decodeMultiScale, decodeNative } from "./decode-core.js";
import { WORKER_SOURCE } from "./worker-inline.generated.js";
import type { WorkerRequest, WorkerResponse } from "./worker.js";

export interface WorkerHandle {
  postMessage(message: WorkerRequest, transfer: Transferable[]): void;
  terminate(): void;
  onmessage: ((event: { data: WorkerResponse }) => void) | null;
  onerror: ((event: ErrorEvent | Event) => void) | null;
}

/** 実Workerをラップするだけの薄いアダプタ（型を WorkerHandle に揃える）。 */
class RealWorkerHandle implements WorkerHandle {
  private readonly worker: Worker;
  onmessage: ((event: { data: WorkerResponse }) => void) | null = null;
  onerror: ((event: ErrorEvent | Event) => void) | null = null;

  constructor(worker: Worker) {
    this.worker = worker;
    worker.onmessage = (event) => this.onmessage?.(event as unknown as { data: WorkerResponse });
    worker.onerror = (event) => this.onerror?.(event);
  }

  postMessage(message: WorkerRequest, transfer: Transferable[]): void {
    this.worker.postMessage(message, transfer);
  }

  terminate(): void {
    this.worker.terminate();
  }
}

/**
 * 同スレッド実行フォールバック。postMessageの非同期性（呼び出し元が「結果は後から
 * onmessage経由で来る」ことを前提にできる)を壊さないよう、処理はマイクロタスクへ逃がす。
 * terminate() 後に届いたレスポンスは破棄する（stop()後の遅延応答でonResultが呼ばれる
 * 事故を防ぐ）。
 */
class InlineWorkerHandle implements WorkerHandle {
  private terminated = false;
  onmessage: ((event: { data: WorkerResponse }) => void) | null = null;
  onerror: ((event: ErrorEvent | Event) => void) | null = null;

  postMessage(message: WorkerRequest, _transfer: Transferable[]): void {
    queueMicrotask(() => {
      if (this.terminated) return;
      try {
        const data = new Uint8Array(message.buffer);
        const result = message.multiscale
          ? decodeMultiScale(data, message)
          : decodeNative(data, message);
        this.onmessage?.({ data: { id: message.id, result } });
      } catch (error) {
        const err = error instanceof Error ? error : new Error(String(error));
        this.onerror?.(new ErrorEvent("error", { error: err, message: err.message }));
      }
    });
  }

  terminate(): void {
    this.terminated = true;
  }
}

function tryCreateRealWorker(): Worker | null {
  if (typeof Worker === "undefined") return null;
  let url: string;
  try {
    const blob = new Blob([WORKER_SOURCE], { type: "text/javascript" });
    url = URL.createObjectURL(blob);
  } catch {
    return null;
  }
  try {
    return new Worker(url);
  } catch {
    return null;
  } finally {
    // Workerコンストラクタはスクリプト取得を同期的に開始する（仕様上、URLの解決は
    // コンストラクタ呼び出し時点で行われる）ため、直後にrevokeしてよい。
    URL.revokeObjectURL(url);
  }
}

/**
 * WorkerHandle を生成する。実Worker（Blob URL経由）を優先し、使えない/構築に失敗した
 * 環境では透過的に同スレッド実行へフォールバックする。
 */
export function createWorkerHandle(): WorkerHandle {
  const real = tryCreateRealWorker();
  return real ? new RealWorkerHandle(real) : new InlineWorkerHandle();
}
