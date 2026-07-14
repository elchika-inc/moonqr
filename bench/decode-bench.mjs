// Phase 2 Task 11: 自前 decode_js と jsQR (npm) の 640x480 フレームデコード
// 時間比較ベンチ。方法論は Phase 1 bench/run-node.mjs と同一
// （WARMUP=30 / ITERS=200 / median）。
//
// 合格基準（スペック rubric 2）: 自前 median ≤ jsQR median × 1.2 が
// hit フレーム・miss フレームの両方で成立すること。
//
// フレームは2種:
//   (a) hit  : bench/gen-frame.mjs 由来のノイズ背景に、encode_js で生成した
//              v2-M QR を packages/moonqr/test/lib/rasterize.mjs でラスタ化
//              し、非中央（オフセンター）位置に合成した 640x480 フレーム。
//              測定前に jsQR/自前の両方が実際にデコードでき、テキストが
//              一致することを検証する（デコードできないフレームを測ると
//              誤った経路を測定してしまうため）。
//   (b) miss : gen-frame.mjs の背景のみ（QR非合成）。両実装とも null を
//              返すことを測定前に検証する。
//
// jsQR は inversionAttempts: "attemptBoth"（主計測）/ "dontInvert"（参考）、
// 自前は invert=true（主計測、attemptBoth相当）/ invert=false（参考、
// dontInvert相当）で対応させる。
import { readFileSync, writeFileSync, appendFileSync, existsSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { execFileSync } from "node:child_process";
import jsQR from "jsqr";
import { genFrame } from "./gen-frame.mjs";
import { rasterize } from "../packages/moonqr/test/lib/rasterize.mjs";

const __dirname = dirname(fileURLToPath(import.meta.url));
const repoRoot = join(__dirname, "..");
const resultMdPath = join(repoRoot, "bench", "RESULT.md");

const decodeMod = await import(
  "../core/_build/js/release/build/decode/decode.js");
const encodeMod = await import(
  "../core/_build/js/release/build/encode/encode.js");
const { decode_js } = decodeMod;
const { encode_js } = encodeMod;

const EC_NUM = { L: 0, M: 1, Q: 2, H: 3 };
const WIDTH = 640, HEIGHT = 480;
const WARMUP = 30, ITERS = 200;

// --- フレーム生成 ---
// (a) hit: ノイズ背景 + v2-M QR をオフセンター位置に合成
const HIT_TEXT = "PERF BENCH DECODE TEST";
function buildHitFrame() {
  const bg = genFrame(WIDTH, HEIGHT, 42);
  const flat = encode_js(HIT_TEXT, EC_NUM.M, 2);
  if (flat.length === 0) throw new Error("encode_js failed for hit frame text");
  const raster = rasterize(flat, { scale: 5, margin: 4, seed: 7 });
  // オフセンター配置（画面中心 (235,155) 付近ではなく (400,180) — 右下寄り）。
  const ox = 400, oy = 180;
  if (ox + raster.width >= WIDTH || oy + raster.height >= HEIGHT) {
    throw new Error("rasterized QR does not fit in 640x480 frame at chosen offset");
  }
  const frame = Uint8Array.from(bg);
  for (let ry = 0; ry < raster.height; ry++) {
    for (let rx = 0; rx < raster.width; rx++) {
      const si = (ry * raster.width + rx) * 4;
      const di = ((oy + ry) * WIDTH + (ox + rx)) * 4;
      frame[di] = raster.data[si];
      frame[di + 1] = raster.data[si + 1];
      frame[di + 2] = raster.data[si + 2];
      frame[di + 3] = 255;
    }
  }
  return frame;
}

// (b) miss: gen-frame.mjs のノイズ背景のみ（QR非合成、Phase 1と同一生成）
function buildMissFrame() {
  return genFrame(WIDTH, HEIGHT, 42);
}

const hitFrame = buildHitFrame();
const missFrame = buildMissFrame();

// --- 事前検証: hit は両実装が同一テキストへデコードでき、miss は両方null ---
function jsqrDecode(frame, attemptBoth) {
  const res = jsQR(frame, WIDTH, HEIGHT, {
    inversionAttempts: attemptBoth ? "attemptBoth" : "dontInvert",
  });
  return res ? res.data : null;
}
function ourDecode(frame, invert) {
  const out = decode_js(frame, WIDTH, HEIGHT, invert);
  if (out === "") return null;
  return JSON.parse(out).text;
}

{
  const jsHit = jsqrDecode(hitFrame, true);
  const ourHit = ourDecode(hitFrame, true);
  if (jsHit !== HIT_TEXT) {
    throw new Error(`pre-check failed: jsQR did not decode hit frame correctly (got ${JSON.stringify(jsHit)})`);
  }
  if (ourHit !== HIT_TEXT) {
    throw new Error(`pre-check failed: our decode_js did not decode hit frame correctly (got ${JSON.stringify(ourHit)})`);
  }
  if (jsHit !== ourHit) {
    throw new Error(`pre-check failed: jsQR and ours disagree on hit frame text (${JSON.stringify(jsHit)} vs ${JSON.stringify(ourHit)})`);
  }
  const jsMiss = jsqrDecode(missFrame, true);
  const ourMiss = ourDecode(missFrame, true);
  if (jsMiss !== null) {
    throw new Error(`pre-check failed: jsQR unexpectedly decoded miss frame (got ${JSON.stringify(jsMiss)})`);
  }
  if (ourMiss !== null) {
    throw new Error(`pre-check failed: our decode_js unexpectedly decoded miss frame (got ${JSON.stringify(ourMiss)})`);
  }
  console.log("pre-check OK: hit frame decodes identically on both impls, miss frame is null on both");
}

// --- 計測 ---
// 結果消費ガード: 各イテレーションの戻り値を sink に集計してログする
// （Phase 1 run-node.mjs が hits を捕捉していたのと同じ趣旨。戻り値を捨てると
// JIT のデッドコード除去で計測対象の一部が消えるリスクがあるため、結果を
// 必ず消費して観測可能にする。hit フレームでは sink=ITERS（毎回デコード成功）、
// miss フレームでは sink=0 になるはず）。
function median(label, expectedSink, fn) {
  for (let i = 0; i < WARMUP; i++) fn();
  const times = [];
  let sink = 0;
  for (let i = 0; i < ITERS; i++) {
    const t0 = performance.now();
    const res = fn();
    times.push(performance.now() - t0);
    // jsQR は object|null、decode_js は string（"" = 失敗）を返す
    sink += typeof res === "string" ? (res.length > 0 ? 1 : 0) : res ? 1 : 0;
  }
  console.log(`  ${label}: sink=${sink}/${ITERS} decoded iterations`);
  if (sink !== expectedSink) {
    throw new Error(
      `sink mismatch for ${label}: got ${sink}, expected ${expectedSink} — ` +
      `measurement loop did not consistently exercise the intended path`,
    );
  }
  times.sort((a, b) => a - b);
  return times[Math.floor(ITERS / 2)];
}

// 実行順序の注記: 各フレームにつき jsQR → 自前 の固定順・非インターリーブで
// 計測する。時間経過によるドリフト（サーマルスロットリング・GC 圧の蓄積）は
// 後に走る側＝自前に不利に働くため、報告される自前優位に対して保守的な
// （優位を過小評価する方向の）バイアスであり、rubric 判定を甘くする方向には
// 働かない。
const results = {};
for (const [frameName, frame] of [["hit", hitFrame], ["miss", missFrame]]) {
  console.log(`measuring [${frameName}] frame:`);
  const exp = frameName === "hit" ? ITERS : 0;
  results[frameName] = {
    jsqrAttemptBoth: median("jsQR attemptBoth", exp, () => jsQR(frame, WIDTH, HEIGHT, { inversionAttempts: "attemptBoth" })),
    ourInvertTrue: median("ours invert=true ", exp, () => decode_js(frame, WIDTH, HEIGHT, true)),
    jsqrDontInvert: median("jsQR dontInvert  ", exp, () => jsQR(frame, WIDTH, HEIGHT, { inversionAttempts: "dontInvert" })),
    ourInvertFalse: median("ours invert=false", exp, () => decode_js(frame, WIDTH, HEIGHT, false)),
  };
}

// --- 判定 ---
const RATIO_MAX = 1.2;
let allPass = true;
const rows = [];
for (const frameName of ["hit", "miss"]) {
  const r = results[frameName];
  const ratioPrimary = r.ourInvertTrue / r.jsqrAttemptBoth;
  const ratioSecondary = r.ourInvertFalse / r.jsqrDontInvert;
  const pass = ratioPrimary <= RATIO_MAX;
  if (!pass) allPass = false;
  rows.push({ frameName, ...r, ratioPrimary, ratioSecondary, pass });
  console.log(
    `[${frameName}] jsQR(attemptBoth)=${r.jsqrAttemptBoth.toFixed(3)}ms ` +
    `ours(invert=true)=${r.ourInvertTrue.toFixed(3)}ms ratio=${ratioPrimary.toFixed(3)} ` +
    `${pass ? "PASS" : "FAIL"} (threshold ${RATIO_MAX}) | ` +
    `secondary: jsQR(dontInvert)=${r.jsqrDontInvert.toFixed(3)}ms ` +
    `ours(invert=false)=${r.ourInvertFalse.toFixed(3)}ms ratio=${ratioSecondary.toFixed(3)}`,
  );
}
console.log(`\njudgment (rubric 2, ours <= jsQR * ${RATIO_MAX} on BOTH frames): ${allPass ? "PASS" : "FAIL"}`);

// --- RESULT.md 追記（冪等: 既存セクションがあれば置換、なければ追記） ---
function commitHash() {
  try {
    return execFileSync("git", ["rev-parse", "--short", "HEAD"], { cwd: repoRoot }).toString().trim();
  } catch {
    return "(unknown, not a git repo checkout at bench time)";
  }
}

function moonVersion() {
  try {
    // `moon version` の1行目（例: "moon 0.1.20260703 (6fbf8c3 2026-07-03)"）
    return execFileSync("moon", ["version"]).toString().trim().split("\n")[0];
  } catch {
    return "(unknown, moon not on PATH at bench time)";
  }
}

const tableRows = rows.map((r) =>
  `| ${r.frameName} | ${r.jsqrAttemptBoth.toFixed(3)} | ${r.ourInvertTrue.toFixed(3)} | ` +
  `${r.ratioPrimary.toFixed(3)} | ${r.pass ? "PASS" : "FAIL"} | ${r.jsqrDontInvert.toFixed(3)} | ` +
  `${r.ourInvertFalse.toFixed(3)} | ${r.ratioSecondary.toFixed(3)} |`,
).join("\n");

const summary = `

## decode性能ベンチ jsQR比較（Task 11・2026-07-14）

### 環境

- node: \`${process.version}\`
- moon: \`${moonVersion()}\`
- arch: \`${process.arch}\` / platform: \`${process.platform}\`
- jsqr (npm): \`1.4.0\`
- commit: \`${commitHash()}\`

### 方法

Phase 1 (\`bench/run-node.mjs\`) と同一方法論: WARMUP=30, ITERS=200, median。
フレームは 640x480 RGBA、2種:
- **hit**: \`bench/gen-frame.mjs\` のノイズ背景（seed=42）に、\`encode_js\`
  で生成した v2-M QR（"${HIT_TEXT}"）を \`packages/moonqr/test/lib/rasterize.mjs\`
  でラスタ化（scale=5, margin=4, seed=7）し、オフセンター位置 (400,180) に
  合成。計測前に jsQR・自前の両方が実際にデコードでき、テキストが一致する
  ことを検証済み。
- **miss**: \`bench/gen-frame.mjs\` の背景のみ（QR非合成）。計測前に両実装
  とも null を返すことを検証済み。

jsQR は \`inversionAttempts\` オプションで対応: 主計測は \`"attemptBoth"\`
（自前 \`invert=true\` に相当）、参考計測は \`"dontInvert"\`（自前
\`invert=false\` に相当）。

計測フェアネスの注記:
- 各イテレーションの戻り値を sink に集計・検証している（JIT のデッドコード
  除去対策。hit で sink=ITERS、miss で sink=0 になることを assert 済み）。
- 実行順序は各フレームにつき jsQR → 自前 の固定順・非インターリーブ。時間
  経過によるドリフト（サーマル・GC）は後に走る自前側に不利に働くため、
  報告される自前優位に対して保守的なバイアス（rubric 判定を甘くしない方向）。

### 結果

| frame | jsQR attemptBoth (ms) | ours invert=true (ms) | ratio (ours/jsQR) | 判定 | jsQR dontInvert (ms, 参考) | ours invert=false (ms, 参考) | ratio (参考) |
|---|---|---|---|---|---|---|---|
${tableRows}

### 判定（スペック rubric 2）

**基準: 自前 median ≤ jsQR median × ${RATIO_MAX} が hit・miss 両フレームで成立すること。**

**判定: ${allPass ? "PASS" : "FAIL"}**
`;

const sectionMarker = "## decode性能ベンチ jsQR比較（Task 11";
const existingResultMd = existsSync(resultMdPath) ? readFileSync(resultMdPath, "utf8") : "";
const markerIdx = existingResultMd.indexOf(sectionMarker);
if (markerIdx === -1) {
  appendFileSync(resultMdPath, summary);
} else {
  // 既存セクションを最新の計測値で置換する（マーカーから次の "## " 見出し、
  // なければ末尾まで）。再実行でRESULT.mdが肥大化せず、常に最新値を反映する。
  const nextSection = existingResultMd.indexOf("\n## ", markerIdx + sectionMarker.length);
  const before = existingResultMd.slice(0, markerIdx).replace(/\n+$/, "\n");
  const after = nextSection === -1 ? "" : existingResultMd.slice(nextSection + 1);
  writeFileSync(resultMdPath, before + summary.replace(/^\n+/, "\n") + after);
}
console.log(summary);

if (!allPass) {
  process.exitCode = 1;
}
