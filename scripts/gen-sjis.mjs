// jsQR (Apache-2.0, cozmo) の shiftJISTable.ts から SJIS コード → Unicode コードポイントの
// 対応表を抽出し、core/src/decode/sjis.mbt を生成する。
//
// 出典テーブルはカテゴリ単位（ASCII → 半角カナ → 第一水準漢字 → 第二水準漢字 …）で並んでおり、
// SJIS コード昇順ではない（例: 0x9FFC の次に半角カナの 0xA1 が来る）。
// sjis_to_unicode は二分探索で引くため、生成時にコード昇順へソートし直す。
//
// 移植元コミットを固定する（Task 7 brief に記載のSHA）。
// 更新時は README/brief の SHA を書き換えたうえで本スクリプトを再実行し、
// `git diff core/src/decode/sjis.mbt` で差分を確認すること。
const COMMIT = "8e6a036beafa7053dd44b1b76ac578d22b1b3311";
const SOURCE_URL = `https://raw.githubusercontent.com/cozmo/jsQR/${COMMIT}/src/decoder/decodeData/shiftJISTable.ts`;

import { writeFileSync } from "node:fs";

const src = await (await fetch(SOURCE_URL)).text();

// `0x935F: 0x70B9,` 形式の行を抽出する。
const re = /0x([0-9A-Fa-f]+):\s*0x([0-9A-Fa-f]+),/g;
const pairs = [];
let m;
while ((m = re.exec(src))) {
  pairs.push([parseInt(m[1], 16), parseInt(m[2], 16)]);
}

if (pairs.length === 0) {
  throw new Error("shiftJISTable entries not found — ソース構造が変わった。手動確認せよ");
}

// 重複キー・範囲外値がないかの健全性チェック。
const seen = new Set();
for (const [code, cp] of pairs) {
  if (seen.has(code)) {
    throw new Error(`duplicate SJIS code 0x${code.toString(16)}`);
  }
  seen.add(code);
  if (code < 0 || code > 0xffff || cp < 0 || cp > 0x10ffff) {
    throw new Error(`out-of-range entry: 0x${code.toString(16)} -> 0x${cp.toString(16)}`);
  }
}

pairs.sort((a, b) => a[0] - b[0]);

console.log(`shiftJISTable rows: ${pairs.length}`);

// 固定コミットのソースなので行数は決定論的。パース漏れ/重複混入の回帰検知として
// 実測値（2026-07時点で確認済み）に固定する。将来ソースを更新する場合はこの数値も
// 更新すること（このエラーが出たら「更新のし忘れ」か「パース崩れ」のどちらか）。
const EXPECTED_ROWS = 7037;
if (pairs.length !== EXPECTED_ROWS) {
  throw new Error(
    `shiftJISTable rows: expected ${EXPECTED_ROWS}, got ${pairs.length} — ` +
      "パース漏れ、またはソース更新に伴う想定値の更新漏れ。手動確認せよ",
  );
}

let mbt = `///| このファイルは scripts/gen-sjis.mjs により生成。手編集禁止。
///| 出典: jsQR (Apache-2.0) https://github.com/cozmo/jsQR
///| 取得元: ${SOURCE_URL}
///| 元テーブルはカテゴリ単位の並び（SJISコード昇順ではない）だが、
///| sjis_to_unicode の二分探索のため生成時にコード昇順へソート済み。
///| 行数: ${pairs.length}（gen-sjis.mjs 実行時にコンソールへ出力・重複キー検査済み）

let sjis_codes : Array[Int] = [
${pairs.map(([code]) => `  0x${code.toString(16)},`).join("\n")}
]

let sjis_unicode : Array[Int] = [
${pairs.map(([, cp]) => `  0x${cp.toString(16)},`).join("\n")}
]

///| SJIS コード → Unicode コードポイントの二分探索。テーブルにない値は None
pub fn sjis_to_unicode(code : Int) -> Int? {
  let mut lo = 0
  let mut hi = sjis_codes.length() - 1
  while lo <= hi {
    let mid = (lo + hi) / 2
    let v = sjis_codes[mid]
    if v == code {
      return Some(sjis_unicode[mid])
    } else if v < code {
      lo = mid + 1
    } else {
      hi = mid - 1
    }
  }
  None
}
`;

writeFileSync(new URL("../core/src/decode/sjis.mbt", import.meta.url), mbt);
console.log("generated core/src/decode/sjis.mbt");
