// 純JSラスタライザ（canvas不使用）: encode_js の flat 行列
// ([size, ...row-major 0/1] 、 flat[1 + y*size + x] = module(x,y))
// をカメラ撮影相当のRGBA画素に展開する。Phase 2 Task 9 のテスト基盤。
//
// パイプライン:
//   1. 「正準画像」= QR行列 + margin を scale 倍したWxW正方形（W=(size+2*margin)*scale）
//   2. 中心まわりに rotate 度回転（任意角）→ 回転後の4隅座標
//   3. perspective が指定されていれば4隅を個別にオフセット（フラクション*W）
//      → 最終的な出力先の四角形（quad）
//   4. quad のbounding boxに収まる出力キャンバスを確保し、quadを平行移動
//   5. 単位正方形→quad の射影変換行列（Heckbert方式）を組み立てて逆行列を取り、
//      出力画素ごとに正準画像上の座標へ逆写像（nearest-neighbor）
//   6. モジュール範囲外は白、範囲内は黒/白 + seeded PRNG (mulberry32) ノイズ
//
// mulberry32 は bench/gen-frame.mjs からコピー（tree跨ぎimport回避）。
// Date.now()/Math.random() は使用しない。

function mulberry32(seed) {
  let a = seed >>> 0;
  return () => {
    a |= 0;
    a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

// 単位正方形 (0,0)(1,0)(1,1)(0,1) → quad=[p0,p1,p2,p3] への射影変換行列を
// 3x3 (row-major, [a,b,c,d,e,f,g,h,1]) で返す。quad が平行四辺形（アフィンで
// 表現可能）なら g=h=0 に落ちる（Paul Heckbert, "Fundamentals of Texture
// Mapping and Image Warping" の square-to-quad 導出）。
function squareToQuadMatrix(quad) {
  const [p0, p1, p2, p3] = quad;
  const x0 = p0.x, y0 = p0.y;
  const x1 = p1.x, y1 = p1.y;
  const x2 = p2.x, y2 = p2.y;
  const x3 = p3.x, y3 = p3.y;
  const dx1 = x1 - x2, dx2 = x3 - x2, dx3 = x0 - x1 + x2 - x3;
  const dy1 = y1 - y2, dy2 = y3 - y2, dy3 = y0 - y1 + y2 - y3;
  let g = 0;
  let h = 0;
  if (Math.abs(dx3) > 1e-9 || Math.abs(dy3) > 1e-9) {
    const det = dx1 * dy2 - dx2 * dy1;
    g = (dx3 * dy2 - dx2 * dy3) / det;
    h = (dx1 * dy3 - dx3 * dy1) / det;
  }
  const a = x1 * g + x1 - x0;
  const b = x3 * h + x3 - x0;
  const c = x0;
  const d = y1 * g + y1 - y0;
  const e = y3 * h + y3 - y0;
  const f = y0;
  return [a, b, c, d, e, f, g, h, 1];
}

// 3x3行列の逆行列（アジュゲート/行列式方式）。
function invert3x3([a, b, c, d, e, f, g, h, i]) {
  const det = a * (e * i - f * h) - b * (d * i - f * g) + c * (d * h - e * g);
  const A = e * i - f * h, B = c * h - b * i, C = b * f - c * e;
  const D = f * g - d * i, E = a * i - c * g, F = c * d - a * f;
  const G = d * h - e * g, H = b * g - a * h, I = a * e - b * d;
  return [
    A / det, B / det, C / det,
    D / det, E / det, F / det,
    G / det, H / det, I / det,
  ];
}

/**
 * @param {number[]} flat encode_js の戻り値 ([size, ...0/1])
 * @param {object} opts
 * @param {number} [opts.scale=4] モジュールあたりの出力px
 * @param {number} [opts.margin=4] 余白（モジュール単位）
 * @param {number} [opts.rotate=0] 中心まわりの回転角（度、任意値可）
 * @param {{tl?:{x,y},tr?:{x,y},br?:{x,y},bl?:{x,y}}|null} [opts.perspective=null]
 *   4隅のオフセット（Wに対するフラクション）。未指定隅は{x:0,y:0}。
 * @param {number} [opts.noise=0] ノイズ振幅（±noiseの一様乱数を加算）
 * @param {number} [opts.seed=42] mulberry32のシード
 * @param {number} [opts.black=30] 黒モジュールの階調値
 * @param {number} [opts.white=220] 白モジュール/背景の階調値
 * @returns {{data: Uint8Array, width: number, height: number}} RGBA画素
 */
export function rasterize(flat, opts = {}) {
  const {
    scale = 4,
    margin = 4,
    rotate = 0,
    perspective = null,
    noise = 0,
    seed = 42,
    black = 30,
    white = 220,
  } = opts;

  const size = flat[0];
  const getModule = (mx, my) => flat[1 + my * size + mx];
  const w = (size + margin * 2) * scale; // 正準画像の一辺(px)

  const centerX = w / 2, centerY = w / 2;
  const theta = (rotate * Math.PI) / 180;
  const cos = Math.cos(theta), sin = Math.sin(theta);
  const rotatePoint = (x, y) => {
    const dx = x - centerX, dy = y - centerY;
    return { x: centerX + dx * cos - dy * sin, y: centerY + dx * sin + dy * cos };
  };

  // 正準画像の4隅: TL,TR,BR,BL（単位正方形 (0,0)(1,0)(1,1)(0,1) に対応）
  let corners = [
    rotatePoint(0, 0), rotatePoint(w, 0), rotatePoint(w, w), rotatePoint(0, w),
  ];

  if (perspective) {
    const keys = ["tl", "tr", "br", "bl"];
    corners = corners.map((p, idx) => {
      const off = perspective[keys[idx]] || {};
      return { x: p.x + (off.x || 0) * w, y: p.y + (off.y || 0) * w };
    });
  }

  const xs = corners.map((p) => p.x);
  const ys = corners.map((p) => p.y);
  const minX = Math.min(...xs), maxX = Math.max(...xs);
  const minY = Math.min(...ys), maxY = Math.max(...ys);
  const pad = 2; // 端の白背景を確保するための余白px
  const width = Math.ceil(maxX - minX) + pad * 2;
  const height = Math.ceil(maxY - minY) + pad * 2;
  const tx = -minX + pad, ty = -minY + pad;
  const quad = corners.map((p) => ({ x: p.x + tx, y: p.y + ty }));

  const m = squareToQuadMatrix(quad);
  const mInv = invert3x3(m);

  const rand = mulberry32(seed);
  const data = new Uint8Array(width * height * 4);

  for (let py = 0; py < height; py++) {
    for (let px = 0; px < width; px++) {
      const ptX = px + 0.5, ptY = py + 0.5;
      const uNum = mInv[0] * ptX + mInv[1] * ptY + mInv[2];
      const vNum = mInv[3] * ptX + mInv[4] * ptY + mInv[5];
      const wNum = mInv[6] * ptX + mInv[7] * ptY + mInv[8];
      const u = uNum / wNum, v = vNum / wNum;
      const sx = u * w, sy = v * w;

      let val = white;
      if (sx >= 0 && sx < w && sy >= 0 && sy < w) {
        const mx = Math.floor((sx - margin * scale) / scale);
        const my = Math.floor((sy - margin * scale) / scale);
        if (mx >= 0 && mx < size && my >= 0 && my < size) {
          val = getModule(mx, my) ? black : white;
        }
      }

      if (noise > 0) {
        val = Math.max(0, Math.min(255, Math.round(val + noise * (rand() * 2 - 1))));
      }

      const i = (py * width + px) * 4;
      data[i] = val;
      data[i + 1] = val;
      data[i + 2] = val;
      data[i + 3] = 255;
    }
  }

  return { data, width, height };
}
