// QrScanner の統合テスト（Vitest + jsdom）。
//
// jsdomはWorker/OffscreenCanvasを実装しない——本ファイルの大半のテストはその
// 「フォールバック環境」を素で踏むことになる（worker-handle.ts の InlineWorkerHandle
// が使われる）。stop()の解放確認・throttle確認など「実Workerが呼ばれたこと」自体を
// 検証したいテストだけ、globalThis.Worker を最小フェイクで一時的に用意する。
//
// デコード経路は最低1箇所で実デコーダを通す（brief要件）: escalation テストと
// scanImage テストは test-raster.ts で生成した実際のQRラスタ画像を実際に
// decodeNative/decodeMultiScale に流し込む。
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { encode } from "@elchika-inc/moonqr/encode";
import { QrScanner } from "./index.js";
import { applyMonitorLattice, rasterizeMatrix, type RasterImage } from "./test-raster.js";

// ---- 共有フィクスチャ ----------------------------------------------------

// 素直に等倍で読める、きれいなQRラスタ（Worker-unavailable fallback の decode 経路検証用）。
const CLEAN_TEXT = "HELLO MOONQR";
const cleanMatrix = encode(CLEAN_TEXT, { ecLevel: "M", version: 2 });
if (!cleanMatrix) throw new Error("fixture setup: encode() failed for CLEAN_TEXT");
const cleanImage = rasterizeMatrix(cleanMatrix, { scale: 6, margin: 4 });

// 等倍で読め、かつ **ピラミッドが作られない** サイズのQRラスタ（scanImage の scale=1 検証用）。
// multiScaleDecode は max(width, height) >= 150 の間だけ半減レベルを積むため、
// 132px（=(25+8)*4）四方のこの画像は等倍1段のみ＝scale は必ず1になる
// （cleanImage は198px四方でレベルが2段積まれるため scale=1 の断定に使えない）。
const tinyCleanImage = rasterizeMatrix(cleanMatrix, { scale: 4, margin: 4 });

// 等倍decodeは失敗し、multiScaleDecodeの段階的縮小でのみ成功するフィクスチャ
// （packages/moonqr/test/monitor-lattice.test.mjs と同じ手法。test-raster.ts参照）。
const LATTICE_TEXT = "MONITOR LATTICE";
const latticeMatrix = encode(LATTICE_TEXT, { ecLevel: "M", version: 2 });
if (!latticeMatrix) throw new Error("fixture setup: encode() failed for LATTICE_TEXT");
const latticeImage = applyMonitorLattice(rasterizeMatrix(latticeMatrix, { scale: 28, margin: 4 }));

/** `image` を `size`x`size` の白キャンバスの左上に貼り付ける（周囲は白で埋める）。 */
function padToWhiteCanvas(image: RasterImage, size: number): RasterImage {
  const data = new Uint8Array(size * size * 4).fill(255);
  for (let y = 0; y < image.height; y++) {
    for (let x = 0; x < image.width; x++) {
      const src = (y * image.width + x) * 4;
      const dst = (y * size + x) * 4;
      data[dst] = image.data[src] as number;
      data[dst + 1] = image.data[src + 1] as number;
      data[dst + 2] = image.data[src + 2] as number;
      data[dst + 3] = 255;
    }
  }
  return { data, width: size, height: size };
}

// 「大きな画像の中に小さく写ったQR」——縮小レベルではモジュールが潰れて読めず、
// より大きい（＝縮小率の小さい）レベルまで降りて初めて読める。multiScaleDecode が
// 小スケールから順に**複数レベルを試行して**いることを attemptedScales で観測するための
// フィクスチャ（latticeImage は最小レベルで即成功するため試行が1回で終わり、順序の検証に
// 使えない）。
const smallQrInLargeImage = padToWhiteCanvas(rasterizeMatrix(cleanMatrix, { scale: 4, margin: 4 }), 640);

// ---- canvas モック ---------------------------------------------------------
// jsdomは<canvas>の2Dコンテキストで実ピクセル操作を行わない（getContextはnullを返す）ため、
// getContextをモックしてFrameCapturer/sourceToRGBAへ狙った画像を注入する。
function mockCanvasWith(image: { data: Uint8Array; width: number; height: number }) {
  const ctx = {
    drawImage: vi.fn(),
    getImageData: vi.fn(() => ({
      data: new Uint8ClampedArray(image.data.buffer, image.data.byteOffset, image.data.length),
      width: image.width,
      height: image.height,
    })),
  };
  vi.spyOn(HTMLCanvasElement.prototype, "getContext").mockReturnValue(ctx as unknown as CanvasRenderingContext2D);
  return ctx;
}

function mockVideoSize(video: HTMLVideoElement, width: number, height: number) {
  Object.defineProperty(video, "videoWidth", { value: width, configurable: true });
  Object.defineProperty(video, "videoHeight", { value: height, configurable: true });
}

// ---- getUserMedia モック ----------------------------------------------------

interface FakeTrack {
  stop: ReturnType<typeof vi.fn>;
}

function makeFakeStream(): { stream: MediaStream; tracks: FakeTrack[] } {
  const tracks: FakeTrack[] = [{ stop: vi.fn() }, { stop: vi.fn() }];
  const stream = {
    getTracks: () => tracks,
  } as unknown as MediaStream;
  return { stream, tracks };
}

function mockGetUserMedia(impl: (constraints: unknown) => Promise<MediaStream>) {
  Object.defineProperty(navigator, "mediaDevices", {
    value: { getUserMedia: vi.fn(impl) },
    configurable: true,
  });
}

// ---- 実Workerフェイク（stop()解放・throttle検証用） ---------------------------
// InlineWorkerHandle経由だと「Workerに何が渡ったか」を外部から観測しづらいため、
// このフェイクはglobalThis.Workerを差し替えてRealWorkerHandle経路を通す
// （worker-handle.tsのtryCreateRealWorker: typeof Worker!=="undefined" を満たす）。
class FakeWorker {
  static instances: FakeWorker[] = [];
  /** trueの間、応答を自動配送せず pendingResponses に溜める（stop()後の遅延配送を再現する）。 */
  static defer = false;
  static pendingResponses: Array<() => void> = [];
  onmessage: ((event: { data: unknown }) => void) | null = null;
  onerror: ((event: unknown) => void) | null = null;
  terminate = vi.fn();
  postMessage = vi.fn((message: { id: number }) => {
    // 実Workerの非同期性を模す: 既定では「見つからなかった」で即応答する
    // （呼び出し元のpendingフラグを解放し、次フレームが進行できるようにする）。
    const deliver = (result: unknown = null) => {
      this.onmessage?.({ data: { id: message.id, result } });
    };
    if (FakeWorker.defer) {
      FakeWorker.pendingResponses.push(() => deliver(FakeWorker.deferredResult));
      return;
    }
    queueMicrotask(() => deliver(null));
  });
  /** defer中に配送する結果（既定は成功結果を模した任意のオブジェクト）。 */
  static deferredResult: unknown = null;
  constructor() {
    FakeWorker.instances.push(this);
  }
  /** 溜めておいた応答を今この場で配送する。 */
  static flush(): void {
    const queued = FakeWorker.pendingResponses;
    FakeWorker.pendingResponses = [];
    for (const deliver of queued) deliver();
  }
}

function installFakeWorker(): void {
  FakeWorker.instances = [];
  FakeWorker.defer = false;
  FakeWorker.pendingResponses = [];
  FakeWorker.deferredResult = null;
  vi.stubGlobal("Worker", FakeWorker);
  if (!("createObjectURL" in URL)) {
    // @ts-expect-error jsdom未実装環境向けの最小stub
    URL.createObjectURL = vi.fn(() => "blob:mock");
  }
  if (!("revokeObjectURL" in URL)) {
    // @ts-expect-error 同上
    URL.revokeObjectURL = vi.fn();
  }
  vi.spyOn(URL, "createObjectURL").mockReturnValue("blob:mock");
  vi.spyOn(URL, "revokeObjectURL").mockImplementation(() => {});
}

// ---- setup / teardown -------------------------------------------------------

let video: HTMLVideoElement;

beforeEach(() => {
  video = document.createElement("video");
  video.play = vi.fn().mockResolvedValue(undefined);
});

afterEach(() => {
  vi.restoreAllMocks();
  vi.unstubAllGlobals();
  vi.useRealTimers();
});

// ---- テスト -------------------------------------------------------------

describe("QrScanner#start", () => {
  it("calls getUserMedia with { video: { facingMode: 'environment' } } by default", async () => {
    const { stream } = makeFakeStream();
    const getUserMedia = vi.fn().mockResolvedValue(stream);
    mockGetUserMedia(getUserMedia);
    mockCanvasWith(cleanImage);

    const scanner = new QrScanner(video, vi.fn());
    await scanner.start();

    expect(getUserMedia).toHaveBeenCalledWith({ video: { facingMode: "environment" } });
    scanner.stop();
  });

  it("passes through preferredCamera: 'user'", async () => {
    const { stream } = makeFakeStream();
    const getUserMedia = vi.fn().mockResolvedValue(stream);
    mockGetUserMedia(getUserMedia);
    mockCanvasWith(cleanImage);

    const scanner = new QrScanner(video, vi.fn(), { preferredCamera: "user" });
    await scanner.start();

    expect(getUserMedia).toHaveBeenCalledWith({ video: { facingMode: "user" } });
    scanner.stop();
  });

  it("rejects on permission denial and never calls onResult", async () => {
    mockGetUserMedia(() => Promise.reject(new DOMException("Permission denied", "NotAllowedError")));
    const onResult = vi.fn();
    const scanner = new QrScanner(video, onResult);

    await expect(scanner.start()).rejects.toThrow(/Permission denied|Failed to access camera/);
    expect(onResult).not.toHaveBeenCalled();
  });
});

describe("QrScanner#stop", () => {
  it("is idempotent and releases stream tracks + worker", async () => {
    installFakeWorker();
    const { stream, tracks } = makeFakeStream();
    mockGetUserMedia(() => Promise.resolve(stream));
    mockCanvasWith(cleanImage);

    const scanner = new QrScanner(video, vi.fn());
    await scanner.start();
    const worker = FakeWorker.instances[0];
    if (!worker) throw new Error("expected a FakeWorker instance to have been created");

    scanner.stop();
    scanner.stop(); // 2回目: 例外を投げない（冪等）

    for (const track of tracks) expect(track.stop).toHaveBeenCalledTimes(1);
    expect(worker.terminate).toHaveBeenCalledTimes(1);
  });
});

describe("QrScanner throttling", () => {
  it("honors maxScansPerSecond (fewer scan attempts than the unthrottled frame rate)", async () => {
    vi.useFakeTimers({ toFake: ["requestAnimationFrame", "cancelAnimationFrame", "performance", "Date"] });
    installFakeWorker();
    const { stream } = makeFakeStream();
    mockGetUserMedia(() => Promise.resolve(stream));
    mockCanvasWith(cleanImage);
    mockVideoSize(video, cleanImage.width, cleanImage.height);

    // 10 scans/sec = 100ms間隔。350ms分進めれば、無throttleなら60fps(~16.7ms)で
    // 20回超のフレームが来るが、throttle後は3〜4回程度の実スキャンに収まるはず。
    const scanner = new QrScanner(video, vi.fn(), { maxScansPerSecond: 10 });
    await scanner.start();
    const worker = FakeWorker.instances[0];
    if (!worker) throw new Error("expected a FakeWorker instance");

    await vi.advanceTimersByTimeAsync(350);

    expect(worker.postMessage.mock.calls.length).toBeGreaterThanOrEqual(2);
    expect(worker.postMessage.mock.calls.length).toBeLessThanOrEqual(5);

    scanner.stop();
  });
});

describe("QrScanner live-frame decoding", () => {
  it("uses the native-scale fast path and calls onResult for a clean QR (Worker-unavailable fallback)", async () => {
    // globalThis.Worker を用意しない = jsdom既定のまま(Workerは undefined)。
    // worker-handle.ts の InlineWorkerHandle が使われ、実デコーダが同スレッドで走る。
    vi.useFakeTimers({ toFake: ["requestAnimationFrame", "cancelAnimationFrame", "performance", "Date"] });
    const { stream } = makeFakeStream();
    mockGetUserMedia(() => Promise.resolve(stream));
    mockCanvasWith(cleanImage);
    mockVideoSize(video, cleanImage.width, cleanImage.height);

    const onResult = vi.fn();
    const scanner = new QrScanner(video, onResult, { maxScansPerSecond: 25 });
    await scanner.start();

    await vi.advanceTimersByTimeAsync(80); // 25/sec = 40ms間隔 → 2フレーム分あれば十分

    expect(onResult).toHaveBeenCalled();
    expect(onResult.mock.calls[0]?.[0]?.text).toBe(CLEAN_TEXT);

    scanner.stop();
  });

  it("escalates to multiscale after N consecutive failures and recovers a monitor-lattice QR", async () => {
    vi.useFakeTimers({ toFake: ["requestAnimationFrame", "cancelAnimationFrame", "performance", "Date"] });
    const { stream } = makeFakeStream();
    mockGetUserMedia(() => Promise.resolve(stream));
    mockCanvasWith(latticeImage);
    mockVideoSize(video, latticeImage.width, latticeImage.height);

    const onResult = vi.fn();
    // maxScansPerSecond=1000 (1msおき) にして、17フレーム分を短時間で消化する。
    const scanner = new QrScanner(video, onResult, { maxScansPerSecond: 1000 });
    await scanner.start();

    // 15回の等倍失敗 + 16回目でエスカレーションして成功する設計
    // (DEFAULT_ESCALATE_AFTER_FAILURES=15、index.tsのコメント参照)。
    // rAFは(fake timers下でも)実際には約16msおきにしか発火しないため、
    // maxScansPerSecond=1000(1ms間隔)にしてもスキャン試行数はrAFの発火回数で
    // 律速される——十分な実時間を進めて20フレーム超のrAF発火を確保する。
    await vi.advanceTimersByTimeAsync(500);

    expect(onResult).toHaveBeenCalledTimes(1);
    expect(onResult.mock.calls[0]?.[0]?.text).toBe(LATTICE_TEXT);

    scanner.stop();
  });
});

describe("QrScanner stale-response safety (regression)", () => {
  // 回帰テスト: Worker.terminate() は **Workerスレッドを止めるだけ** で、既にメイン
  // スレッドのイベントループに積まれた "message" タスクはキャンセルしない。
  // stop()後に古い応答が配送されても onResult / onError を発火させてはならない
  // （消費者が「成功→stop()→成功画面へ遷移」した直後に二重通知が来る事故を防ぐ）。
  it("does NOT call onResult when a worker response arrives after stop()", async () => {
    vi.useFakeTimers({ toFake: ["requestAnimationFrame", "cancelAnimationFrame", "performance", "Date"] });
    installFakeWorker();
    FakeWorker.defer = true; // 応答を保留し、stop()後に手動配送する
    FakeWorker.deferredResult = { text: "STALE", bytes: new Uint8Array(), version: 1, ecLevel: "M", corners: [] };
    const { stream } = makeFakeStream();
    mockGetUserMedia(() => Promise.resolve(stream));
    mockCanvasWith(cleanImage);
    mockVideoSize(video, cleanImage.width, cleanImage.height);

    const onResult = vi.fn();
    const scanner = new QrScanner(video, onResult);
    await scanner.start();
    await vi.advanceTimersByTimeAsync(50); // フレームをpostMessageさせる
    expect(FakeWorker.pendingResponses.length).toBeGreaterThan(0); // 応答が in-flight

    scanner.stop();
    FakeWorker.flush(); // stop()後に古い応答が配送される
    await vi.advanceTimersByTimeAsync(10);

    expect(onResult).not.toHaveBeenCalled();
  });

  it("does NOT call onError when a worker error arrives after stop()", async () => {
    installFakeWorker();
    const { stream } = makeFakeStream();
    mockGetUserMedia(() => Promise.resolve(stream));
    mockCanvasWith(cleanImage);

    const onError = vi.fn();
    const scanner = new QrScanner(video, vi.fn(), { onError });
    await scanner.start();
    const worker = FakeWorker.instances[0];
    if (!worker) throw new Error("expected a FakeWorker instance");

    scanner.stop();
    // stop()後にクラッシュ通知が届いても、RealWorkerHandle 側でハンドラが外れている
    // （かつ index.ts 側にも stopped ガードがある）ため発火しない。
    worker.onerror?.(new ErrorEvent("error", { message: "late boom" }));

    expect(onError).not.toHaveBeenCalled();
  });
});

describe("QrScanner worker crash", () => {
  it("auto-restarts the worker and surfaces the crash via onError (never swallowed)", async () => {
    installFakeWorker();
    const { stream } = makeFakeStream();
    mockGetUserMedia(() => Promise.resolve(stream));
    mockCanvasWith(cleanImage);
    mockVideoSize(video, cleanImage.width, cleanImage.height);

    const onError = vi.fn();
    const scanner = new QrScanner(video, vi.fn(), { onError });
    await scanner.start();
    const firstWorker = FakeWorker.instances[0];
    if (!firstWorker) throw new Error("expected a FakeWorker instance");

    firstWorker.onerror?.(new ErrorEvent("error", { message: "boom" }));

    expect(onError).toHaveBeenCalledTimes(1);
    expect(onError.mock.calls[0]?.[0]).toBeInstanceOf(Error);
    expect(firstWorker.terminate).toHaveBeenCalledTimes(1);
    expect(FakeWorker.instances.length).toBe(2); // 再起動で新しいインスタンスが作られる

    scanner.stop();
  });
});

describe("QrScanner.scanImage", () => {
  it("always uses multiscale and recovers a monitor-lattice QR from a canvas source", async () => {
    mockCanvasWith(latticeImage);
    const source = document.createElement("canvas");
    source.width = latticeImage.width;
    source.height = latticeImage.height;

    const result = await QrScanner.scanImage(source);

    expect(result).not.toBeNull();
    expect(result?.text).toBe(LATTICE_TEXT);
  });

  it("returns null for an image with no QR code", async () => {
    const blank = { data: new Uint8Array(100 * 100 * 4).fill(255), width: 100, height: 100 };
    mockCanvasWith(blank);
    const source = document.createElement("canvas");
    source.width = 100;
    source.height = 100;

    const result = await QrScanner.scanImage(source);
    expect(result).toBeNull();
  });

  // --- scale / attemptedScales の公開契約（ScanImageResult） -------------------
  // scanImage は DecodeResult だけでなく「どのスケールで読めたか」まで返す
  // （index.ts の ScanImageResult 参照）。この情報を落とすと消費者は成功スケールを
  // 知るために multiScaleDecode を自前で呼び直す＝公開APIを迂回するしかなくなる。

  it("reports scale=1 when the image decodes at native resolution (no pyramid built)", async () => {
    // tinyImage は max(w,h) < 150 のため multiScaleDecode はピラミッドを作らず
    // 等倍レベル1段のみを試す → scale は必ず 1（等倍成功）。
    mockCanvasWith(tinyCleanImage);
    const source = document.createElement("canvas");
    source.width = tinyCleanImage.width;
    source.height = tinyCleanImage.height;

    const result = await QrScanner.scanImage(source);

    expect(result?.text).toBe(CLEAN_TEXT);
    expect(result?.scale).toBe(1);
    expect(result?.attemptedScales).toEqual([1]);
  });

  it("reports the reduced scale (>1) that recovered the monitor-lattice QR", async () => {
    // 等倍では格子に阻まれて読めず、段階的ボックス平均縮小でのみ読める
    // （multiscale.ts 冒頭の root cause）。scale は縮小が効いたことを示す >1 になり、
    // 「等倍でも読めた」場合と区別できていること（＝scaleが定数1でベタ書きされていない）を
    // 保証する。
    mockCanvasWith(latticeImage);
    const source = document.createElement("canvas");
    source.width = latticeImage.width;
    source.height = latticeImage.height;

    const result = await QrScanner.scanImage(source);

    expect(result?.text).toBe(LATTICE_TEXT);
    expect(result?.scale).toBeGreaterThan(1);
    // scale は必ず2の冪（逐次半減の総縮小率）
    expect(Number.isInteger(Math.log2(result?.scale ?? 0))).toBe(true);
    // 成功したスケールは、実際に試行した列の最後（＝そこで打ち切られた）に来る。
    const attempted = result?.attemptedScales ?? [];
    expect(attempted[attempted.length - 1]).toBe(result?.scale);
  });

  it("lists attemptedScales from the smallest image (largest reduction) upward", async () => {
    // 契約: attemptedScales は「小さい画像から」の試行順（= scale値としては降順）。
    // 安価な小スケールから試すのが multiScaleDecode の性能設計の要（multiscale.ts 参照）。
    // 大画像に小さく写ったQRは小スケールでは潰れて読めず、複数レベルを試行する
    // ——順序を観測できる唯一のフィクスチャ（lattice は最小レベルで即成功する）。
    mockCanvasWith(smallQrInLargeImage);
    const source = document.createElement("canvas");
    source.width = smallQrInLargeImage.width;
    source.height = smallQrInLargeImage.height;

    const result = await QrScanner.scanImage(source);

    expect(result?.text).toBe(CLEAN_TEXT);
    const attempted = result?.attemptedScales ?? [];
    expect(attempted.length).toBeGreaterThan(1); // 小スケールで失敗し、実際に複数レベルを試している
    for (let i = 1; i < attempted.length; i++) {
      const prev = attempted[i - 1] as number;
      const cur = attempted[i] as number;
      // scale値が単調減少 = 画像サイズが単調増加（小さい画像から大きい画像へ）
      expect(cur).toBeLessThan(prev);
    }
    // 成功レベルは試行列の末尾（そこで打ち切られた）
    expect(attempted[attempted.length - 1]).toBe(result?.scale);
  });
});

describe("QrScanner.hasCamera", () => {
  it("returns true when getUserMedia is available", async () => {
    mockGetUserMedia(() => Promise.reject(new Error("unused")));
    await expect(QrScanner.hasCamera()).resolves.toBe(true);
  });

  it("returns false when mediaDevices is unavailable", async () => {
    Object.defineProperty(navigator, "mediaDevices", { value: undefined, configurable: true });
    await expect(QrScanner.hasCamera()).resolves.toBe(false);
  });
});
