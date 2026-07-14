// Phase 2 Task 12: モニター格子写真対応の回帰テスト。
//
// root cause: モニター表示のQRをスマホで撮影すると、モニターのサブピクセル
// 格子（白いはずの領域に写り込む高周波の暗い格子線）が乗る。jsQR方式の
// ブロック二値化はこれを「ほぼ50%speckle」と誤認しファインダを検出できなく
// なる（jsQR npm でも同一の失敗＝自前decode_jsのコア二値化/ロケータは無改修
// でjsQRとパリティのまま）。素朴な単発縮小はこの格子をエイリアシングして
// むしろ悪化させるため、2x2ボックス平均による段階的な半分縮小
// （@elchika-inc/moonqr-scanner の multiScaleDecode）で解決する。詳細は
// bench/RESULT.md Task 12 節を参照。
//
// このテストは実写真を使わず、rasterize() で生成したQR画像に合成の
// サブピクセル格子を重ねたフィクスチャで失敗モードを再現する（コミット
// 可能・決定的）。
//
// Phase 3 Task 5: 旧 lib/multiscale.mjs（手動同期の複製）は削除し、
// packages/scanner/src/multiscale.ts を唯一の実装として直接importする。
// Node 24 はネイティブTS型ストリッピングを持つため、node --test から
// .ts を直接importでき、ビルド成果物への依存を持ち込まずに済む。
import { test } from "node:test";
import assert from "node:assert";
import jsQR from "jsqr";
import { rasterize } from "./lib/rasterize.mjs";
import { multiScaleDecode } from "../../scanner/src/multiscale.ts";

// ビルド出力パス規約は roundtrip.test.mjs 等と同じ。
const encodeMod = await import(
  "../../../core/_build/js/release/build/encode/encode.js");
const decodeMod = await import(
  "../../../core/_build/js/release/build/decode/decode.js");
const { encode_js } = encodeMod;
const { decode_js } = decodeMod;

const EC_NUM = { L: 0, M: 1, Q: 2, H: 3 };

// フィクスチャ固定パラメータ（scratchpadで scale×period×darkenTo の格子探索を
// 行い、direct decode_js FAIL・jsQR npm FAIL・multiScaleDecode SUCCESS の
// 3条件を同時に満たす最小限の組み合わせとして選定した）:
//   scale=28 (モジュールあたり28px、写真スケール相当800px超)
//   period=9 (9px周期の格子線。実測モニターのサブピクセル周期を模した値)
//   darkenTo=120 (白220→120に暗化。黒モジュールはそのまま=30)
//   whiteThreshold=200 (白画素の判定閾値。黒画素を誤って暗化しないためのガード)
const LATTICE_PERIOD = 9;
const LATTICE_DARKEN_TO = 120;
const LATTICE_WHITE_THRESHOLD = 200;
const RASTER_SCALE = 28;

// モニターのサブピクセル格子を模した劣化: (x%period==0 || y%period==0) の
// 格子線上にある「白画素」だけを暗化する。黒画素（QRの黒モジュール）は
// そのまま維持する——モニター格子は「白いはずの領域に写り込む」現象であり
// 黒領域には影響しないため。
function applyMonitorLattice(data, width, height, {
  period = LATTICE_PERIOD,
  darkenTo = LATTICE_DARKEN_TO,
  whiteThreshold = LATTICE_WHITE_THRESHOLD,
} = {}) {
  const out = new Uint8Array(data); // コピー（rasterize()の出力を破壊しない）
  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      if (x % period === 0 || y % period === 0) {
        const i = (y * width + x) * 4;
        if (out[i] >= whiteThreshold) {
          out[i] = darkenTo;
          out[i + 1] = darkenTo;
          out[i + 2] = darkenTo;
          // alphaはそのまま(255)
        }
      }
    }
  }
  return out;
}

function makeLatticeFixture(text = "HELLO", ec = "M", version = 1) {
  const flat = encode_js(text, EC_NUM[ec], version);
  assert.notEqual(flat.length, 0, "encode_js must succeed for fixture generation");
  const { data, width, height } = rasterize(flat, { scale: RASTER_SCALE, margin: 4 });
  const lattice = applyMonitorLattice(data, width, height);
  return { text, data: lattice, width, height };
}

function decodeFn(d, w, h) {
  const out = decode_js(d, w, h, true);
  return out === "" ? null : JSON.parse(out);
}

test("monitor lattice fixture: direct decode_js FAILS (reproduces the failure mode)", () => {
  const { data, width, height } = makeLatticeFixture();
  const out = decode_js(data, width, height, true);
  assert.equal(
    out,
    "",
    "lattice fixture must defeat single-scale decode_js — if this fails, " +
      "the fixture no longer reproduces the monitor-photo failure mode and " +
      "LATTICE_PERIOD/LATTICE_DARKEN_TO must be strengthened",
  );
});

test("monitor lattice fixture: jsQR npm ALSO fails (core parity proof)", () => {
  const { data, width, height } = makeLatticeFixture();
  const result = jsQR(data, width, height, { inversionAttempts: "attemptBoth" });
  assert.equal(
    result,
    null,
    "jsQR npm must also fail on the lattice fixture — this proves our core " +
      "binarizer/locator is at exact parity with jsQR and is NOT the cause " +
      "(the fix lives entirely in the multi-scale retry wrapper, not core/src/decode/)",
  );
});

test("monitor lattice fixture: multiScaleDecode SUCCEEDS and returns the right text", () => {
  const { text, data, width, height } = makeLatticeFixture();
  const outcome = multiScaleDecode(decodeFn, data, width, height);
  assert.notEqual(
    outcome,
    null,
    "multiScaleDecode must succeed on the lattice fixture via progressive halving",
  );
  assert.equal(outcome.result.text, text);
  assert.ok(outcome.scale >= 2, `expected halving to have occurred (scale=${outcome.scale})`);
});

// 事前半減（メモリガード）のスケール計上の回帰テスト。
// decode_js の16Mピクセル上限（16,777,216）を超える入力ではメモリガードが
// ループ開始前に半減を行う。この半減が返り値の scale に計上されないと、
// 「事前半減のおかげで初めて成功した」ケースが scale=1（無縮小成功）として
// 報告されてしまう（48MP級スマホ写真 8064x6048 で日常的に発動する経路）。
// クリーンなQR（格子なし）を 4200x4200（=17.64Mピクセル > 16M）の白キャンバス
// に埋め込む——事前半減1回で 2100x2100 になり初回試行で成功するはずなので、
// 「初回のループ内試行で成功しても scale が事前半減を反映して >= 2」を固定する。
test("pre-halve memory guard: halvings are counted in the returned scale (>16M px input)", () => {
  const text = "HELLO";
  const flat = encode_js(text, EC_NUM.M, 1);
  assert.notEqual(flat.length, 0, "encode_js must succeed");
  // scale=8: 事前半減で4px/moduleになってもクリーンQRなら余裕でデコード可能
  const qr = rasterize(flat, { scale: 8, margin: 4 });

  const BIG = 4200; // 4200*4200 = 17,640,000 > 16*1024*1024 = 16,777,216
  assert.ok(BIG * BIG > 16 * 1024 * 1024, "canvas must exceed the 16M pixel limit");
  const big = new Uint8Array(BIG * BIG * 4).fill(255); // 全面白（alpha込み）
  // QRを中央付近に埋め込む
  const ox = Math.floor((BIG - qr.width) / 2);
  const oy = Math.floor((BIG - qr.height) / 2);
  for (let y = 0; y < qr.height; y++) {
    const srcRow = y * qr.width * 4;
    const dstRow = ((oy + y) * BIG + ox) * 4;
    big.set(qr.data.subarray(srcRow, srcRow + qr.width * 4), dstRow);
  }

  const outcome = multiScaleDecode(decodeFn, big, BIG, BIG);
  assert.notEqual(outcome, null, "multiScaleDecode must succeed on the oversized clean QR");
  assert.equal(outcome.result.text, text);
  assert.ok(
    outcome.width * outcome.height <= 16 * 1024 * 1024,
    "decode must have happened within the 16M pixel limit",
  );
  assert.ok(
    outcome.scale >= 2,
    `pre-halve halvings must be counted in the returned scale ` +
      `(scale=${outcome.scale}, finalSize=${outcome.width}x${outcome.height})`,
  );
  // scale と実サイズの整合: 総縮小率 scale に対して final width = floor寄りの
  // BIG/scale になっているはず（halveRGBAは各段で floor(w/2)）。
  assert.equal(outcome.width, Math.floor(BIG / outcome.scale));
});

// 小スケール優先の試行順の回帰テスト（perf対応）。
// カメラ写真は小スケールでデコードできることが大半なのに、大スケールから試すと
// ネイティブ解像度の失敗試行（16Mピクセルで数秒）を毎回払う。multiScaleDecode は
// 半減ピラミッドを構築後、画素数の少ないレベルから昇順に試行しなければならない。
// lattice フィクスチャは 816px → ピラミッドの scale は [1,2,4,8]（150px 未満で
// 打ち切り）なので、最初の試行は必ず scale=8（最小レベル 102px）であること、
// および成功がネイティブ解像度（scale=1）の試行前に起きること（=フル解像度の
// 失敗コストを払っていないこと）を固定する。
test("small-first ordering: smallest pyramid level attempted first, no full-res attempt when small succeeds", () => {
  const { text, data, width, height } = makeLatticeFixture();
  assert.equal(width, 816, "fixture width must be 816 (pyramid scales [1,2,4,8])");
  const outcome = multiScaleDecode(decodeFn, data, width, height);
  assert.notEqual(outcome, null, "multiScaleDecode must succeed on the lattice fixture");
  assert.equal(outcome.result.text, text);

  // 最初の試行は最小レベル（最大 scale）
  assert.ok(Array.isArray(outcome.attemptedScales), "outcome must expose attemptedScales");
  assert.equal(
    outcome.attemptedScales[0],
    8,
    `first attempt must be the smallest pyramid level (scale=8), got ` +
      `attemptedScales=[${outcome.attemptedScales.join(",")}]`,
  );
  // 昇順（画素数の少ない順）= scale は単調減少（各段でちょうど半分）
  for (let i = 1; i < outcome.attemptedScales.length; i++) {
    assert.equal(
      outcome.attemptedScales[i],
      outcome.attemptedScales[i - 1] / 2,
      "attempts must ascend in pixel count (scale halves each step)",
    );
  }
  // 小スケールで成功した以上、ネイティブ解像度（scale=1）の高価な失敗試行を
  // 払っていないこと
  assert.ok(
    !outcome.attemptedScales.includes(1),
    `full-resolution attempt must not happen when a smaller scale succeeds ` +
      `(attemptedScales=[${outcome.attemptedScales.join(",")}])`,
  );
});
