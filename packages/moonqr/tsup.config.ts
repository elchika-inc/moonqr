import { defineConfig } from "tsup";

export default defineConfig({
  // encode / decode を物理的に別エントリへ分割する（サブパスエクスポート）。
  // エンコードのみの消費者がデコーダ（raw 261KB / gzip 62KB、SJIS テーブル）を
  // 一切バンドルせずに済むようにするため。ルート（index.ts）は DX のため双方を
  // re-export するが、サイズ重視の消費者は `@elchika-inc/moonqr/encode` を使う。
  //
  // NOTE: `src/dom.ts`（Task 4 で追加予定の DOM ヘルパ）はこの時点では存在しないため
  // entry に含めていない。Task 4 で `src/dom.ts` を作成し、ここと package.json の
  // exports map に `./dom` を追加する。
  entry: ["src/index.ts", "src/encode.ts", "src/decode.ts"],
  format: ["esm", "cjs"],
  dts: true,
  minify: true,
  treeshake: true,
  clean: true,
  // MoonBit の JS 出力（core/_build 配下）はビルド成果物であり npm には公開されない。
  // 実行時に import 解決できないため、外部依存として残さず必ずバンドルへインライン化する。
  noExternal: [/core\/_build/],
});
