// qrcode-generator (MIT, kazuhikoarase) のソースから RS_BLOCK_TABLE と
// PATTERN_POSITION_TABLE を抽出して MoonBit コードを生成する。
// 出典コメントを生成ファイル先頭に付ける。
//
// 注意: master ブランチの js/qrcode.js は現在のリポジトリ構成には存在しない
// （js/ 以下は ts/ からビルドされた dist/ 構成に移行済み）。
// 実際に確認したソース: js/dist/qrcode.js
// （コンパイル済み plain JS。ts/src/ts/com/d_project/qrcode/RSBlock.ts, QRUtil.ts と内容一致を確認済み）
//
// RS_BLOCK_TABLE の並びは (version-1)*4 + [L,M,Q,H の index]。
// ErrorCorrectLevel の数値定数は L=1,M=0,Q=3,H=2 だが、getRsBlockTable は
// switch 文でシンボル名によって分岐しており、table の行オフセットは
// L:+0, M:+1, Q:+2, H:+3 の固定順（ソースコメント "// L // M // Q // H" とも一致）。
// 数値定数の並びに惑わされないこと。
//
// master の HEAD が動くと無断でテーブル内容が変わりうるため、取得時点の
// commit SHA に固定する（2026-07-14 時点の master HEAD = 83b7e8f）。
// 更新時は `git ls-remote https://github.com/kazuhikoarase/qrcode-generator HEAD`
// で新SHAを取得し、再生成後 `git diff core/src/encode/tables.mbt` で差分を確認すること。
const SOURCE_URL =
  "https://raw.githubusercontent.com/kazuhikoarase/qrcode-generator/83b7e8fe3fddd3b0368dbafd6ce56995bd25e3c8/js/dist/qrcode.js";

import { writeFileSync } from "node:fs";

const src = await (await fetch(SOURCE_URL)).text();

const rsMatch = src.match(/var RS_BLOCK_TABLE\s*=\s*\[([\s\S]*?)\n\s*\];/);
const posMatch = src.match(
  /var PATTERN_POSITION_TABLE\s*=\s*\[([\s\S]*?)\n\s*\];/,
);
if (!rsMatch) throw new Error("RS_BLOCK_TABLE not found — ソース構造が変わった。手動確認せよ");
if (!posMatch) throw new Error("PATTERN_POSITION_TABLE not found — ソース構造が変わった。手動確認せよ");

const stripComments = (s) => s.replace(/\/\/[^\n]*/g, "");

const rsRows = JSON.parse("[" + stripComments(rsMatch[1]) + "]");
const posRows = JSON.parse("[" + stripComments(posMatch[1]) + "]");

if (rsRows.length !== 160) {
  throw new Error(`RS_BLOCK_TABLE: expected 160 rows (40 versions * 4 levels), got ${rsRows.length}`);
}
if (posRows.length !== 40) {
  throw new Error(`PATTERN_POSITION_TABLE: expected 40 rows (versions 1..40), got ${posRows.length}`);
}

let mbt = `///| このファイルは scripts/gen-tables.mjs により生成。手編集禁止。
///| 出典: qrcode-generator (MIT) https://github.com/kazuhikoarase/qrcode-generator
///| 取得元: ${SOURCE_URL}
///| RS_BLOCK_TABLE の行順は (version-1)*4 + ec_index(L=0,M=1,Q=2,H=3)。
///| （ErrorCorrectLevel の数値定数 L=1,M=0,Q=3,H=2 とは無関係。
///|  getRsBlockTable の switch 分岐がシンボル名基準のため、行オフセットは常に L,M,Q,H の固定順）

pub(all) enum EcLevel {
  L
  M
  Q
  H
} derive(Eq, Debug)

fn ec_index(ec : EcLevel) -> Int {
  match ec {
    EcLevel::L => 0
    EcLevel::M => 1
    EcLevel::Q => 2
    EcLevel::H => 3
  }
}

///| (totalCount, dataCount) のブロック列。version 1..40
pub fn rs_blocks(version : Int, ec : EcLevel) -> Array[(Int, Int)] {
  let row = rs_block_row((version - 1) * 4 + ec_index(ec))
  let out : Array[(Int, Int)] = []
  let mut i = 0
  while i < row.length() {
    let count = row[i]
    for k = 0; k < count; k = k + 1 {
      out.push((row[i + 1], row[i + 2]))
    }
    i = i + 3
  }
  out
}

pub fn data_capacity(version : Int, ec : EcLevel) -> Int {
  let blocks = rs_blocks(version, ec)
  let mut sum = 0
  for i = 0; i < blocks.length(); i = i + 1 {
    let (_, data) = blocks[i]
    sum = sum + data
  }
  sum
}

pub fn alignment_positions(version : Int) -> Array[Int] {
  pattern_position_row(version - 1)
}

fn rs_block_row(idx : Int) -> Array[Int] {
  match idx {
`;
for (let i = 0; i < 160; i++) {
  const row = rsRows[i];
  mbt += `    ${i} => [${row.join(", ")}]\n`;
}
mbt += `    _ => abort("invalid rs block index")
  }
}

fn pattern_position_row(idx : Int) -> Array[Int] {
  match idx {
`;
for (let i = 0; i < 40; i++) {
  mbt += `    ${i} => [${posRows[i].join(", ")}]\n`;
}
mbt += `    _ => abort("invalid version")
  }
}
`;
writeFileSync(new URL("../core/src/encode/tables.mbt", import.meta.url), mbt);
console.log("generated core/src/encode/tables.mbt");
