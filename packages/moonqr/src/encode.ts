// moonqr の encode サブパスエントリ（`@elchika-inc/moonqr/encode`）。
//
// サイズ影響の大きい消費者はここから import することで、デコーダ（SJIS テーブル込みで
// raw 261KB / gzip 62KB）を一切バンドルに含めずに済む。ルートエントリ（`./index.ts`）は
// DX のため encode/decode 双方を re-export するが、その場合ツリーシェイキングの成否が
// ダウンストリームのバンドラ品質に依存してしまうため、物理的に分離したこのエントリを正とする。
//
// 設計上の決定（重要）: `toSvgString` は「行列」を受け取り、テキストは受け取らない。
// MoonBit 側には `to_svg_string_js(text, ec, version, margin, cell)` という
// テキスト→SVG 直行の実装（src/core-encode.ts の toSvgStringJs、demo/簡易用途）が既に存在するが、
// あれは公開 API の形（matrix→svg・純粋関数・DOM 非依存）とは合わないため、
// `toSvgString` の実体としては **使わない**。理由は2点:
//   1. 公開契約が「matrix を受ける」形である以上、内部で再エンコードする実装は
//      「同じ matrix から SVG を作っている」という直感に反し、しかも ecLevel/version を
//      呼び出し側が忘れると無関係な QR の SVG が出る事故になりうる。
//   2. `encode()` が返した `QrMatrix` をそのまま渡せることで、エンコード結果を
//      加工（将来的な色替え・ロゴ埋め込み等）してから SVG 化する拡張の余地を残せる。
// そのため `toSvgString` は本ファイル内で TS 実装する。
import { encodeJs } from "./core-encode.js";
import type { EcLevel, EncodeOptions, QrMatrix, SvgOptions } from "./types.js";

export type { EcLevel, EncodeOptions, QrMatrix, SvgOptions } from "./types.js";

// prototype-safe なルックアップ（オブジェクトリテラル + `[]` は使わない）。
// 素の `{L:0,M:1,Q:2,H:3}[ecLevel]` だと、型を無視した呼び出し元が `"__proto__"` を渡した
// 場合に Object.prototype が、`"constructor"`/`"toString"` を渡した場合に関数が返り、
// `=== undefined` ガードをすり抜けて **誤った EC レベルの QR が黙って生成される**。
// Map は prototype チェーンを持たないため、この経路を構造的に塞ぐ。
const EC_LEVEL_TO_NUM: ReadonlyMap<EcLevel, number> = new Map<EcLevel, number>([
  ["L", 0],
  ["M", 1],
  ["Q", 2],
  ["H", 3],
]);

class FlatQrMatrix implements QrMatrix {
  readonly size: number;
  private readonly cells: number[];

  constructor(size: number, cells: number[]) {
    this.size = size;
    this.cells = cells;
  }

  get(x: number, y: number): boolean {
    if (x < 0 || y < 0 || x >= this.size || y >= this.size) {
      return false;
    }
    return this.cells[y * this.size + x] !== 0;
  }
}

/**
 * テキストを QR 行列にエンコードする。
 * 容量超過・空文字・不正オプション（version が 1..40 の範囲外、ecLevel が L/M/Q/H 以外）は null を返す。
 */
export function encode(text: string, options?: EncodeOptions): QrMatrix | null {
  const ecLevel = options?.ecLevel ?? "M";
  const version = options?.version ?? 0;
  const ecNum = EC_LEVEL_TO_NUM.get(ecLevel);
  // TS の型では EcLevel は "L"|"M"|"Q"|"H" に閉じているが、型を無視した非TS呼び出し元に
  // 備え total function として扱う（未知の ecLevel は null）。
  if (ecNum === undefined) {
    return null;
  }
  const flat = encodeJs(text, ecNum, version);
  if (flat.length === 0) {
    return null;
  }
  // flat.length > 0 を直前で確認済みのため flat[0]（size）は必ず存在する。
  const size = flat[0] as number;
  const cells = flat.slice(1);
  return new FlatQrMatrix(size, cells);
}

/** QR 行列を SVG 文字列にする（純粋関数・DOM 非依存）。MoonBit 側の svg.mbt と同じ描画方式（1つの <path> にモジュールを結合、余白付き <rect> 背景）を TS で再実装している。 */
export function toSvgString(matrix: QrMatrix, options?: SvgOptions): string {
  const margin = options?.margin ?? 4;
  const cell = options?.cell ?? 4;
  const total = (matrix.size + margin * 2) * cell;
  let d = "";
  for (let y = 0; y < matrix.size; y++) {
    for (let x = 0; x < matrix.size; x++) {
      if (matrix.get(x, y)) {
        const px = (x + margin) * cell;
        const py = (y + margin) * cell;
        d += `M${px} ${py}h${cell}v${cell}h-${cell}z`;
      }
    }
  }
  return (
    `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${total} ${total}">` +
    `<rect width="${total}" height="${total}" fill="#fff"/>` +
    `<path d="${d}" fill="#000"/></svg>`
  );
}
