// worker.ts（Worker内で実行）と index.ts（同スレッドfallback / scanImage）の両方から
// 共有される純粋なデコードロジック。Worker境界をまたいで再利用するため、DOM/Worker固有の
// API（postMessage, self.onmessage 等）には一切触れない（副作用なしの純粋関数のみを置く）。
//
// decoder は必ずサブパス（`@elchika-inc/moonqr/decode`）から import する（root import禁止）。
// root（`@elchika-inc/moonqr`）は encoder も re-export しており、混ぜると esbuild のバンドルに
// encoder（SJIS テーブル込み）まで巻き上がる（moonqr側 core-decode.ts/decode.ts のコメント参照）。
// scanner は decode 専用パッケージであり encoder を一切必要としないため、この境界を破ると
// バンドルサイズが不必要に膨らむ。
import { decode } from "@elchika-inc/moonqr/decode";
import type { DecodeResult } from "@elchika-inc/moonqr/decode";
import { multiScaleDecode, type MultiScaleOutcome } from "./multiscale.js";

export type { DecodeResult } from "@elchika-inc/moonqr/decode";

export interface DecodeParams {
  width: number;
  height: number;
  /** 反転色QRも試すか（既定 true・呼び出し元で解決済みの値を渡すこと） */
  invert?: boolean;
}

/**
 * `Uint8ClampedArray`（`ImageData.data` の実際の型）をコピーせず同一バッファのビューとして
 * `Uint8Array` に正規化する（moonqr の decode.ts と同じ手法）。multiScaleDecode/halveRGBA は
 * `Uint8Array` を要求するため、呼び出しの型を揃えるためだけの変換——scanImage/ライブフレーム
 * どちらも getImageData 由来の `Uint8ClampedArray` を渡してくる経路がある。
 */
function toUint8Array(data: Uint8Array | Uint8ClampedArray): Uint8Array {
  return data instanceof Uint8ClampedArray
    ? new Uint8Array(data.buffer, data.byteOffset, data.byteLength)
    : data;
}

/**
 * ネイティブ解像度で1回だけデコードを試みる（ライブフレームの高速パス）。
 * マルチスケールピラミッドは構築しない——毎フレーム構築すると数十msのコストが掛かり
 * 続けフレームレートを損なうため、まずこの安価な単発試行を基本とする。
 */
export function decodeNative(
  data: Uint8Array | Uint8ClampedArray,
  params: DecodeParams,
): DecodeResult | null {
  return decode(data, params.width, params.height, { invert: params.invert });
}

/**
 * マルチスケールピラミッドでデコードを試みる（静止画の一発読取、および
 * ライブフレームでの失敗エスカレーション用）。
 *
 * 戻り値は `MultiScaleOutcome`（`result` に加えて成功した `scale` と試行した
 * `attemptedScales` を含む）——**成否だけでなく「どのスケールで成功したか」まで
 * 返すのが契約**。`QrScanner.scanImage()` はこれをそのまま公開APIへ通す
 * （消費者が「モニター越しの撮影だったので1/8で読めた」等を提示できるようにするため。
 * この情報を握りつぶすと消費者は multiScaleDecode を自前で呼び直すしかなくなる）。
 * 結果のみが必要な呼び出し元（Worker境界を越えるライブフレーム経路）は `?.result` を取る。
 */
export function decodeMultiScale(
  data: Uint8Array | Uint8ClampedArray,
  params: DecodeParams,
): MultiScaleOutcome<DecodeResult> | null {
  return multiScaleDecode(
    (d, w, h) => decode(d, w, h, { invert: params.invert }),
    toUint8Array(data),
    params.width,
    params.height,
  );
}
