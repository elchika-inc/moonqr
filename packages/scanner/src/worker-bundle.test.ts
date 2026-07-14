// **実Workerバンドルの実行テスト**（本番経路のカバー）。
//
// なぜ必要か: index.test.ts のWorker関連テストは手書きのFakeWorkerを使うため、
// 実際にブラウザで実行される成果物——scripts/build-worker.mjs が生成した
// 自己完結IIFEバンドル（`WORKER_SOURCE`）——のコードは一度も走らない。
// つまりビルド設定の破綻（decoderがバンドルされていない・`self.onmessage` の
// 契約ズレ・minifyによる破壊等）をテストで検知できない状態だった。
//
// ここでは WORKER_SOURCE を `new Function("self", WORKER_SOURCE)` で **実際に評価** し
// （ブラウザWorkerのグローバルスコープを模した最小環境: `self` に onmessage/postMessage
// を持たせるだけ。バンドルはIIFEで `self` を自由変数として参照するため、仮引数の `self`
// に束縛される）、実際にラスタライズしたQRフレームを流し込んでデコード結果が返ることを
// end-to-end で確認する。これにより「Blob URL 化されて本番で実際に走る文字列」そのものが
// 検証対象になる（Node固有API（node:vm）に依存せず、ブラウザ向けパッケージの
// tsconfig に @types/node を持ち込まずに済む）。
import { describe, expect, it } from "vitest";
import { encode } from "@elchika-inc/moonqr/encode";
import { WORKER_SOURCE } from "./worker-inline.generated.js";
import { applyMonitorLattice, rasterizeMatrix } from "./test-raster.js";

interface WorkerLike {
  post(message: {
    id: number;
    buffer: ArrayBuffer;
    width: number;
    height: number;
    invert?: boolean;
    multiscale?: boolean;
  }): { id: number; result: { text: string } | null };
}

/**
 * WORKER_SOURCE を評価し、`self.onmessage` を叩けるハンドルを返す。
 *
 * 注: `new Function` に渡しているのは **自前のビルド成果物**（scripts/build-worker.mjs が
 * esbuild で生成した固定文字列）であり、外部入力を連結していない——コードインジェクションの
 * 経路にはならない。そして「本番で実際に評価される文字列を、そのまま評価して確かめる」ことが
 * このテストの目的そのものである（文字列を偽物に差し替えたらテストの意味が消える）。
 */
function loadWorkerBundle(): WorkerLike {
  const responses: Array<{ id: number; result: { text: string } | null }> = [];
  const self = {
    onmessage: null as ((event: { data: unknown }) => void) | null,
    postMessage: (message: { id: number; result: { text: string } | null }) => {
      responses.push(message);
    },
  };
  // バンドルはIIFEで `self` を自由変数として参照する（ブラウザWorkerでは self===globalThis）。
  // 仮引数 `self` に束縛することで、上のフェイクグローバルの上で実行させる。
  const runBundle = new Function("self", WORKER_SOURCE) as (s: typeof self) => void;
  runBundle(self);

  if (typeof self.onmessage !== "function") {
    throw new Error(
      "worker bundle did not install self.onmessage — the Blob-URL worker would be a no-op in production",
    );
  }

  return {
    post(message) {
      responses.length = 0;
      self.onmessage?.({ data: message });
      const response = responses[0];
      if (!response) throw new Error("worker bundle did not postMessage a response");
      return response;
    },
  };
}

describe("the real inlined worker bundle (WORKER_SOURCE)", () => {
  it("installs self.onmessage and decodes a real QR frame at native scale", () => {
    const worker = loadWorkerBundle();
    const text = "WORKER BUNDLE E2E";
    const matrix = encode(text, { ecLevel: "M", version: 3 });
    if (!matrix) throw new Error("fixture: encode() failed");
    const { data, width, height } = rasterizeMatrix(matrix, { scale: 6, margin: 4 });

    const response = worker.post({
      id: 7,
      buffer: data.buffer as ArrayBuffer,
      width,
      height,
      invert: true,
    });

    expect(response.id).toBe(7);
    expect(response.result?.text).toBe(text);
  });

  it("decodes a monitor-lattice QR only when multiscale:true is requested", () => {
    const worker = loadWorkerBundle();
    const text = "LATTICE VIA WORKER";
    const matrix = encode(text, { ecLevel: "M", version: 2 });
    if (!matrix) throw new Error("fixture: encode() failed");
    const image = applyMonitorLattice(rasterizeMatrix(matrix, { scale: 28, margin: 4 }));

    // 等倍（fast path）では読めないフィクスチャであること
    const nativeResponse = worker.post({
      id: 1,
      buffer: image.data.slice().buffer as ArrayBuffer,
      width: image.width,
      height: image.height,
      invert: true,
    });
    expect(nativeResponse.result).toBeNull();

    // multiscale:true（エスカレーション経路）なら読める＝Worker内でmultiScaleDecodeが
    // 実際に配線されている
    const multiResponse = worker.post({
      id: 2,
      buffer: image.data.slice().buffer as ArrayBuffer,
      width: image.width,
      height: image.height,
      invert: true,
      multiscale: true,
    });
    expect(multiResponse.result?.text).toBe(text);
  });

  it("returns a null result (not a throw) for a frame with no QR", () => {
    const worker = loadWorkerBundle();
    const blank = new Uint8Array(120 * 120 * 4).fill(255);

    const response = worker.post({
      id: 3,
      buffer: blank.buffer as ArrayBuffer,
      width: 120,
      height: 120,
      invert: true,
    });

    expect(response.result).toBeNull();
  });
});
