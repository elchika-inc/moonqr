// moonqr 公開 API の型定義。
// 実装（encode/decode/svg）とは分離し、ここは型のみを持つ。

/** 誤り訂正レベル（QR仕様の4段階） */
export type EcLevel = "L" | "M" | "Q" | "H";

export interface EncodeOptions {
  /** 誤り訂正レベル（既定 "M"） */
  ecLevel?: EcLevel;
  /** バージョン 1..40。省略時は収まる最小を自動選択 */
  version?: number;
}

export interface QrMatrix {
  readonly size: number;
  /** true = 黒モジュール。範囲外の座標は false（例外を投げない） */
  get(x: number, y: number): boolean;
}

export interface SvgOptions {
  /** 余白（モジュール単位、既定 4） */
  margin?: number;
  /** 1モジュールの辺長（px、既定 4） */
  cell?: number;
}

// --- 以下は Task 4（decode 側 TS ラッパ）向けのスタブ。
// このタスク（encode 側）では未使用だが、後続タスクの型契約を先に固定しておく。

/** 平面上の点（px 座標） */
export interface Point {
  x: number;
  y: number;
}

export interface DecodeOptions {
  /** true の場合、白黒を反転して読み取る（反転QR対応） */
  invert?: boolean;
}

export interface DecodeResult {
  /** デコードされたテキスト */
  text: string;
  /** QR の4隅（元画像px座標）。将来の可視化用途 */
  corners?: [Point, Point, Point, Point];
}
