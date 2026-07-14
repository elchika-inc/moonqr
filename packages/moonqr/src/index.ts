// moonqr のルートエントリ（`@elchika-inc/moonqr`）。
//
// DX のため encode / decode 双方を re-export する。ただし **サイズが問題になる消費者は
// サブパスから import すること**:
//   - `@elchika-inc/moonqr/encode` — エンコードのみ（デコーダを一切含まない）
//   - `@elchika-inc/moonqr/decode` — デコードのみ
// ルートエントリ経由で encode だけを使う場合、デコーダ（raw 261KB / gzip 62KB、SJIS テーブル）
// が落ちるかどうかはダウンストリームのバンドラのツリーシェイキング品質に依存してしまう
// （`sideEffects: false` は宣言済みだが、それでも保証はできない）。サブパスなら物理的に
// 別ファイルなので確実に含まれない。
export { encode, toSvgString } from "./encode.js";
export type { EcLevel, EncodeOptions, QrMatrix, SvgOptions } from "./types.js";

export { decode } from "./decode.js";
export type { DecodeOptions, DecodeResult, Point } from "./types.js";

// `./dom.js`（toCanvas）はルートからは re-export しない。DOM 依存（HTMLCanvasElement）を
// 持つためNode専用消費者の型解決を汚さないよう、`@elchika-inc/moonqr/dom` サブパス経由での
// 利用に限定する（README のサブパス表を参照）。
