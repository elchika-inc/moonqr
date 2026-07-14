// Worker本体。scripts/build-worker.mjs がこのファイルを外部依存のない自己完結バンドルへ
// 変換し、src/worker-inline.generated.ts に文字列として埋め込む。index.ts はその文字列を
// Blob URL化して `new Worker(url)` で起動する（consumer側にバンドラ設定を一切要求しない
// ための設計。詳細は task-6-report.md 参照）。
//
// 型について: このファイルは tsup の dts 生成グラフ（index.ts からの静的import）には
// 含まれず、scripts/build-worker.mjs 内の esbuild（型チェックなし・型を消去するだけ）で
// のみビルドされる。DOM lib と WebWorker lib は同一tsconfig上で共存できない（両方が
// postMessage 等のグローバルを非互換に宣言する）ため、self を意図的に緩く型付けしている。
import { decodeMultiScale, decodeNative } from "./decode-core.js";
import type { DecodeResult } from "./decode-core.js";

export interface WorkerRequest {
  id: number;
  buffer: ArrayBuffer;
  width: number;
  height: number;
  invert?: boolean;
  /** true ならマルチスケールピラミッドで試行する（エスカレーション用）。既定は等倍1回。 */
  multiscale?: boolean;
}

export interface WorkerResponse {
  id: number;
  result: DecodeResult | null;
}

declare const self: {
  onmessage: ((event: { data: WorkerRequest }) => void) | null;
  postMessage: (message: WorkerResponse) => void;
};

self.onmessage = (event: { data: WorkerRequest }) => {
  const { id, buffer, width, height, invert, multiscale } = event.data;
  const data = new Uint8Array(buffer);
  // ライブフレーム経路は結果のみを返す（scale/attemptedScales は onResult の契約に
  // 含まれない——ライブスキャンでは「どのスケールで読めたか」は消費者に意味を持たず、
  // 毎フレームWorker境界を越えて運ぶ価値がない）。静止画の scanImage は
  // decodeMultiScale の outcome をそのまま公開する（index.ts の ScanImageResult）。
  const result = multiscale
    ? (decodeMultiScale(data, { width, height, invert })?.result ?? null)
    : decodeNative(data, { width, height, invert });
  self.postMessage({ id, result });
};
