// OGP 画像 (site/og-image.png) の元になる HTML を生成するスクリプト。
//
// 生成物は 2 つに分かれる。
//   site/og-image.html — 本スクリプトが生成する。1200x630 に組んだレイアウト
//   site/og-image.png  — その HTML をブラウザで 1200x630 で撮った PNG（手作業・下記手順）
//
// なぜ PNG を直接生成しないか: 画像に文字を描くにはフォントのラスタライズが要る。
// pngjs はピクセル操作しか持たず、SVG→PNG 変換やテキスト描画を入れるには
// ネイティブ依存（sharp / resvg / node-canvas）を足すことになる。依存ゼロを売りに
// するライブラリの devDependencies を OGP 画像 1 枚のために重くしたくない。
// standards PRODUCT_PLAYBOOK「シェア・OGP」も LP は固定の og-image.png で可としており、
// demo の URL が変わらない限り再生成は起きない。ブラウザで 1 回撮る運用で足りる。
//
// 左側の QR は moonqr 自身の to_svg_string_js で生成した本物で、デモページの URL を
// エンコードしている（読むとこのページに来る）。EC レベルと version は固定値で指定する
// ——auto 選択のままだと、将来エンコーダのセグメント最適化が改善したときに version が
// 変わり、同じ URL から別の画像が出る。
//
// 再生成の手順:
//   1. cd core && moon build --target js --release && cd ..
//   2. node scripts/gen-og-image.mjs          # site/og-image.html を書き出す
//   3. npx serve site  などで site/ を HTTP で配る（file:// はブラウザ側で拒否される）
//   4. ブラウザのビューポートを 1200x630 にして og-image.html を開き、
//      ビューポートのスクリーンショットを site/og-image.png として保存する
//      （device pixel ratio が 2 の環境では 2400x1260 になるので、CSS ピクセル基準で撮ること）
//   5. 検証: file site/og-image.png が "1200 x 630" を返すこと。
//      さらに PNG を decode_js に通して、デコード結果の text が DEMO_URL と一致すること
import { writeFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const repoRoot = fileURLToPath(new URL("..", import.meta.url));
const encodePath = path.join(repoRoot, "core/_build/js/release/build/encode/encode.js");

const DEMO_URL = "https://elchika-inc.github.io/moonqr/";
// to_svg_string_js(text, ecLevel, version, margin, cell)
// ecLevel: 0=L 1=M 2=Q 3=H / version: 0 は auto。ここは決定的にするため固定する。
const EC_M = 1;
const VERSION = 3; // DEMO_URL を EC=M で収める最小 version（29 モジュール）。実測で確認済み
const MARGIN = 4; // quiet zone。QR 規格が要求する最小値
const CELL = 1;

const { to_svg_string_js } = await import(encodePath);
const qrSvg = to_svg_string_js(DEMO_URL, EC_M, VERSION, MARGIN, CELL);
if (!qrSvg || !qrSvg.startsWith("<svg")) {
  throw new Error(
    `to_svg_string_js returned no SVG. core/_build が古い可能性がある（手順 1 を実行したか確認する）`,
  );
}

const html = `<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <title>moonqr — OGP image source (1200x630)</title>
    <!--
      このファイルは scripts/gen-og-image.mjs が生成する。直接編集しない。
      site/og-image.png はこのページを 1200x630 のビューポートで撮ったもの。
      配色のうち背景 #08090b とアクセント #f2c744 は site/style.css と同じ値で、
      文字色の #f4f5f7 / #b9bdc7 / #6d727e は OGP のコントラスト用にここで決めている。
      style.css を参照せず直書きするのは、デモの配色変更が画像へ意図せず波及しないようにするため。
    -->
    <style>
      * { margin: 0; padding: 0; box-sizing: border-box; }
      html, body { width: 1200px; height: 630px; }
      body {
        background: #08090b;
        display: flex;
        align-items: center;
        gap: 64px;
        padding: 0 80px;
        font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", system-ui, sans-serif;
        color: #f4f5f7;
      }
      .qr {
        width: 400px;
        height: 400px;
        background: #fff;
        border-radius: 16px;
        padding: 16px;
        flex: none;
      }
      .qr svg { width: 100%; height: 100%; display: block; }
      .txt { display: flex; flex-direction: column; gap: 18px; }
      h1 { font-size: 92px; letter-spacing: -0.03em; font-weight: 700; line-height: 1; }
      .tag { font-size: 34px; color: #b9bdc7; line-height: 1.35; font-weight: 400; }
      .meta { font-size: 26px; color: #f2c744; font-weight: 600; }
      .url {
        font-size: 20px;
        color: #6d727e;
        font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
        margin-top: 6px;
      }
    </style>
  </head>
  <body>
    <div class="qr">${qrSvg}</div>
    <div class="txt">
      <h1>moonqr</h1>
      <p class="tag">QR encoder &amp; decoder<br />written in MoonBit</p>
      <p class="meta">Zero dependencies · Plain JavaScript</p>
      <p class="url">elchika-inc.github.io/moonqr</p>
    </div>
  </body>
</html>
`;

const outPath = path.join(repoRoot, "site/og-image.html");
writeFileSync(outPath, html);
console.log(
  `OK: wrote ${path.relative(repoRoot, outPath)} (${html.length} bytes, QR version ${VERSION}, EC M)`,
);
