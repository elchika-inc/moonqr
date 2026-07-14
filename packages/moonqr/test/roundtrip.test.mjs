// Phase 2 Task 9: JSラスタライザ(lib/rasterize.mjs) を挟んだ
// encode_js → rasterize → decode_js のラウンドトリップ結合テスト。
// 「カメラ撮影っぽい歪み」（回転・透視・ノイズ・色反転）を通した状態で
// decode がJS境界から実際に動くかを検証する、デコーダ初のE2E試験。
import { test } from "node:test";
import assert from "node:assert";
import { rasterize } from "./lib/rasterize.mjs";

// ビルド出力パス規約は matrix-parity.test.mjs / version-sweep.test.mjs と同じ
// (core/_build/js/release/build/... が実体。brief記載の core/target/... ではない)
const encodeMod = await import(
  "../../../core/_build/js/release/build/encode/encode.js");
const decodeMod = await import(
  "../../../core/_build/js/release/build/decode/decode.js");
const { encode_js } = encodeMod;
const { decode_js } = decodeMod;

const EC_NUM = { L: 0, M: 1, Q: 2, H: 3 };

function decodeRasterized(flat, opts, invert = false) {
  const { data, width, height } = rasterize(flat, opts);
  const out = decode_js(data, width, height, invert);
  return out === "" ? null : JSON.parse(out);
}

// --- Step 1: ラスタライザ自己テスト（flat行列→スケール展開の手検証） ---
// v1-M "HELLO" の flat[0]=size=21。module(0,0)は左上ファインダの角なので
// 黒(=1)であることが仕様上既知。scale=4, margin=4 (marginPx=16) のとき
// module(0,0) の中心ピクセル座標は (16+2, 16+2)=(18,18) — rasterize が
// 出力キャンバスへ pad=2px の白背景マージンを足すため実測は (18,18)。
// 余白角(2,2)は白であるべき。
test("rasterize: hand-verified scale expansion for v1-M HELLO", () => {
  const flat = encode_js("HELLO", EC_NUM.M, 1);
  assert.notEqual(flat.length, 0, "encode must succeed");
  assert.equal(flat[0], 21, "version1 size must be 21");
  const size = flat[0];
  const getModule = (x, y) => flat[1 + y * size + x];
  assert.equal(getModule(0, 0), 1, "top-left finder corner module is black");

  const { data, width, height } = rasterize(flat, { scale: 4, margin: 4 });
  assert.equal(width, (size + 8) * 4 + 4, "canvas width = (size+2*margin)*scale + 2*pad");
  assert.equal(height, width, "square canvas for rotate=0/no perspective");

  const pxAt = (x, y) => data[(y * width + x) * 4];
  assert.equal(pxAt(18, 18), 30, "module(0,0) center must sample black=30");
  assert.equal(pxAt(2, 2), 220, "canvas corner (outside quiet zone) must be white=220");
});

// --- Step 2a: クリーン往復 — 全EC × 代表バージョンで decode 成功&一致 ---
const VERSIONS = [1, 2, 5, 7, 10, 20, 40];
const ECS = ["L", "M", "Q", "H"];

for (const ec of ECS) {
  for (const v of VERSIONS) {
    test(`roundtrip clean: v${v}-${ec}`, () => {
      const text = `RT-${v}-${ec}`;
      const flat = encode_js(text, EC_NUM[ec], v);
      assert.notEqual(flat.length, 0, `encode_js failed for v${v}-${ec} text=${text}`);
      const result = decodeRasterized(flat, { scale: 4, margin: 4 });
      assert.notEqual(result, null, `decode failed for clean v${v}-${ec}`);
      assert.equal(result.text, text);
      assert.equal(result.version, v);
      assert.equal(result.ecLevel, ec);
    });
  }
}

// --- Step 2b: 回転 — v2-M × {90,180,270,5°,-7°} ---
const ROTATE_TEXT = "ROTATE TEST";
const ROTATE_ANGLES = [90, 180, 270, 5, -7];

for (const angle of ROTATE_ANGLES) {
  test(`roundtrip rotate: v2-M ROTATE TEST @ ${angle}deg`, () => {
    const flat = encode_js(ROTATE_TEXT, EC_NUM.M, 2);
    assert.notEqual(flat.length, 0);
    const result = decodeRasterized(flat, { scale: 4, margin: 4, rotate: angle });
    assert.notEqual(result, null, `decode failed at rotate=${angle}`);
    assert.equal(result.text, ROTATE_TEXT);
  });
}

// --- Step 2c: 透視歪み — v2-M × 4隅オフセット(各隅絶対値8%以内) ---
const PERSPECTIVE_TEXT = "ROTATE TEST";
const PERSPECTIVE_CASES = [
  {
    name: "top-narrow trapezoid",
    // 上辺の左右を内側へ8%寄せる = 真上から見た台形（透視の典型形）
    perspective: { tl: { x: 0.08, y: 0 }, tr: { x: -0.08, y: 0 } },
  },
  {
    name: "single corner recede",
    // 右下角だけを外側へ8%押し出す = 片側から覗き込む透視
    perspective: { br: { x: 0.08, y: 0.08 } },
  },
];

for (const { name, perspective } of PERSPECTIVE_CASES) {
  test(`roundtrip perspective: v2-M ${name}`, () => {
    const flat = encode_js(PERSPECTIVE_TEXT, EC_NUM.M, 2);
    assert.notEqual(flat.length, 0);
    const result = decodeRasterized(flat, { scale: 4, margin: 4, perspective });
    assert.notEqual(result, null, `decode failed for perspective case ${name}`);
    assert.equal(result.text, PERSPECTIVE_TEXT);
  });
}

// --- Step 2b': ジオメトリピン（回転） ---
// decode成功だけでは「デコーダが歪みを復元した」のか「ラスタライザが
// そもそも歪ませていない」のか区別できない（サボタージュレビュー指摘）。
// そこでデコーダが報告する corners を、rasterize.mjs の実装とは独立に
// 手計算した期待画像座標へピン留めする。
//
// 導出（rasterize のヘルパは一切使わない・平面幾何の手計算）:
//   v2-M: size=25, scale=4, margin=4
//   m = margin*scale = 16px（余白）, s = size*scale = 100px（QR部）
//   W = (size+2*margin)*scale = 132px（正準画像の一辺）, pad = 2px
//   正準画像でのQR論理TL角 = (m, m) = (16,16)、BR角 = (m+s, m+s) = (116,116)
//   90度回転（中心(W/2,W/2)=(66,66)、x'=cx-dy, y'=cy+dx）:
//     TL(16,16): dx=dy=-50 → (66+50, 66-50) = (116, 16)
//     BR(116,116): dx=dy=+50 → (66-50, 66+50) = (16, 116)
//   正方形の90度回転はbboxが不変（[0,W]²のまま）なので平行移動は+padのみ:
//     期待 corners[0] = (118, 18) / corners[2] = (18, 118)
//   theta=0サボタージュ時は corners[0]=(18,18) となり100px乖離 → 必ずFAIL。
test("roundtrip geometry pin: rotate=90 moves logical TL to (118,18)", () => {
  const flat = encode_js(ROTATE_TEXT, EC_NUM.M, 2);
  assert.equal(flat[0], 25, "v2 size must be 25 (pin arithmetic depends on it)");
  const result = decodeRasterized(flat, { scale: 4, margin: 4, rotate: 90 });
  assert.notEqual(result, null);
  assert.equal(result.text, ROTATE_TEXT);
  const tol = 8; // 2*scale
  const tl = result.corners[0];
  const br = result.corners[2];
  assert.ok(Math.abs(tl.x - 118) <= tol, `TL.x=${tl.x} expected~118 (rotated)`);
  assert.ok(Math.abs(tl.y - 18) <= tol, `TL.y=${tl.y} expected~18 (rotated)`);
  assert.ok(Math.abs(br.x - 18) <= tol, `BR.x=${br.x} expected~18 (rotated)`);
  assert.ok(Math.abs(br.y - 118) <= tol, `BR.y=${br.y} expected~118 (rotated)`);
});

// --- Step 2c': ジオメトリピン（透視: せん断＝アフィン直接算術） ---
// 上辺を右へ 12% ずらすせん断（tl/tr 同オフセット）。quad は平行四辺形に
// なるため写像はアフィンで、内部点は直接算術で計算できる（ホモグラフィ不要）:
//   quad: p0=(kW,0) p1=(W+kW,0) p2=(W,W) p3=(0,W)（k=0.12）
//   bbox minX=0 → キャンバス平行移動は +pad のみ
//   P(u,v) = p0 + u*(p1-p0) + v*(p3-p0), p1-p0=(W,0), p3-p0=(-kW,W)
//   QR TL: u=v=m/W → x = kW + m - (m/W)*kW + pad, y = m + pad
//   QR BR: u=v=(m+s)/W → 同式
// perspective短絡サボタージュ時は TL.x≈18（乖離13.9px）→ 必ずFAIL。
test("roundtrip geometry pin: perspective shear (affine arithmetic)", () => {
  const flat = encode_js(PERSPECTIVE_TEXT, EC_NUM.M, 2);
  assert.equal(flat[0], 25);
  const k = 0.12;
  const result = decodeRasterized(flat, {
    scale: 4, margin: 4, perspective: { tl: { x: k }, tr: { x: k } },
  });
  assert.notEqual(result, null);
  assert.equal(result.text, PERSPECTIVE_TEXT);
  const W = 132, pad = 2, m = 16, s = 100;
  const expX = (px) => k * W + px - (px / W) * k * W + pad;
  const tol = 4;
  const tl = result.corners[0];
  const br = result.corners[2];
  assert.ok(Math.abs(tl.x - expX(m)) <= tol, `TL.x=${tl.x} expected~${expX(m)}`);
  assert.ok(Math.abs(tl.y - (m + pad)) <= tol, `TL.y=${tl.y} expected~${m + pad}`);
  assert.ok(Math.abs(br.x - expX(m + s)) <= tol, `BR.x=${br.x} expected~${expX(m + s)}`);
  assert.ok(Math.abs(br.y - (m + s + pad)) <= tol, `BR.y=${br.y} expected~${m + s + pad}`);
});

// --- Step 2c'': ジオメトリピン（透視: 台形＝真の射影変換） ---
// せん断ピンはアフィン退化（g=h=0）のため、射影パス（g,h≠0）もピンする。
// 期待値は rasterize.mjs（Heckbert閉形式）とは独立の実装——単位正方形→quad
// の DLT を 8x8 ガウス消去で解く一回限りのスクリプト——で導出してハード
// コードした値（導出条件: W=132, pad=2, quad p0=(0.08W+2,2) p1=(0.92W+2,2)
// p2=(W+2,W+2) p3=(2,W+2)、QR角は u=v=16/132 と 116/132）:
//   QR TL = (25.17, 15.71) / QR TR = (110.83, 15.71) / QR BR = (116.87, 115.38)
// 実測デコーダ出力 (25.55,16.36)/(117.70,116.19) と ~1px で一致し相互検証済み。
// perspective短絡時は TL.x≈18（乖離7.2px > tol4）/ TR.x≈118 → 必ずFAIL。
test("roundtrip geometry pin: perspective trapezoid (projective, DLT-derived)", () => {
  const flat = encode_js(PERSPECTIVE_TEXT, EC_NUM.M, 2);
  assert.equal(flat[0], 25);
  const result = decodeRasterized(flat, {
    scale: 4, margin: 4,
    perspective: { tl: { x: 0.08, y: 0 }, tr: { x: -0.08, y: 0 } },
  });
  assert.notEqual(result, null);
  assert.equal(result.text, PERSPECTIVE_TEXT);
  const tol = 4;
  const tl = result.corners[0];
  const tr = result.corners[1];
  const br = result.corners[2];
  assert.ok(Math.abs(tl.x - 25.17) <= tol, `TL.x=${tl.x} expected~25.17`);
  assert.ok(Math.abs(tl.y - 15.71) <= tol, `TL.y=${tl.y} expected~15.71`);
  assert.ok(Math.abs(tr.x - 110.83) <= tol, `TR.x=${tr.x} expected~110.83`);
  assert.ok(Math.abs(br.x - 116.87) <= tol, `BR.x=${br.x} expected~116.87`);
  assert.ok(Math.abs(br.y - 115.38) <= tol, `BR.y=${br.y} expected~115.38`);
});

// --- Step 2d: ノイズ — v2-M × ノイズ振幅30, seed固定 ---
test("roundtrip noise: v2-M amplitude=30 seed=42", () => {
  const flat = encode_js("ROTATE TEST", EC_NUM.M, 2);
  assert.notEqual(flat.length, 0);
  const result = decodeRasterized(flat, { scale: 4, margin: 4, noise: 30, seed: 42 });
  assert.notEqual(result, null, "decode failed under noise=30");
  assert.equal(result.text, "ROTATE TEST");
});

// --- Step 2e: 色反転 — invert=false は失敗、invert=true は成功 ---
test("roundtrip inverted: v2-M black/white swapped", () => {
  const flat = encode_js("INVERT ME", EC_NUM.M, 2);
  assert.notEqual(flat.length, 0);
  const { data, width, height } = rasterize(flat, {
    scale: 4, margin: 4, black: 220, white: 30,
  });
  assert.equal(decode_js(data, width, height, false), "", "must NOT decode without invert");
  const out = decode_js(data, width, height, true);
  assert.notEqual(out, "", "must decode with invert=true");
  const parsed = JSON.parse(out);
  assert.equal(parsed.text, "INVERT ME");
});

// --- Step 2f: corners sanity — クリーン1ケースで4隅の位置を確認 ---
test("roundtrip corners sanity: v2-M clean", () => {
  const flat = encode_js("RT-2-M", EC_NUM.M, 2);
  assert.notEqual(flat.length, 0);
  const size = flat[0];
  const result = decodeRasterized(flat, { scale: 4, margin: 4 });
  assert.notEqual(result, null);
  assert.equal(result.corners.length, 4);
  // rasterize は rotate=0/perspective無しのとき pad=2px の白背景を追加して
  // 平行移動するため、期待座標は (margin*scale + pad, ...)。
  const marginPx = 4 * 4;
  const pad = 2;
  const expectedTl = marginPx + pad;
  const expectedBr = marginPx + pad + size * 4;
  const tl = result.corners[0];
  const br = result.corners[2];
  assert.ok(Math.abs(tl.x - expectedTl) <= 8, `TL.x=${tl.x} expected~${expectedTl}`);
  assert.ok(Math.abs(tl.y - expectedTl) <= 8, `TL.y=${tl.y} expected~${expectedTl}`);
  assert.ok(Math.abs(br.x - expectedBr) <= 8, `BR.x=${br.x} expected~${expectedBr}`);
  assert.ok(Math.abs(br.y - expectedBr) <= 8, `BR.y=${br.y} expected~${expectedBr}`);
});
