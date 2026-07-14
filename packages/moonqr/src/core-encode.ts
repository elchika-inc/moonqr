// MoonBit エンコーダ（core/_build/js/release/build/encode/encode.js）への内部バインディング層。
//
// **重要（サブパス分割の要）**: このファイルは decode.js を import してはならない。
// encode 側と decode 側の MoonBit 成果物を1つのモジュール（旧 core.ts）から両方 import すると、
// tsup(esbuild) のコード分割が「両エントリが参照する共通モジュール」として両成果物を1つの
// 共有チャンクへ巻き上げてしまい、`@elchika-inc/moonqr/encode` だけを import した消費者にも
// デコーダ（raw 261KB / gzip 62KB、SJIS テーブル）が流れ込む（実測で確認済み。
// 詳細は .superpowers/sdd/task-3-report.md のツリーシェイキング調査を参照）。
// core-encode / core-decode を分けることで、共有チャンクに MoonBit 成果物が載らなくなる。
import { encode_js, to_svg_string_js } from "../../../core/_build/js/release/build/encode/encode.js";

/**
 * QR 行列をエンコードする（MoonBit `encode_js` の薄いラッパ）。
 * text: エンコード対象文字列 / ec: 0=L 1=M 2=Q 3=H / version: 0=自動 or 1..40
 * 戻り値: `[size, cell...]` の平坦配列。失敗時は空配列 `[]`。
 */
export const encodeJs: (text: string, ec: number, version: number) => number[] = encode_js;

/**
 * QR を直接 SVG 文字列にする MoonBit 側実装（text→svg）。
 * demo/簡易用途としてのみ残しており、公開 API `toSvgString`（matrix→svg, src/encode.ts）
 * の実体には使わない。詳細は src/encode.ts のコメントを参照。
 */
export const toSvgStringJs: (
  text: string,
  ec: number,
  version: number,
  margin: number,
  cell: number,
) => string = to_svg_string_js;
