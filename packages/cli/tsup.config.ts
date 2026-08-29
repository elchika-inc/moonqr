import { defineConfig } from "tsup";

export default defineConfig({
  // 実行ファイルであり誰も import しないため、型定義（dts）は生成しない。
  // Node が直接実行するので CJS も不要。
  entry: ["src/cli.ts"],
  format: ["esm"],
  dts: false,
  // CLI は起動時に読み込まれるだけでバンドルサイズの制約がないため、
  // デバッグしやすい出力を優先して minify しない。
  minify: false,
  clean: true,
});
