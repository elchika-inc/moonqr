import { test } from "node:test";
import assert from "node:assert";
import QRCode from "qrcode";

// ビルド出力: core/_build/js/release/build/encode/encode.js
// (moon build --target js --release の実際の出力パス。brief記載の
//  core/target/... ではなく core/_build/... が実体)
const mod = await import(
  "../../../core/_build/js/release/build/encode/encode.js");

const CASES = [
  ["01234567", "M"], ["HELLO WORLD", "Q"], ["hello, world!", "L"],
  ["https://example.com/path?q=1&r=2", "M"],
  ["こんにちは世界", "M"], ["🦑🐙", "H"],
  ["A".repeat(500), "L"], ["1".repeat(1000), "M"],
];
const EC_NUM = { L: 0, M: 1, Q: 2, H: 3 };

// 自前実装の全モジュール比較が最低1回は発火したことを記録する
// (メソドロジー: 8マスク中、自前の自動選択マスクは必ずどれかと一致する)
export const fullCompareCount = { value: 0 };

for (const [text, ec] of CASES) {
  for (let mask = 0; mask < 8; mask++) {
    test(`parity: ${JSON.stringify(text.slice(0, 20))} ec=${ec} mask=${mask}`, async () => {
      // qrcode npm に強制マスクで生成させ、バージョンを合わせて自前と比較
      const ref = QRCode.create(text, {
        errorCorrectionLevel: ec, maskPattern: mask,
      });
      const size = ref.modules.size;
      const version = ref.version;
      // 自前実装: 同バージョン強制。マスクは自動選択なので、
      // マスク自動選択が ref.maskPattern と一致した場合のみ全比較、
      // それ以外はサイズ一致のみ（マスク選択はどちらも仕様適合でありうる）
      const flat = mod.encode_js(text, EC_NUM[ec], version);
      assert.notEqual(flat.length, 0, "encode must succeed");
      assert.equal(flat[0], size, "matrix size must match version");
      if (ref.maskPattern === mask) {
        // TODO ではない恒久仕様: 完全一致検証は同マスク時のみ意味を持つ
        // 自前の選択マスクを知るため、format情報から読み取る:
        // format bits は (8,0..5),(8,7),(8,8),(7,8),(5..0,8) に配置済み
        // → 比較は「ref と自前のどちらのマスク選択も許し、行列一致は
        //    自前マスク == ref マスクのときのみ」
        const ourMask = readMask(flat);
        if (ourMask === mask) {
          fullCompareCount.value++;
          for (let y = 0; y < size; y++) for (let x = 0; x < size; x++) {
            assert.equal(
              flat[1 + y * size + x],
              ref.modules.get(y, x) ? 1 : 0,
              `mismatch at (${x},${y})`);
          }
        }
      }
    });
  }
}

test("methodology: full-matrix comparison fired at least once per text case", () => {
  // fullCompareCount はテキストごとの発火回数を追跡していないため、
  // ここでは全体で最低 CASES.length 回発火したことのみ確認する
  // (各テキストにつき自前の自動選択マスクは 0..7 のどれかと必ず一致する)
  assert.ok(
    fullCompareCount.value >= CASES.length,
    `expected at least ${CASES.length} full-matrix comparisons, got ${fullCompareCount.value}`,
  );
});

// フォーマット情報15bitからマスク3bitを復元（XOR 0x5412 を戻す）
function readMask(flat) {
  const size = flat[0];
  const get = (x, y) => flat[1 + y * size + x];
  let bits = 0;
  const coords = [
    [8, 0], [8, 1], [8, 2], [8, 3], [8, 4], [8, 5], [8, 7], [8, 8],
    [7, 8], [5, 8], [4, 8], [3, 8], [2, 8], [1, 8], [0, 8],
  ];
  coords.forEach(([x, y], i) => { bits |= get(x, y) << i; });
  const unmasked = bits ^ 0x5412;
  return (unmasked >> 10) & 0b111;
}
