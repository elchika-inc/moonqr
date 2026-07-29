import { defineConfig } from "tsup";

export default defineConfig({
  // 実行ファイルであり誰も import しないため、型定義（dts）は生成しない。
  // Node が直接実行するので CJS も不要。
  entry: ["src/cli.ts"],
  format: ["esm"],
  dts: false,
  // minify しない: cli.test.ts が「isTTY を参照していないこと」を関数のソース
  // 文字列で検査する。minify すると識別子が変わり検査の前提が崩れる。
  // CLI は起動のたびに読み込まれるだけでバンドルサイズの制約もない。
  minify: false,
  clean: true,
});
