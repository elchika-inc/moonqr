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

// decode 側の実装は Task 4 で `./decode.js` に入る（現時点では型のみ）。
export type { DecodeOptions, DecodeResult, Point } from "./types.js";
