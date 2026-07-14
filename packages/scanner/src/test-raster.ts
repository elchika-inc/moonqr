// テスト専用ラスタライザ（index.test.ts からのみ import される。tsupのエントリ
// （src/index.ts）からは到達しないため配布物には含まれない）。
//
// packages/moonqr/test/lib/rasterize.mjs の簡略版: 回転/透視変換は行わず、
// QrMatrix（公開API）を直接RGBAへ展開する最小実装。scanner側のテストは
// カメラ経由の幾何学的歪みではなくWorker/マルチスケール配線の検証が目的のため、
// 回転等は不要。
//
// applyMonitorLattice は packages/moonqr/test/monitor-lattice.test.mjs
// （Phase 2 Task 12）と同じ手法（白画素にのみ高周波格子を重ねる）の移植。
// 等倍decodeは失敗し、multiScaleDecodeの段階的ボックス平均縮小でのみ成功する
// フィクスチャを作るための道具——ライブフレームのエスカレーション経路と
// scanImageのマルチスケール経路を、実デコーダで検証するために使う。
import type { QrMatrix } from "@elchika-inc/moonqr/encode";

export interface RasterImage {
  data: Uint8Array;
  width: number;
  height: number;
}

export function rasterizeMatrix(
  matrix: QrMatrix,
  opts: { scale?: number; margin?: number } = {},
): RasterImage {
  const scale = opts.scale ?? 4;
  const margin = opts.margin ?? 4;
  const w = (matrix.size + margin * 2) * scale;
  const data = new Uint8Array(w * w * 4).fill(255); // 白背景（RGBA全255）
  for (let my = 0; my < matrix.size; my++) {
    for (let mx = 0; mx < matrix.size; mx++) {
      if (!matrix.get(mx, my)) continue;
      for (let dy = 0; dy < scale; dy++) {
        for (let dx = 0; dx < scale; dx++) {
          const px = (mx + margin) * scale + dx;
          const py = (my + margin) * scale + dy;
          const i = (py * w + px) * 4;
          data[i] = 0;
          data[i + 1] = 0;
          data[i + 2] = 0;
          data[i + 3] = 255;
        }
      }
    }
  }
  return { data, width: w, height: w };
}

/**
 * モニターのサブピクセル格子を模した劣化: 周期 `period` px の格子線上にある
 * 「白画素」だけを暗化する（黒モジュールはそのまま維持）。パラメータは
 * monitor-lattice.test.mjs の実測チューニング値をそのまま踏襲する。
 */
export function applyMonitorLattice(
  image: RasterImage,
  opts: { period?: number; darkenTo?: number; whiteThreshold?: number } = {},
): RasterImage {
  const period = opts.period ?? 9;
  const darkenTo = opts.darkenTo ?? 120;
  const whiteThreshold = opts.whiteThreshold ?? 200;
  const out = new Uint8Array(image.data);
  for (let y = 0; y < image.height; y++) {
    for (let x = 0; x < image.width; x++) {
      if (x % period === 0 || y % period === 0) {
        const i = (y * image.width + x) * 4;
        if ((out[i] ?? 0) >= whiteThreshold) {
          out[i] = darkenTo;
          out[i + 1] = darkenTo;
          out[i + 2] = darkenTo;
        }
      }
    }
  }
  return { data: out, width: image.width, height: image.height };
}
