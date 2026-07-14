// canvas経由でのRGBA画素取得。OffscreenCanvasが使える環境ではそちらを優先する
// （メインスレッドのレイアウト/表示コストを避けられるため）。ない環境（jsdom・
// 古いブラウザ）では通常の <canvas> にフォールバックする。

type Canvas2DLike = OffscreenCanvas | HTMLCanvasElement;
type Ctx2DLike = OffscreenCanvasRenderingContext2D | CanvasRenderingContext2D;

export interface RGBAFrame {
  data: Uint8ClampedArray;
  width: number;
  height: number;
}

function createCanvas(width: number, height: number): { canvas: Canvas2DLike; ctx: Ctx2DLike } {
  if (typeof OffscreenCanvas !== "undefined") {
    const canvas = new OffscreenCanvas(width, height);
    const ctx = canvas.getContext("2d");
    if (!ctx) throw new Error("Failed to acquire a 2D context from OffscreenCanvas");
    return { canvas, ctx };
  }
  const canvas = document.createElement("canvas");
  canvas.width = width;
  canvas.height = height;
  const ctx = canvas.getContext("2d");
  if (!ctx) throw new Error("Failed to acquire a 2D context from HTMLCanvasElement");
  return { canvas, ctx };
}

/** 再利用可能なキャプチャ用キャンバス（動画ループでの毎フレームの生成コストを避ける）。 */
export class FrameCapturer {
  private canvas: Canvas2DLike | null = null;
  private ctx: Ctx2DLike | null = null;
  private width = 0;
  private height = 0;

  private ensureSize(width: number, height: number): void {
    if (this.canvas && this.width === width && this.height === height) return;
    const created = createCanvas(width, height);
    this.canvas = created.canvas;
    this.ctx = created.ctx;
    this.width = width;
    this.height = height;
  }

  /** `video` の現在フレームをRGBAで取り出す。 */
  capture(video: HTMLVideoElement, width: number, height: number): RGBAFrame {
    this.ensureSize(width, height);
    const ctx = this.ctx as Ctx2DLike;
    ctx.drawImage(video, 0, 0, width, height);
    const imageData = ctx.getImageData(0, 0, width, height);
    return { data: imageData.data, width, height };
  }
}

type ScanImageSource = HTMLImageElement | HTMLCanvasElement | ImageBitmap | Blob;

function sourceSize(source: HTMLImageElement | HTMLCanvasElement | ImageBitmap): {
  width: number;
  height: number;
} {
  if ("naturalWidth" in source) {
    return { width: source.naturalWidth, height: source.naturalHeight };
  }
  return { width: source.width, height: source.height };
}

/** `QrScanner.scanImage` 向け: 任意の画像ソースをRGBA画素に変換する。 */
export async function sourceToRGBA(source: ScanImageSource): Promise<RGBAFrame> {
  const drawable = source instanceof Blob ? await createImageBitmap(source) : source;
  const { width, height } = sourceSize(drawable);
  if (!width || !height) {
    throw new Error("scanImage: source has no intrinsic width/height");
  }
  const { ctx } = createCanvas(width, height);
  ctx.drawImage(drawable, 0, 0, width, height);
  const imageData = ctx.getImageData(0, 0, width, height);
  return { data: imageData.data, width, height };
}
