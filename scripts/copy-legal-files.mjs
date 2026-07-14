// npm は `files` フィールドでパッケージディレクトリの**外側**（相対パス上位 `../../LICENSE`
// 等）を同梱できない。ライセンス関連ファイル（LICENSE / NOTICE / THIRD_PARTY_LICENSES）は
// リポジトリルートに一箇所だけ置く（Task 1 の方針）ため、公開時（`npm pack` / `npm publish`
// が自動で走らせる `prepack` フック）にルートから各パッケージ直下へコピーする。
//
// コピー先はコミットしない（.gitignore 対象・生成物）。ソースが正でパッケージ側は毎回
// 再生成される使い捨てコピーという扱い。
//
// 実行 cwd はパッケージディレクトリ（pnpm/npm がスクリプトを実行する規約）を前提にする。
// リポジトリルートの位置はこのスクリプト自身の場所（import.meta.url）から解決するため、
// どのパッケージから呼んでも正しく動く。
import { copyFileSync, existsSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const repoRoot = join(dirname(fileURLToPath(import.meta.url)), "..");
const targetDir = process.cwd();

const files = ["LICENSE", "NOTICE", "THIRD_PARTY_LICENSES"];

for (const name of files) {
  const src = join(repoRoot, name);
  if (!existsSync(src)) {
    console.error(`copy-legal-files: ${src} が見つかりません`);
    process.exit(1);
  }
  copyFileSync(src, join(targetDir, name));
  console.log(`copy-legal-files: ${name} -> ${targetDir}/${name}`);
}
