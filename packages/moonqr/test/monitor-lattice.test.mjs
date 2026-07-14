// Phase 2 Task 12: モニター格子写真対応の回帰テスト。
//
// root cause: モニター表示のQRをスマホで撮影すると、モニターのサブピクセル
// 格子（白いはずの領域に写り込む高周波の暗い格子線）が乗る。jsQR方式の
// ブロック二値化はこれを「ほぼ50%speckle」と誤認しファインダを検出できなく
// なる（jsQR npm でも同一の失敗＝自前decode_jsのコア二値化/ロケータは無改修
// でjsQRとパリティのまま）。素朴な単発縮小はこの格子をエイリアシングして
// むしろ悪化させるため、2x2ボックス平均による段階的な半分縮小
// （lib/multiscale.mjs の multiScaleDecode）で解決する。詳細は
// bench/RESULT.md Task 12 節を参照。
//
// このテストは実写真を使わず、rasterize() で生成したQR画像に合成の
// サブピクセル格子を重ねたフィクスチャで失敗モードを再現する（コミット
// 可能・決定的）。
import { test } from "node:test";
import assert from "node:assert";
import jsQR from "jsqr";
import { rasterize } from "./lib/rasterize.mjs";
import { multiScaleDecode } from "./lib/multiscale.mjs";

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
