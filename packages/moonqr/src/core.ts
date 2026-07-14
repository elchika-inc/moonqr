// MoonBit が生成した JS 境界（core/_build/js/release/build/**）への内部バインディング層。
// このファイルだけが MoonBit 出力の生パスを知っている（他の src/*.ts からは直接 import しない）。
//
// tsup.config.ts の noExternal でこの import 先を必ずバンドルにインライン化するため、
// 公開パッケージは実行時依存を持たない（MoonBit の JS 出力はビルド成果物であり npm には
// 公開されないため、外部依存として残すと消費者側で解決できない）。
import { encode_js, to_svg_string_js } from "../../../core/_build/js/release/build/encode/encode.js";
// decode_js は Task 4（decode 側 TS ラッパ）が使う。src/index.ts（このタスクの公開エントリ）は
// decodeJs を re-export も import もしない。ここで先取り import しているのは、
// 「未使用のまま import だけしておくと dist/index.js にデコード側コード（SJIS テーブル等、
// 261KB 相当）が含まれてしまわないか」をツリーシェイキング調査の一環として実測するため
// （結果は task-3-report.md 参照。esbuild が到達不能と判定し完全に除去されることを確認済み）。
import { decode_js } from "../../../core/_build/js/release/build/decode/decode.js";

/**
 * QR 行列をエンコードする（MoonBit `encode_js` の薄いラッパ）。
 * text: エンコード対象文字列 / ec: 0=L 1=M 2=Q 3=H / version: 0=自動 or 1..40
 * 戻り値: `[size, cell...]` の平坦配列。失敗時は空配列 `[]`。
 */
export const encodeJs: (text: string, ec: number, version: number) => number[] = encode_js;

/**
 * QR 行列を直接 SVG 文字列にする MoonBit 側実装（text→svg）。
 * demo/簡易用途としてのみ残しており、公開 API `toSvgString`（matrix→svg, src/index.ts）
 * の実体には使わない。詳細は src/index.ts のコメントを参照。
 */
export const toSvgStringJs: (
  text: string,
  ec: number,
  version: number,
  margin: number,
  cell: number,
) => string = to_svg_string_js;

/**
 * QR をデコードする（MoonBit `decode_js` の薄いラッパ）。Task 4 で公開 API に配線する。
 * data: 2値化済みの1バイト/px（0=白 それ以外=黒）想定 / width, height: 画像サイズ / invert: 反転読取
 */
export const decodeJs: (data: Uint8Array, width: number, height: number, invert: boolean) => string =
  decode_js;
