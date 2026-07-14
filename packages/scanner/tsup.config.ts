import { defineConfig } from "tsup";

export default defineConfig({
  // 現時点ではルートエントリのみ（multiscale はカメラ非依存の純粋ロジックで
  // サイズも小さく、Task 3/4 の encode/decode のようなサブパス分割の理由が
  // ない。Task 6 でカメラ/Workerを追加する際に分割の要否を再検討する）。
  entry: ["src/index.ts"],
  format: ["esm", "cjs"],
  dts: true,
  minify: true,
  treeshake: true,
  clean: true,
});
