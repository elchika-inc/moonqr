// moonqr の decode サブパスエントリ（`@elchika-inc/moonqr/decode`）。
//
// Task 4（decode 側 TS ラッパ）が `decode()` の実装をここに追加する。実装時は
// **`./core-decode.js` から `decodeJs` を import すること**（`./core-encode.js` を混ぜない）。
// 現時点では型のみを公開しており、MoonBit の decode.js（raw 261KB / gzip 62KB、SJIS テーブルが
// 重量物）へのランタイム import はまだ持たない。
//
// 分離の理由: encode のみを使う消費者（大多数）がデコーダを一切バンドルしないで済むよう、
// tsup のエントリとして encode/decode を物理的に別ファイルに分けている。ルートエントリ
// （`./index.ts`）は DX のため双方を re-export するが、サイズが問題になる消費者は
// `@elchika-inc/moonqr/encode` から import すればデコーダは確実に含まれない
// （ダウンストリームのバンドラのツリーシェイキング品質に依存しない）。
//
// なお、エントリを分けるだけでは不十分で、内部バインディング層（core-encode / core-decode）も
// 分けなければ esbuild のコード分割が両 MoonBit 成果物を共有チャンクへ巻き上げてしまう
// （実測済み。core-encode.ts の冒頭コメントと task-3-report.md を参照）。
export type { DecodeOptions, DecodeResult, Point } from "./types.js";
