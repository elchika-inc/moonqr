import { defineConfig } from "tsup";

export default defineConfig({
  // ルートエントリのみ（multiscale はカメラ非依存の純粋ロジックでサイズも小さく、
  // Task 3/4 の encode/decode のようなサブパス分割の理由がない）。
  entry: ["src/index.ts"],
  // ESMのみ: Worker起動をBlob URL化した文字列（src/worker-inline.generated.ts。
  // scripts/build-worker.mjs が生成）に依存しており、CJS化する実利がない
  // （Worker自体はブラウザAPIでNode CJSコンシューマを想定しない）。
  format: ["esm"],
  dts: true,
  minify: true,
  treeshake: true,
  clean: true,
});
