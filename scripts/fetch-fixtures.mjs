// jsQR (Apache-2.0, cozmo) の end-to-end テストコーパス（tests/end-to-end/）を
// Task 3 で固定した commit から取得し、fixtures/jsqr-e2e/ へコピーする。
//
// fixtures/ はリポジトリに含めない（.gitignore・再取得可能・リポジトリ肥大回避）ため、
// パリティ測定（packages/moonqr/test/jsqr-parity.test.mjs）を走らせる前に本スクリプトの
// 実行が必要。冪等: 既に想定件数ぶん揃っていれば再取得をスキップする。
//
// 移植元コミットを固定する（P2 Task 2 で確定、sjis生成スクリプトと同じ値）。
const COMMIT = "8e6a036beafa7053dd44b1b76ac578d22b1b3311";
const REPO_URL = "https://github.com/cozmo/jsQR.git";

// 固定コミット時点の tests/end-to-end/ 実測件数（254フォルダ、全て input.png +
// output.json を持つ。output.json は40件が null=jsQR自身も読めないnegativeケース）。
// commit を固定している以上この数は決定的なので、冪等スキップの検証にそのまま使う。
const EXPECTED_CASE_COUNT = 254;

import { existsSync, mkdtempSync, mkdirSync, readdirSync, rmSync, cpSync, statSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { execFileSync } from "node:child_process";

const __dirname = dirname(fileURLToPath(import.meta.url));
const repoRoot = join(__dirname, "..");
const fixturesDir = join(repoRoot, "fixtures", "jsqr-e2e");

// ケースフォルダ名は数字だけ（"0","1",...）とは限らない。jsQR の実コーパスには
// "cupcake-1" 等の説明的な名前のフォルダも約70件含まれる（254件中185件のみ数字名）。
// なのでフォルダ名では絞らず、直下の全ディレクトリをケース候補として扱う。
function listCaseDirs(dir) {
  if (!existsSync(dir)) return [];
  return readdirSync(dir, { withFileTypes: true })
    .filter((e) => e.isDirectory())
    .map((e) => e.name);
}

function verify(dir, { quiet = false } = {}) {
  const cases = listCaseDirs(dir);
  const missing = [];
  for (const c of cases) {
    const inputPng = join(dir, c, "input.png");
    const outputJson = join(dir, c, "output.json");
    if (!existsSync(inputPng)) missing.push(`${c}/input.png`);
    if (!existsSync(outputJson)) missing.push(`${c}/output.json`);
  }
  const ok = cases.length === EXPECTED_CASE_COUNT && missing.length === 0;
  if (!quiet) {
    console.log(`fixtures/jsqr-e2e: ${cases.length} case folders (expected ${EXPECTED_CASE_COUNT})`);
    if (missing.length > 0) {
      console.log(`  missing files (${missing.length}):`, missing.slice(0, 10));
    }
  }
  return { ok, cases, missing };
}

// --- 冪等チェック: 既に正しい件数ぶん揃っていれば再取得をスキップ ---
if (existsSync(fixturesDir)) {
  const check = verify(fixturesDir, { quiet: true });
  if (check.ok) {
    console.log(
      `fixtures/jsqr-e2e already populated (${check.cases.length}/${EXPECTED_CASE_COUNT} cases, all input.png/output.json present). Skipping fetch.`,
    );
    process.exit(0);
  }
  console.log(
    `fixtures/jsqr-e2e exists but incomplete (${check.cases.length}/${EXPECTED_CASE_COUNT} cases, ${check.missing.length} missing files). Re-fetching.`,
  );
  rmSync(fixturesDir, { recursive: true, force: true });
}

// --- shallow clone (scratch) ---
const cloneDir = mkdtempSync(join(tmpdir(), "moonqr-jsqr-fixtures-"));
console.log(`cloning jsQR@${COMMIT} into ${cloneDir} (shallow)...`);
try {
  execFileSync("git", ["init", "-q"], { cwd: cloneDir, stdio: "inherit" });
  execFileSync("git", ["remote", "add", "origin", REPO_URL], { cwd: cloneDir, stdio: "inherit" });
  execFileSync("git", ["fetch", "--depth", "1", "origin", COMMIT], { cwd: cloneDir, stdio: "inherit" });
  execFileSync("git", ["checkout", "-q", "FETCH_HEAD"], { cwd: cloneDir, stdio: "inherit" });

  const actualHead = execFileSync("git", ["rev-parse", "HEAD"], { cwd: cloneDir }).toString().trim();
  if (actualHead !== COMMIT) {
    throw new Error(`checked out HEAD ${actualHead} does not match pinned commit ${COMMIT}`);
  }

  const srcE2e = join(cloneDir, "tests", "end-to-end");
  if (!existsSync(srcE2e)) {
    throw new Error(`tests/end-to-end/ not found in clone at ${srcE2e}`);
  }

  mkdirSync(dirname(fixturesDir), { recursive: true });
  cpSync(srcE2e, fixturesDir, { recursive: true });
} finally {
  rmSync(cloneDir, { recursive: true, force: true });
}

// --- 検証 ---
const result = verify(fixturesDir);
if (!result.ok) {
  console.error(
    `FAILED: fixtures/jsqr-e2e verification failed (got ${result.cases.length} cases, expected ${EXPECTED_CASE_COUNT}; ${result.missing.length} missing files)`,
  );
  process.exit(1);
}
console.log(`OK: fixtures/jsqr-e2e ready (${result.cases.length} cases, all input.png/output.json present).`);
