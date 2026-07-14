// dist/ 内の主要エントリの raw / gzip サイズを表にして出力する（CI: $GITHUB_STEP_SUMMARY へ、
// ローカル: stdout へ）。`pnpm -r build` の後に実行する前提（dist が無いエントリはスキップして
// 警告するのみ — CI を落とすほどの検証ではない「あれば嬉しい」機能のため fail-open）。
//
// moonqr は CJS 出力（*.cjs）を測る。ESM 出力はサブパス間で共有チャンク
// （dist/chunk-*.js）へ分割されるため単一ファイルのサイズがエントリ実体を表さない一方、
// CJS はエントリごとに自己完結でバンドルされるため「そのサブパスだけを import したときの
// 実際の重さ」を正しく表す（packages/moonqr/README.md のサブパス比較表と同じ測定方法）。
// scanner は ESM のみ・単一エントリのためチャンク分割の懸念がない。
import { existsSync, readFileSync, appendFileSync } from "node:fs";
import { gzipSync } from "node:zlib";
import { join } from "node:path";

const repoRoot = join(import.meta.dirname, "..");

const targets = [
  { pkg: "@elchika-inc/moonqr", file: "packages/moonqr/dist/index.cjs", label: "." },
  { pkg: "@elchika-inc/moonqr", file: "packages/moonqr/dist/encode.cjs", label: "./encode" },
  { pkg: "@elchika-inc/moonqr", file: "packages/moonqr/dist/decode.cjs", label: "./decode" },
  { pkg: "@elchika-inc/moonqr", file: "packages/moonqr/dist/dom.cjs", label: "./dom" },
  { pkg: "@elchika-inc/moonqr-scanner", file: "packages/scanner/dist/index.js", label: "." },
];

function kb(bytes) {
  return (bytes / 1024).toFixed(1);
}

const rows = [];
for (const t of targets) {
  const abs = join(repoRoot, t.file);
  if (!existsSync(abs)) {
    console.warn(`report-bundle-sizes: skip ${t.file} (not built — run \`pnpm -r build\` first)`);
    continue;
  }
  const buf = readFileSync(abs);
  const gz = gzipSync(buf);
  rows.push({ ...t, raw: buf.length, gzip: gz.length });
}

const lines = [];
lines.push("### Bundle sizes");
lines.push("");
lines.push("| package | entry | raw | gzip |");
lines.push("|---|---|---|---|");
for (const r of rows) {
  lines.push(`| ${r.pkg} | \`${r.label}\` | ${kb(r.raw)} KB | ${kb(r.gzip)} KB |`);
}
const md = lines.join("\n") + "\n";

console.log(md);

const summaryPath = process.env.GITHUB_STEP_SUMMARY;
if (summaryPath) {
  appendFileSync(summaryPath, md);
}
