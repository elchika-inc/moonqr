import { defineConfig } from "tsup";

export default defineConfig({
  // encode / decode を物理的に別エントリへ分割する（サブパスエクスポート）。
  // エンコードのみの消費者がデコーダ（raw 261KB / gzip 62KB、SJIS テーブル）を
  // 一切バンドルせずに済むようにするため。ルート（index.ts）は DX のため双方を
  // re-export するが、サイズ重視の消費者は `@elchika-inc/moonqr/encode` を使う。
  //
  // `src/dom.ts`（toCanvas）は MoonBit 成果物に依存しない純粋な DOM ヘルパのため、
  // encode/decode いずれの閉包にも影響しない別エントリとして追加する（Task 4）。
  entry: ["src/index.ts", "src/encode.ts", "src/decode.ts", "src/dom.ts"],
  format: ["esm", "cjs"],
  dts: true,
  minify: true,
  treeshake: true,
  clean: true,
  // MoonBit の JS 出力（core/_build 配下）はビルド成果物であり npm には公開されない。
  // 実行時に import 解決できないため、外部依存として残さず必ずバンドルへインライン化する。
  noExternal: [/core\/_build/],
});
