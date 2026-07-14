import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    include: ["src/**/*.test.ts"],
    // camera/canvas/Worker統合 (index.test.ts) はDOM APIを要するためjsdomを使う。
    // jsdomはWorker/OffscreenCanvasを実装しない——これは偶然ではなく、
    // 「Worker不在環境での同スレッドフォールバックが透過的に動く」ことの
    // 実地検証として利用している（worker-handle.ts参照）。
    environment: "jsdom",
  },
});
