// moonqr の decode サブパスエントリ（`@elchika-inc/moonqr/decode`）。
//
// **サブパス分割の要（Task 3 からの申し送り）**: このファイルは **`./core-decode.js` からのみ**
// import すること。`./core-encode.js`（もしくはそれを再 export するモジュール）を混ぜると、
// esbuild のコード分割が encode/decode 両 MoonBit 成果物を1つの共有チャンクへ巻き上げてしまい、
// `@elchika-inc/moonqr/encode` だけを import した消費者にもデコーダ（raw 128KB 級、SJIS テーブル）
// が流れ込む（実測で確認済み。詳細は core-encode.ts の冒頭コメントと task-3-report.md を参照）。
//
// 分離の理由: encode のみを使う消費者（大多数）がデコーダを一切バンドルしないで済むよう、
// tsup のエントリとして encode/decode を物理的に別ファイルに分けている。ルートエントリ
// （`./index.ts`）は DX のため双方を re-export するが、サイズが問題になる消費者は
// `@elchika-inc/moonqr/encode` から import すればデコーダは確実に含まれない
// （ダウンストリームのバンドラのツリーシェイキング品質に依存しない）。
import { decodeJs } from "./core-decode.js";
import type { DecodeOptions, DecodeResult, EcLevel, Point } from "./types.js";

export type { DecodeOptions, DecodeResult, Point } from "./types.js";

// prototype-safe な検証（Task 3 の教訓の再適用）。
// decode_js が返す JSON の `ecLevel` フィールドは実装上 "L"|"M"|"Q"|"H" のいずれかしか
// 出力しないが、JSON.parse の戻り値は型システム上 `unknown` であり、この値を
// `{L:...,M:...}[ecLevel]` のようなオブジェクトリテラル + `[]` ルックアップで検証すると
// `"__proto__"` 等の値が Object.prototype 経由で「見つかった」ことになりガードをすり抜ける
// （encode.ts の EC_LEVEL_TO_NUM と同じ地雷）。prototype チェーンを持たない `Set#has` で
// 検証することでこの経路を構造的に塞ぐ。
const VALID_EC_LEVELS: ReadonlySet<string> = new Set<EcLevel>(["L", "M", "Q", "H"]);

function isEcLevel(value: unknown): value is EcLevel {
  return typeof value === "string" && VALID_EC_LEVELS.has(value);
}

function isPoint(value: unknown): value is Point {
  if (typeof value !== "object" || value === null) return false;
  const p = value as Record<string, unknown>;
  return typeof p.x === "number" && typeof p.y === "number";
}

/** decode_js が返す JSON を DecodeResult に整形する。想定外の形は total に null を返す。 */
function toDecodeResult(parsed: unknown): DecodeResult | null {
  if (typeof parsed !== "object" || parsed === null) return null;
  const obj = parsed as Record<string, unknown>;

  if (typeof obj.text !== "string") return null;
  if (typeof obj.version !== "number") return null;
  if (!isEcLevel(obj.ecLevel)) return null;
  if (!Array.isArray(obj.bytes) || !obj.bytes.every((b) => typeof b === "number")) return null;
  if (!Array.isArray(obj.corners) || obj.corners.length !== 4 || !obj.corners.every(isPoint)) {
    return null;
  }

  const corners = obj.corners as Point[];
  return {
    text: obj.text,
    bytes: Uint8Array.from(obj.bytes as number[]),
    version: obj.version,
    ecLevel: obj.ecLevel,
    corners: [corners[0], corners[1], corners[2], corners[3]] as [Point, Point, Point, Point],
  };
}

/**
 * RGBA ピクセルから QR を読む。見つからなければ null。不正入力（長さ不一致等）も null。
 *
 * `data` は `width*height*4` バイトの RGBA 配列（`ImageData.data` 相当）。
 * `Uint8ClampedArray`（`ImageData.data` の実際の型）はコピーせず同一バッファのビューとして
 * `Uint8Array` に正規化してから MoonBit 側へ渡す。
 *
 * `options.invert`（既定 true）: true の場合、まず通常配色で読み取りを試み、失敗したら
 * 反転配色（黒白が入れ替わったQR）でも読み取りを試みる。false の場合は通常配色のみを試す。
 */
export function decode(
  data: Uint8Array | Uint8ClampedArray,
  width: number,
  height: number,
  options?: DecodeOptions,
): DecodeResult | null {
  // 入力ガード（totality 契約の要）。MoonBit 側 `decode_js` は width/height を `BigInt(width)` へ
  // 通すため、NaN / 小数 / Infinity が境界を越えると **RangeError を throw する**（同様に
  // data が null/undefined だと `data.length` 参照で TypeError）。MoonBit 側の
  // `width <= 0` ガードは NaN 比較が常に false になるためすり抜ける。
  // 小数の width は `canvas.width * devicePixelRatio` や `video.videoWidth` 由来の計算で
  // 現実に発生しうる経路であり、そのままではスキャナがホストアプリを未捕捉例外でクラッシュ
  // させる。TS の型は非TS呼び出し元を守らないため、境界の手前で全て null に倒す。
  // `instanceof` で型そのものを検証する（`.length` の duck-typing では、正しい長さの
  // 素の `Array` や `Float64Array` が通過してしまい、MoonBit 側で
  // `Error: Index out of bounds` を throw させてしまう＝README の「例外を投げない」契約違反）。
  if (!(data instanceof Uint8Array || data instanceof Uint8ClampedArray)) return null;
  // Number.isInteger は NaN・小数・±Infinity を全て弾く（`> 0` 比較だけでは NaN が漏れる）。
  if (!Number.isInteger(width) || !Number.isInteger(height)) return null;
  if (width <= 0 || height <= 0) return null;
  if (data.length !== width * height * 4) return null;

  const alsoTryInverted = options?.invert ?? true;
  const normalized =
    data instanceof Uint8ClampedArray
      ? new Uint8Array(data.buffer, data.byteOffset, data.byteLength)
      : data;

  let raw = decodeJs(normalized, width, height, false);
  if (raw === "" && alsoTryInverted) {
    raw = decodeJs(normalized, width, height, true);
  }
  if (raw === "") return null;

  let parsed: unknown;
  try {
    parsed = JSON.parse(raw);
  } catch {
    // decode_js は本来常に妥当なJSONを返す契約だが、境界を越えた値は信用しない
    // （total function の方針。例外は投げず null）。
    return null;
  }
  return toDecodeResult(parsed);
}
