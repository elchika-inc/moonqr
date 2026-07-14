// site/ (GitHub Pages 用デモ) が読み込む「ビルド済みライブラリ」を組み立てるスクリプト。
//
// なぜバンドラを使わないか: site/app.js は `@elchika-inc/moonqr` / `@elchika-inc/moonqr-scanner`
// を素の ESM `<script type="module">` として読み込む。両パッケージの dist は tsup で既に
// 自己完結バンドル済み（MoonBit の core/_build 出力も含めてバンドル済み）なので、必要なのは
// 「該当 .js ファイルをブラウザから相対パスで読める場所へコピーする」ことだけ——esbuild 等で
// 再バンドルすると二重バンドルになり無駄（実装方針: インフラ/標準機能で足りるところに自前の
// ビルドステップを足さない）。
//
// scanner/dist/index.js は `@elchika-inc/moonqr/decode` をベア指定子で import している
// （パッケージ間の依存はバンドルに巻き込まない設計・decode-core.ts 冒頭コメント参照）。
// ブラウザにはNode解決がないため、site/index.html の <script type="importmap"> でこの
// ベア指定子を ./assets/ 配下の相対パスへ解決する。従って本スクリプトの出力先ディレクトリ名
// （assets/moonqr/, assets/moonqr-scanner/）は index.html の importmap と一致させること。
import { existsSync, mkdirSync, readdirSync, rmSync, copyFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import path from "node:path";

const repoRoot = fileURLToPath(new URL("..", import.meta.url));
const moonqrDist = path.join(repoRoot, "packages/moonqr/dist");
const scannerDist = path.join(repoRoot, "packages/scanner/dist");
const siteAssets = path.join(repoRoot, "site/assets");

function requireDist(dir, pkgName) {
  if (!existsSync(dir)) {
    throw new Error(
      `${pkgName} の dist が見つからない (${dir})。先に \`pnpm -r build\` を実行してください。`,
    );
  }
}

requireDist(moonqrDist, "@elchika-inc/moonqr");
requireDist(scannerDist, "@elchika-inc/moonqr-scanner");

// 生成物なのでクリーンビルド（gitignore対象。stale なチャンクファイルが残らないようにする）。
rmSync(siteAssets, { recursive: true, force: true });

const moonqrOut = path.join(siteAssets, "moonqr");
const scannerOut = path.join(siteAssets, "moonqr-scanner");
mkdirSync(moonqrOut, { recursive: true });
mkdirSync(scannerOut, { recursive: true });

// .js のみコピーする（.cjs はNode向け、.d.ts/.d.cts は型のみでブラウザに不要）。
// encode.js/decode.js/index.js が参照する chunk-*.js も対象（ワイルドカードで一括拾う）。
let copiedMoonqr = 0;
for (const name of readdirSync(moonqrDist)) {
  if (name.endsWith(".js") && !name.endsWith(".cjs")) {
    copyFileSync(path.join(moonqrDist, name), path.join(moonqrOut, name));
    copiedMoonqr++;
  }
}
if (copiedMoonqr === 0) {
  throw new Error(`@elchika-inc/moonqr/dist に .js が1つも無い (${moonqrDist})`);
}

let copiedScanner = 0;
for (const name of readdirSync(scannerDist)) {
  if (name.endsWith(".js") && !name.endsWith(".cjs")) {
    copyFileSync(path.join(scannerDist, name), path.join(scannerOut, name));
    copiedScanner++;
  }
}
if (copiedScanner === 0) {
  throw new Error(`@elchika-inc/moonqr-scanner/dist に .js が1つも無い (${scannerDist})`);
}

console.log(
  `build-site: ${copiedMoonqr} file(s) -> site/assets/moonqr/, ${copiedScanner} file(s) -> site/assets/moonqr-scanner/`,
);
