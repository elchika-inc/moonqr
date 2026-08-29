import { test } from "node:test";
import assert from "node:assert/strict";
import QRCode from "qrcode";
import jsQR from "jsqr";
import { createRequire } from "node:module";
import { performance } from "node:perf_hooks";

const require = createRequire(import.meta.url);
const enc = require("../../../core/_build/js/release/build/encode/encode.js");
const dec = require("../../../core/_build/js/release/build/decode/decode.js");

const EC = { L: 0, M: 1, Q: 2, H: 3 };

// 最小バージョンを求める（encode_js は version を明示指定する形なので線形試行）
function minVersion(text, ec) {
  for (let v = 1; v <= 40; v++) {
    const flat = enc.encode_js(text, ec, v);
    if (flat && flat.length > 0) return v;
  }
  return null;
}

// 効果が出る形（byte に落ちる文字 + 長い数字列）を中心に、
// 効果が出ない形（単一モード・短い数字列）も混ぜる
const digits = (n) =>
  Array.from({ length: n }, (_, i) => String((i * 7) % 10)).join("");

const CASES = [
  "https://ex.com/id/12345",
  "https://ex.com/id/1234567890",
  "https://ex.com/id/" + digits(30),
  "https://ex.com/id/" + digits(100),
  "注文番号は" + digits(30) + "です",
  "HTTPS://EX.COM/ID/" + digits(60),
  "HELLO WORLD",
  "1234567890",
  "hello",
  "ABC12DEF",
  "SKU-1234567890-ABCDEFGHIJ-9876543210",
];

test("never larger than qrcode npm", () => {
  const losses = [];
  for (const text of CASES) {
    for (const ec of ["L", "M", "Q", "H"]) {
      const ours = minVersion(text, EC[ec]);
      const ref = QRCode.create(text, { errorCorrectionLevel: ec }).version;
      assert.ok(ours !== null, `moonqr failed to encode: ${text}`);
      if (ours > ref) losses.push(`${ec} v${ours}>v${ref}: ${text}`);
    }
  }
  assert.deepEqual(losses, [], `qrcode npm に負けたケース:\n${losses.join("\n")}`);
});

// 行列を 4px/セル・margin 4 セルの RGBA バッファへ展開する
function rasterize(flat) {
  const size = flat[0];
  const CELL = 4;
  const MARGIN = 4;
  const px = (size + MARGIN * 2) * CELL;
  const data = new Uint8Array(px * px * 4).fill(255);
  for (let y = 0; y < size; y++) {
    for (let x = 0; x < size; x++) {
      if (flat[1 + y * size + x] === 0) continue;
      for (let dy = 0; dy < CELL; dy++) {
        for (let dx = 0; dx < CELL; dx++) {
          const i = (((y + MARGIN) * CELL + dy) * px + (x + MARGIN) * CELL + dx) * 4;
          data[i] = data[i + 1] = data[i + 2] = 0;
        }
      }
    }
  }
  return { data, px };
}

test("split QR codes round-trip through our own decoder", () => {
  for (const text of CASES) {
    const v = minVersion(text, EC.M);
    const flat = enc.encode_js(text, EC.M, v);
    const { data, px } = rasterize(flat);
    const raw = dec.decode_js(data, px, px, false);
    assert.notEqual(raw, "", `our decoder failed to read: ${text}`);
    const got = JSON.parse(raw);
    assert.equal(got.text, text, `round-trip mismatch: ${text}`);
  }
});

test("split QR codes are readable by jsQR (independent decoder)", () => {
  for (const text of CASES) {
    const v = minVersion(text, EC.M);
    const flat = enc.encode_js(text, EC.M, v);
    const { data, px } = rasterize(flat);
    const got = jsQR(new Uint8ClampedArray(data), px, px);
    assert.ok(got, `jsQR failed to read: ${text}`);
    assert.equal(got.data, text, `jsQR mismatch: ${text}`);
  }
});

test("auto version selection matches forced search within 5 seconds", () => {
  const text = "a1".repeat(500);
  const autoStarted = performance.now();
  const flat = enc.encode_js(text, EC.M, 0);
  const autoElapsed = performance.now() - autoStarted;
  const forcedVersion = minVersion(text, EC.M);
  assert.notEqual(flat.length, 0, "alternating 1,000-char input must fit a QR code");
  assert.equal((flat[0] - 17) / 4, forcedVersion, "auto and forced search must choose the same version");
  assert.ok(autoElapsed < 5_000, `encoding took ${autoElapsed.toFixed(0)}ms (limit: 5000ms)`);
});

// 旧 O(n^2) 実装は開発機で中央値約 889ms、CI は開発機の 3〜4 倍遅いため、
// 退化時は CI で 3,000ms 以上になる。一方、現行 O(n) 実装は開発機で約
// 20〜40ms、CI で約 130ms。1,000ms は現状に約 7 倍の余裕を持たせながら、
// O(n^2) 退化とは 3 倍以上分離する。旧 100ms は開発機の値だけに基づき、
// CI で偽陽性になったため引き上げた。
test("auto version selection stays below 1000ms for 7,088 alternating byte/numeric runs", () => {
  enc.encode_js("a1".repeat(100), EC.L, 0);
  const text = "a1".repeat(3544);
  const started = performance.now();
  const flat = enc.encode_js(text, EC.L, 0);
  const elapsed = performance.now() - started;
  assert.deepEqual(flat, [], "7,088-character alternating input must report capacity overflow");
  assert.ok(elapsed < 1_000, `encoding took ${elapsed.toFixed(1)}ms (limit: 1000ms)`);
});

test("auto version selection stays below 1000ms for 5,356 alternating numeric/alphanumeric runs", () => {
  enc.encode_js("1A".repeat(100), EC.L, 0);
  const text = "1A".repeat(2678);
  const started = performance.now();
  const flat = enc.encode_js(text, EC.L, 0);
  const elapsed = performance.now() - started;
  assert.deepEqual(flat, [], "5,356-character alternating input must report capacity overflow");
  assert.ok(elapsed < 1_000, `encoding took ${elapsed.toFixed(1)}ms (limit: 1000ms)`);
});

test("alternating-run planning stays below three times a single-run baseline", () => {
  const alternating = "a1".repeat(3544);
  const singleRun = "1".repeat(7089);
  enc.encode_js(alternating, EC.L, 0);
  enc.encode_js(singleRun, EC.L, 0);

  const medianElapsed = (text) => {
    const samples = [];
    for (let i = 0; i < 7; i++) {
      const started = performance.now();
      enc.encode_js(text, EC.L, 0);
      samples.push(performance.now() - started);
    }
    samples.sort((a, b) => a - b);
    return samples[3];
  };

  const alternatingMedian = medianElapsed(alternating);
  const singleRunMedian = medianElapsed(singleRun);
  // singleRun は v40 の行列を組み立て、alternating は容量超過で終了するため、
  // 両者は等価な仕事量ではない。これは O(n^2) 退化を検知する粗い上限としてのみ使う。
  assert.ok(
    alternatingMedian < singleRunMedian * 3,
    `alternating median ${alternatingMedian.toFixed(1)}ms exceeded 3x single-run median ${singleRunMedian.toFixed(1)}ms`,
  );
});

test("obviously over-capacity input is rejected before segment planning", () => {
  const text = "a1".repeat(10_000);
  const started = performance.now();
  assert.deepEqual(enc.encode_js(text, EC.L, 0), [], "auto version must reject over-capacity input");
  assert.deepEqual(enc.encode_js(text, EC.L, 40), [], "explicit version must reject over-capacity input");
  const elapsed = performance.now() - started;
  assert.ok(elapsed < 1_000, `over-capacity rejection took ${elapsed.toFixed(0)}ms (limit: 1000ms)`);
});

test("Model 2 absolute capacity boundary is inclusive", () => {
  const atLimit = "1".repeat(7089);
  const overLimit = atLimit + "1";
  for (const version of [0, 40]) {
    const flat = enc.encode_js(atLimit, EC.L, version);
    assert.equal(flat[0], 177, `${version || "auto"} must accept 7,089 Numeric characters`);
    assert.equal(flat.length, 1 + 177 * 177, `${version || "auto"} must return a complete matrix`);
    assert.deepEqual(
      enc.encode_js(overLimit, EC.L, version),
      [],
      `${version || "auto"} must reject 7,090 Numeric characters`,
    );
  }
});
