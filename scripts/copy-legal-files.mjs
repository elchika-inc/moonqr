// npm は `files` フィールドでパッケージディレクトリの**外側**（相対パス上位 `../../LICENSE`
// 等）を同梱できない。ライセンス関連ファイル（LICENSE / NOTICE / THIRD_PARTY_LICENSES）は
// リポジトリルートに一箇所だけ置く（Task 1 の方針）ため、公開時（`npm pack` / `npm publish`
// が自動で走らせる `prepack` フック）にルートから各パッケージ直下へコピーする。
//
// packages/* 向けのコピー先はコミットしない（.gitignore 対象・生成物）。ソースが正で
// パッケージ側は毎回再生成される使い捨てコピーという扱い（cwd 実行、引数なし）。
//
// core/（mooncakes 向け MoonBit モジュール）は事情が異なる: `moon publish` には npm の
// `prepack` に相当するライフサイクルフックが存在せず、`moon package --list` は
// モジュールルート（moon.mod.json のあるディレクトリ）直下に物理的に存在するファイルしか
// 同梱できない（`../` 等モジュール外を参照する include 機構もない。実測で確認済み）。
// そのため core/LICENSE・core/NOTICE・core/THIRD_PARTY_LICENSES は生成物ではなく
// **コミット対象**（.gitignore 対象外）。ルートの3ファイルを更新したら
// `node scripts/copy-legal-files.mjs core`（= `pnpm run sync-legal:core`）を実行して
// core/ 側のコピーを再同期し、diff をコミットすること。
//
// 引数なし: 実行 cwd をコピー先とする（pnpm/npm の prepack 規約、packages/* 向け）。
// 引数あり: リポジトリルートからの相対パスをコピー先とする（例: `core`）。
// リポジトリルートの位置はこのスクリプト自身の場所（import.meta.url）から解決するため、
// どこから呼んでも正しく動く。
import { copyFileSync, existsSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const repoRoot = join(dirname(fileURLToPath(import.meta.url)), "..");
const targetArg = process.argv[2];
const targetDir = targetArg ? join(repoRoot, targetArg) : process.cwd();

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
