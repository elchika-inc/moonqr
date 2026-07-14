// Phase 2 Task 10: jsQR e2e コーパスでのパリティ測定。
//
// jsQR (Apache-2.0, cozmo) 自身の end-to-end テストコーパス（254ケース、
// commit 8e6a036beafa7053dd44b1b76ac578d22b1b3311 で固定・scripts/fetch-fixtures.mjs
// で取得）に対して、jsqr npm パッケージと自前 decode_js の両方を実行し、
// テキスト一致による成功数を比較する。
//
// **合格基準（スペック rubric 1）: 自前の成功数 ≥ jsQR の成功数。** これが
// このファイル唯一のテストであり、実体は node --test の形を借りた測定
// レポート（結果は bench/RESULT.md にも追記する）。
//
// 分母の扱い: コーパスの output.json は40件が null（jsQR自身も読めない
// negativeケース）。ground truth が存在しないため、これらは「テキスト一致」
// 指標の分母から除外し、raw success/failure（何か結果を返したか）のみを
// 参考記録する（brief の指示通り）。
import { test } from "node:test";
import assert from "node:assert";
import { readFileSync, readdirSync, existsSync, appendFileSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { execFileSync } from "node:child_process";
import jsQR from "jsqr";
import { PNG } from "pngjs";

const __dirname = dirname(fileURLToPath(import.meta.url));
const repoRoot = join(__dirname, "..", "..", "..");
const fixturesDir = join(repoRoot, "fixtures", "jsqr-e2e");
const fetchScript = join(repoRoot, "scripts", "fetch-fixtures.mjs");
const resultMdPath = join(repoRoot, "bench", "RESULT.md");

// ビルド出力パス規約は roundtrip.test.mjs 等と同じ。
const decodeMod = await import(
  "../../../core/_build/js/release/build/decode/decode.js");
const { decode_js } = decodeMod;

test("jsQR e2e corpus parity: our success count >= jsQR success count (spec rubric 1)", () => {
  // fixture 取得（冪等: scripts/fetch-fixtures.mjs は既に正しい件数揃っていれば
  // 再取得せずスキップする。ネットワーク到達性が前提）。
  execFileSync(process.execPath, [fetchScript], { stdio: "inherit" });
  assert.ok(
    existsSync(fixturesDir),
    "fixtures/jsqr-e2e must exist after running scripts/fetch-fixtures.mjs",
  );

  const cases = readdirSync(fixturesDir, { withFileTypes: true })
    .filter((e) => e.isDirectory())
    .map((e) => e.name)
    .sort();
  assert.ok(cases.length > 0, "expected at least one fixture case");

  // text-match（ground truth = output.json != null のケースのみ）
  let jsqrSuccess = 0;
  let ourSuccess = 0;
  const jsqrOnlyFail = []; // jsQRは一致・自前は不一致/失敗
  const oursOnlyFail = []; // 自前は一致・jsQRは不一致/失敗
  // jsQR/自前が非null結果を返したが期待テキストと食い違った件（本来ゼロのはず。
  // 発生した場合は「間違った結果を自信満々に返す」= 見た目の成功より深刻な
  // バグの兆候なので個別記録する）。
  const jsqrWrongText = [];
  const ourWrongText = [];

  // raw success（ground truth無し = output.json==null の40ケース。参考記録のみ、
  // rubric の分母には含めない）。
  let jsqrRawSuccessNoGt = 0;
  let ourRawSuccessNoGt = 0;
  const negativeCasesJsqrFalsePositive = [];
  const negativeCasesOurFalsePositive = [];

  let gtCount = 0;
  let negativeCount = 0;

  for (const c of cases) {
    const dir = join(fixturesDir, c);
    const png = PNG.sync.read(readFileSync(join(dir, "input.png")));
    const expected = JSON.parse(readFileSync(join(dir, "output.json"), "utf8"));

    let jsResult = null;
    try {
      jsResult = jsQR(png.data, png.width, png.height, { inversionAttempts: "attemptBoth" });
    } catch {
      jsResult = null;
    }
    let ourResult = null;
    try {
      const out = decode_js(png.data, png.width, png.height, true);
      ourResult = out === "" ? null : JSON.parse(out);
    } catch {
      ourResult = null;
    }

    const jsText = jsResult ? jsResult.data : null;
    const ourText = ourResult ? ourResult.text : null;

    if (expected !== null) {
      gtCount++;
      const jsMatch = jsText === expected.data;
      const ourMatch = ourText === expected.data;
      if (jsMatch) jsqrSuccess++;
      if (ourMatch) ourSuccess++;
      if (jsText !== null && !jsMatch) jsqrWrongText.push(c);
      if (ourText !== null && !ourMatch) ourWrongText.push(c);
      if (jsMatch && !ourMatch) jsqrOnlyFail.push(c);
      if (ourMatch && !jsMatch) oursOnlyFail.push(c);
    } else {
      negativeCount++;
      if (jsText !== null) {
        jsqrRawSuccessNoGt++;
        negativeCasesJsqrFalsePositive.push(c);
      }
      if (ourText !== null) {
        ourRawSuccessNoGt++;
        negativeCasesOurFalsePositive.push(c);
      }
    }
  }

  const listOrNone = (arr) => (arr.length === 0 ? "(なし)" : arr.join(", "));

  const summary = `

## jsQR e2eコーパスパリティ測定（Task 10・2026-07-14）

### 環境

- node: \`${process.version}\`
- jsqr (npm): \`1.4.0\`
- jsQR移植元 pinned commit: \`8e6a036beafa7053dd44b1b76ac578d22b1b3311\`（P2 Task 2で固定した値と同一）
- コーパス取得元: jsQR \`tests/end-to-end/\`（\`scripts/fetch-fixtures.mjs\` で shallow clone → \`fixtures/jsqr-e2e/\`、gitignore対象）

### コーパス概要

- 総ケース数: **${cases.length}**
- ground truth あり（output.json != null）: **${gtCount}**
- ground truth なし（output.json == null、jsQR自身も読めないnegativeケース）: **${negativeCount}**

### 判定基準（スペック rubric 1）

自前 decode_js の成功数 ≥ jsQR (npm) の成功数。成功 = jsQR/自前の返したテキストが
output.json の \`data\` フィールドと**一致**すること（output.json が null のケースは
ground truth が無いため、この一致判定の分母から除外——raw success/failure のみ参考記録）。

### 結果（text-match, ground truth ${gtCount}件中）

| | jsQR (npm) | 自前 (decode_js) |
|---|---|---|
| 成功数 | ${jsqrSuccess} | ${ourSuccess} |
| 成功率 | ${((jsqrSuccess / gtCount) * 100).toFixed(1)}% | ${((ourSuccess / gtCount) * 100).toFixed(1)}% |

**判定: 自前(${ourSuccess}) ${ourSuccess >= jsqrSuccess ? "≥" : "<"} jsQR(${jsqrSuccess}) → rubric ${ourSuccess >= jsqrSuccess ? "PASS" : "FAIL"}**

- jsQRのみ成功（自前は不一致/失敗）: ${jsqrOnlyFail.length}件 — ${listOrNone(jsqrOnlyFail)}
- 自前のみ成功（jsQRは不一致/失敗）: ${oursOnlyFail.length}件 — ${listOrNone(oursOnlyFail)}
- jsQRが非null結果を返したが期待テキストと不一致: ${jsqrWrongText.length}件 — ${listOrNone(jsqrWrongText)}
- 自前が非null結果を返したが期待テキストと不一致: ${ourWrongText.length}件 — ${listOrNone(ourWrongText)}

### 参考: ground truth無しケース（output.json==null、${negativeCount}件）の raw success

rubricの分母には含めない（一致判定の基準が無いため）。jsQR自身が読めないnegativeケースに
対して非null結果を返す＝誤検出（false positive）の可能性がある、という観点でのみ参考記録。

- jsQRが非null結果を返した件数: ${jsqrRawSuccessNoGt} — ${listOrNone(negativeCasesJsqrFalsePositive)}
- 自前が非null結果を返した件数: ${ourRawSuccessNoGt} — ${listOrNone(negativeCasesOurFalsePositive)}

### 分類・対応（初回測定で判明した1件差分の修正）

初回測定（対角ミラー再試行の実装前）: 自前213 < jsQR214（\`bike-1\`ケースのみ差分）。
\`bike-1\`は実写真（約90度回転したQR）で、format/version情報の読取までは成功するが
codewords段で失敗——jsQR \`decoder.ts\` の \`decode()\` が実装する「抽出行列を対角線
(TL-BR)でミラー（転置）して再試行」（locatorのファインダtop-right/bottom-left取り違え
を補正する経路）が自前には未実装だったことが原因と特定した。

対応: \`core/src/decode/decode.mbt\` に \`try_decode_matrix\`（format/version/data
フルパイプラインの抽出）と \`mirror_matrix\`（対角線転置、in-place）を追加し、\`scan()\`
が通常抽出行列で失敗した候補に対してミラー再試行を1回行うようjsQR \`decoder.ts\`を
忠実移植した。再測定で自前214=jsQR214の完全一致となり、rubric達成。

whiteboxテスト \`core/src/decode/decode_wbtest.mbt\` で
(1) \`mirror_matrix\`のinvolution性（2回適用で元に戻る）、
(2) \`scan()\`レベルでミラー再試行が転置画像を実際に救うこと（mutation checkで
再試行を無効化すると同テストが確実に失敗することを確認済み）
の2点をピン留めした。

### 再現手順

\`\`\`bash
export PATH="$HOME/.moon/bin:$PATH"
node scripts/fetch-fixtures.mjs   # 冪等: 既にfixtures/jsqr-e2e/があればスキップ
cd core && moon build --target js --release && cd ..
node --test packages/moonqr/test/jsqr-parity.test.mjs
\`\`\`
`;

  // 冪等: 既にこのセクションが追記済みならRESULT.mdへの再追記はスキップする
  // （node --test の繰り返し実行でRESULT.mdが際限なく肥大化するのを防ぐ。
  // rubricのアサート自体は毎回実行される）。
  const sectionMarker = "## jsQR e2eコーパスパリティ測定（Task 10";
  const existingResultMd = existsSync(resultMdPath) ? readFileSync(resultMdPath, "utf8") : "";
  if (!existingResultMd.includes(sectionMarker)) {
    appendFileSync(resultMdPath, summary);
  }

  console.log(summary);

  // THE RUBRIC ASSERT（スペック rubric 1）
  assert.ok(
    ourSuccess >= jsqrSuccess,
    `rubric failed: ourSuccess=${ourSuccess} < jsqrSuccess=${jsqrSuccess}. ` +
      `jsQR-only fails (jsQR success, ours fails): ${jsqrOnlyFail.join(", ")}`,
  );
});
