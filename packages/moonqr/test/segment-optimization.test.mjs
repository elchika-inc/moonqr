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

test("auto version selection stays below 100ms for 7,088 alternating byte/numeric runs", () => {
  enc.encode_js("a1".repeat(100), EC.L, 0);
  const text = "a1".repeat(3544);
  const started = performance.now();
  const flat = enc.encode_js(text, EC.L, 0);
  const elapsed = performance.now() - started;
  assert.deepEqual(flat, [], "7,088-character alternating input must report capacity overflow");
  assert.ok(elapsed < 100, `encoding took ${elapsed.toFixed(1)}ms (limit: 100ms)`);
});

test("auto version selection stays below 100ms for 5,356 alternating numeric/alphanumeric runs", () => {
  enc.encode_js("1A".repeat(100), EC.L, 0);
  const text = "1A".repeat(2678);
  const started = performance.now();
  const flat = enc.encode_js(text, EC.L, 0);
  const elapsed = performance.now() - started;
  assert.deepEqual(flat, [], "5,356-character alternating input must report capacity overflow");
  assert.ok(elapsed < 100, `encoding took ${elapsed.toFixed(1)}ms (limit: 100ms)`);
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
