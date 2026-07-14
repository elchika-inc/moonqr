import { defineConfig } from "tsup";

export default defineConfig({
  // NOTE: task-3-brief.md は entry に `src/dom.ts` も含める記載だが、
  // dom.ts は Task 4（decode 側 TS ラッパ＋dom サブパス）で追加される。
  // このタスク（encode 側）時点では存在しないため index.ts のみを指定し、
  // Task 4 でこのファイルに追記する。
  entry: ["src/index.ts"],
  format: ["esm", "cjs"],
  dts: true,
  minify: true,
  treeshake: true,
  clean: true,
  // MoonBit の JS 出力（core/_build 配下）はビルド成果物であり npm には公開されない。
  // 実行時に import 解決できないため、外部依存として残さず必ずバンドルへインライン化する。
  noExternal: [/core\/_build/],
});
