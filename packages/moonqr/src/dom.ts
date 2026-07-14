// moonqr の dom サブパスエントリ（`@elchika-inc/moonqr/dom`）。
//
// canvas への描画のみを行う純粋な DOM ヘルパ。MoonBit 成果物（encode.js/decode.js）への
// 依存を一切持たないため、tsup のビルド閉包にそれらが混入することはない（encode/dom を
// 併用しても encode の閉包サイズには影響しない）。
import type { QrMatrix, SvgOptions } from "./types.js";

/**
 * QR 行列を canvas に描画する。canvas のサイズを設定し、白背景 → 黒モジュールの順に塗る。
 * `toSvgString`（src/encode.ts）と同じ余白・セルサイズの規約（margin 既定4, cell 既定4）。
 */
export function toCanvas(matrix: QrMatrix, canvas: HTMLCanvasElement, options?: SvgOptions): void {
  const margin = options?.margin ?? 4;
  const cell = options?.cell ?? 4;
  const total = (matrix.size + margin * 2) * cell;

  canvas.width = total;
  canvas.height = total;

  const ctx = canvas.getContext("2d");
  if (!ctx) return;

  ctx.fillStyle = "#fff";
  ctx.fillRect(0, 0, total, total);

  ctx.fillStyle = "#000";
  for (let y = 0; y < matrix.size; y++) {
    for (let x = 0; x < matrix.size; x++) {
      if (matrix.get(x, y)) {
        ctx.fillRect((x + margin) * cell, (y + margin) * cell, cell, cell);
      }
    }
  }
}
