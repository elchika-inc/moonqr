import { test } from "node:test";
import assert from "node:assert";
import QRCode from "qrcode";

// ビルド出力: core/_build/js/release/build/encode/encode.js
// (moon build --target js --release の実際の出力パス。brief記載の
//  core/target/... ではなく core/_build/... が実体。matrix-parity.test.mjs
//  と同じ規約でパスを揃える)
const mod = await import(
  "../../../core/_build/js/release/build/encode/encode.js");
const EC = { L: 0, M: 1, Q: 2, H: 3 };

// マスクも強制して全行列を厳密比較する（readMask 不要の決定的比較ではなく、
// 自前が選んだマスクに qrcode npm 側を合わせて再生成することで全160組を
// 全モジュール比較する）
for (let version = 1; version <= 40; version++) {
  for (const ec of ["L", "M", "Q", "H"]) {
    test(`sweep v${version}-${ec}`, () => {
      const text = `V${version}${ec}`; // 短いテキスト（全バージョンに収まる）
      const ref = QRCode.create(text, {
        errorCorrectionLevel: ec, version, maskPattern: 3,
      });
      const flat = mod.encode_js(text, EC[ec], version);
      assert.notEqual(flat.length, 0);
      const size = ref.modules.size;
      assert.equal(flat[0], size);
      // 自前はマスク自動選択のため、mask 3 を選ぶとは限らない。
      // → データ・EC・機能パターンの一致は「マスク一致時のみ全比較」では
      //   160組で保証できないので、ここでは encode_js に version を強制した上で
      //   qrcode npm 側を「自前が選んだマスク」に合わせて再生成して全比較する。
      const ourMask = readMask(flat);
      const ref2 = QRCode.create(text, {
        errorCorrectionLevel: ec, version, maskPattern: ourMask,
      });
      for (let y = 0; y < size; y++) for (let x = 0; x < size; x++) {
        assert.equal(flat[1 + y * size + x], ref2.modules.get(y, x) ? 1 : 0,
          `v${version}-${ec} mismatch at (${x},${y}) ourMask=${ourMask}`);
      }
    });
  }
}

function readMask(flat) {
  const size = flat[0];
  const get = (x, y) => flat[1 + y * size + x];
  const coords = [
    [8, 0], [8, 1], [8, 2], [8, 3], [8, 4], [8, 5], [8, 7], [8, 8],
    [7, 8], [5, 8], [4, 8], [3, 8], [2, 8], [1, 8], [0, 8],
  ];
  let bits = 0;
  coords.forEach(([x, y], i) => { bits |= get(x, y) << i; });
  return ((bits ^ 0x5412) >> 10) & 0b111;
}
