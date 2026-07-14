import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    include: ["src/**/*.test.ts"],
    // camera/canvas/Worker統合 (index.test.ts) はDOM APIを要するためjsdomを使う。
    // jsdomはWorker/OffscreenCanvasを実装しない——これは偶然ではなく、
    // 「Worker不在環境での同スレッドフォールバックが透過的に動く」ことの
    // 実地検証として利用している（worker-handle.ts参照）。
    environment: "jsdom",
    // エスカレーションテストは「15回の等倍失敗 → 16回目でマルチスケール成功」を
    // **実デコーダ**で通す（モック化しない＝配線の実証が目的）。900px級の格子画像に
    // 対する16回のデコード試行は実測で数秒かかるため、既定の5秒では並列実行時の
    // CPU競合で不安定になる。実作業時間に見合った上限へ引き上げる。
    testTimeout: 30_000,
  },
});
