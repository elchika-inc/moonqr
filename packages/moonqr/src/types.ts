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

/** 平面上の点（px 座標） */
export interface Point {
  x: number;
  y: number;
}

export interface DecodeOptions {
  /** 反転色QRも試すか（既定 true） */
  invert?: boolean;
}

export interface DecodeResult {
  text: string;
  /** 生バイト列（バイナリペイロード用） */
  bytes: Uint8Array;
  version: number;
  ecLevel: EcLevel;
  /** 元画像px。TL,TR,BR,BL 順 */
  corners: [Point, Point, Point, Point];
}
