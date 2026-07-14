// Dependency-free i18n: a flat dictionary + `data-i18n` attribute binding.
// No build step, no external library — matches the "zero external requests" constraint
// for this page (see site/index.html header comment).
//
// Usage:
//   - Static text: add `data-i18n="some.key"` to an element; its textContent is replaced.
//   - Attributes (placeholder, aria-label, title, ...): `data-i18n-attr="placeholder:some.key"`
//     (multiple pairs separated by `;`).
//   - Dynamic strings built at runtime (e.g. app.js status messages): call `t("some.key", vars)`.
//     `{varName}` placeholders in the string are substituted from `vars`.
//
// Language choice persists in localStorage under STORAGE_KEY and defaults to English.

const STORAGE_KEY = "moonqr-lang";
const DEFAULT_LANG = "en";

export const translations = {
  en: {
    "nav.brand": "moonqr",
    "nav.github": "GitHub",
    "nav.langToggle": "日本語",

    "hero.eyebrow": "QR ENCODER + DECODER · MOONBIT → JS",
    "hero.title": "QR codes, compiled from MoonBit.",
    "hero.subtitle":
      "An encoder and decoder for QR codes, written in MoonBit and compiled to plain JavaScript. Zero runtime dependencies, runs entirely in the browser — try it below.",
    "hero.ctaDemo": "Try the demo ↓",
    "hero.ctaGithub": "View on GitHub",
    "hero.badge1": "214/214 decoder parity with jsQR",
    "hero.badge2": "faster than jsQR",
    "hero.badge3": "6.4 KB gzip encoder",

    "demo.heading": "Try it now",
    "demo.intro":
      "Everything below runs entirely in your browser — no server, no external requests. Open the console or the network tab if you don't believe it.",
    // NOTE: keys ending in the elements listed under data-i18n-html (read.intro, camera.intro,
    // footer.attribution) intentionally contain hand-written HTML (<code>/<a> tags only, no
    // interpolated user data) — see the data-i18n-html handling in applyStaticI18n() below.
    // Plain data-i18n keys must stay pure text, since applyStaticI18n() sets .textContent for
    // those and would otherwise silently strip nested markup.

    "generate.heading": "1. Generate — text → QR",
    "generate.textLabel": "Text",
    "generate.ecLabel": "Error correction level",
    "generate.ecL": "L (Low)",
    "generate.ecM": "M (Medium)",
    "generate.ecQ": "Q (Quartile)",
    "generate.ecH": "H (High)",
    "generate.versionLabel": "Version",
    "generate.versionAuto": "Auto (smallest)",
    "generate.waiting": "Waiting for input…",
    "generate.enterText": "Enter some text",
    "generate.cannotGenerate":
      "Can't generate (capacity exceeded, or an invalid version / EC-level combination)",
    "generate.statusOk": "OK: {size}x{size} modules / EC {ec}{versionNote}",
    "generate.versionAutoNote": " (auto-selected)",
    "generate.versionNote": " / v{version}",
    "generate.downloadSvg": "Download SVG",

    "read.heading": "2. Read — image file",
    "read.intro":
      "Uses QrScanner's multiscale decode (<code>scanImage</code>). Works on screenshots and downscaled images — even photos of a QR code shown on a monitor — by trying a downscale pyramid from the smallest scale first.",
    "read.dropzone": "Drag & drop a QR image here, or click to choose a file",
    "read.success": "✓ Decoded ({scaleNote})",
    "read.scaleNative": "native scale",
    "read.scaleN": "1/{scale} scale",
    "read.fail": "✗ Failed (no QR code detected)",
    "read.error": "✗ Error: {message}",
    "read.text": "Text",
    "read.version": "Version",
    "read.ecLevel": "EC level",
    "read.attempts": "Scales tried (small → large)",

    "camera.heading": "3. Read — live camera",
    "camera.intro":
      "<code>navigator.mediaDevices.getUserMedia</code> only works over HTTPS or localhost (secure-context restriction). On an insecure origin, without a camera, or if permission is denied, this shows a clear error instead of failing silently.",
    "camera.start": "Start camera",
    "camera.stop": "Stop",
    "camera.requesting":
      "Requesting camera access… (check your browser's permission prompt)",
    "camera.scanning": "Scanning… point the camera at a QR code.",
    "camera.stopped": "Stopped.",
    "camera.insecure":
      "This page is not a secure context (HTTPS or localhost), so the camera can't start.",
    "camera.noCamera":
      "getUserMedia isn't available in this environment, or this isn't a secure context (HTTPS/localhost required).",
    "camera.readyPrompt": "Press “Start camera” — your browser will ask for permission.",
    "camera.startFailed": "Could not start the camera: {message}",
    "camera.scannerError": "Scanner error: {message}",
    "camera.detected": "✓ Detected",

    "numbers.heading": "By the numbers",
    "numbers.parityTitle": "Decoder parity",
    "numbers.parityValue": "214 / 214",
    "numbers.parityDesc":
      "Exact-text match with jsQR on jsQR's own 254-image end-to-end corpus. The 40 images jsQR itself can't read, we correctly reject too.",
    "numbers.speedTitle": "Decoder speed",
    "numbers.speedValue": "0.77x / 0.75x",
    "numbers.speedDesc":
      "Frame time relative to jsQR at 640×480 — with a QR present / without one. Lower is faster.",
    "numbers.encodeTitle": "Encoder parity",
    "numbers.encodeValue": "160 / 160",
    "numbers.encodeDesc":
      "Cell-for-cell match against the qrcode npm package across every version × EC-level combination.",
    "numbers.bundleTitle": "Bundle size",
    "numbers.bundleValue": "6.4 KB / ~50 KB",
    "numbers.bundleDesc":
      "gzip, encode-only subpath / full decoder. Import just the part you use.",
    "numbers.evidence": "See bench/RESULT.md →",

    "moonbit.heading": "Why MoonBit",
    "moonbit.body1":
      "MoonBit is a modern, statically-typed language that targets Wasm, JS, and native. Two backends matter for the browser — js and wasm-gc — so before committing to one, we measured both on the real decode workload, boundary costs included.",
    "moonbit.body2":
      "The result: the js backend was 1.99x faster than wasm-gc (geometric mean across Node and Chrome). wasm-gc has no bulk-transfer path yet for moving a Uint8Array into a FixedArray[Byte] — every pixel crosses the JS↔wasm boundary one element at a time. So this project ships the js backend.",
    "moonbit.evidence": "Full methodology →",

    "story.heading": "War story: QR codes on a monitor",
    "story.body1":
      "A photo of a QR code shown on a monitor picks up the screen's sub-pixel grid as high-frequency noise. Naive block-based binarization mistakes it for near-50% speckle and can't find the finder patterns — jsQR fails on these too, so this isn't a bug in our binarizer.",
    "story.body2":
      "A single-step downscale makes it worse — it aliases the grid instead of filtering it. The fix is a small-scale-first multiscale pyramid: box-averaged (2×2 mean, a real low-pass filter) downscales, tried smallest first. On a real monitor-photo test case this cut decode time from ~5.4s to ~62ms, because the small scale that actually works is reached immediately instead of after every larger scale has already failed.",
    "story.evidence": "Full write-up →",

    "install.heading": "Install",
    "install.note":
      "@elchika-inc/moonqr and @elchika-inc/moonqr-scanner aren't published to npm yet — the snippets below show the API you'll use once they are. To try it today, clone the repo and build it locally.",
    "install.encodeTitle": "Encode → SVG",
    "install.decodeTitle": "Decode → from ImageData",
    "install.cameraTitle": "Live camera scan",

    "limitations.heading": "Limitations",
    "limitations.kanji":
      "Kanji-mode encoding is not supported — Japanese (and other non-ASCII) text is always encoded as byte-mode UTF-8, which is valid but not maximally compact. Decoding Kanji-mode QR codes made by other encoders is fully supported.",
    "limitations.segments":
      "No mixed-mode segment optimization — the encoder picks one mode (Numeric / Alphanumeric / Byte) for the whole input rather than splitting mixed content into per-segment optimal modes.",
    "limitations.eci":
      "No ECI, Structured Append, or Micro QR — only standard (Model 2) QR codes with default byte-mode handling are supported.",

    "footer.github": "GitHub",
    "footer.npm": "npm",
    "footer.mooncakes": "mooncakes.io",
    "footer.license": "License",
    "footer.attribution":
      'Portions of the decoder are ported from <a href="https://github.com/cozmo/jsQR" target="_blank" rel="noopener">jsQR</a> (Apache-2.0); the Reed–Solomon block / alignment-pattern position tables are derived from <a href="https://github.com/kazuhikoarase/qrcode-generator" target="_blank" rel="noopener">qrcode-generator</a> (MIT).',
    "footer.comingSoon": "(coming soon)",
  },

  ja: {
    "nav.brand": "moonqr",
    "nav.github": "GitHub",
    "nav.langToggle": "English",

    "hero.eyebrow": "QRエンコーダ/デコーダ · MoonBit → JS",
    "hero.title": "MoonBitからコンパイルされたQRコード。",
    "hero.subtitle":
      "MoonBitで書かれ、素のJavaScriptにコンパイルされたQRコードのエンコーダ/デコーダです。ランタイム依存ゼロ、ブラウザ内で完結して動作します — 下のデモを今すぐ試せます。",
    "hero.ctaDemo": "デモを試す ↓",
    "hero.ctaGithub": "GitHubで見る",
    "hero.badge1": "jsQRとデコーダ完全パリティ 214/214",
    "hero.badge2": "jsQRより高速",
    "hero.badge3": "エンコーダ 6.4KB gzip",

    "demo.heading": "今すぐ試す",
    "demo.intro":
      "以下はすべてブラウザ内だけで完結します — サーバーへのアクセスも外部リクエストもありません。コンソールやネットワークタブで確認できます。",

    "generate.heading": "1. 生成 — テキスト → QR",
    "generate.textLabel": "テキスト",
    "generate.ecLabel": "エラー訂正レベル",
    "generate.ecL": "L（低）",
    "generate.ecM": "M（標準）",
    "generate.ecQ": "Q（高）",
    "generate.ecH": "H（最高）",
    "generate.versionLabel": "バージョン",
    "generate.versionAuto": "自動（最小サイズ）",
    "generate.waiting": "入力を待機中…",
    "generate.enterText": "テキストを入力してください",
    "generate.cannotGenerate":
      "生成できません（容量超過、またはバージョンとECレベルの組み合わせが不正）",
    "generate.statusOk": "OK: {size}x{size} モジュール / EC {ec}{versionNote}",
    "generate.versionAutoNote": "（自動選択）",
    "generate.versionNote": " / v{version}",
    "generate.downloadSvg": "SVGをダウンロード",

    "read.heading": "2. 読取 — 画像ファイル",
    "read.intro":
      "QrScannerのマルチスケールデコード（<code>scanImage</code>）を使用します。モニター越しの撮影や縮小画像でも、小さいスケールから段階的な縮小ピラミッドを試すことで読み取れます。",
    "read.dropzone": "ここにQR画像をドラッグ&ドロップ、またはクリックして選択",
    "read.success": "✓ 読取成功（{scaleNote}）",
    "read.scaleNative": "等倍",
    "read.scaleN": "1/{scale}スケール",
    "read.fail": "✗ 読取失敗（QRコードを検出できませんでした）",
    "read.error": "✗ エラー: {message}",
    "read.text": "テキスト",
    "read.version": "バージョン",
    "read.ecLevel": "ECレベル",
    "read.attempts": "試行スケール（小→大）",

    "camera.heading": "3. 読取 — カメラ・ライブスキャン",
    "camera.intro":
      "<code>navigator.mediaDevices.getUserMedia</code>はHTTPSまたはlocalhostでのみ利用できます（Secure Context制約）。非対応環境・カメラなし・権限拒否時は、失敗を隠さず明確なエラーを表示します。",
    "camera.start": "カメラ開始",
    "camera.stop": "停止",
    "camera.requesting":
      "カメラへのアクセスを要求しています…（ブラウザの許可ダイアログを確認してください）",
    "camera.scanning": "スキャン中… QRコードをカメラに向けてください。",
    "camera.stopped": "停止しました。",
    "camera.insecure":
      "このページはSecure Context（HTTPSまたはlocalhost）ではないため、カメラを起動できません。",
    "camera.noCamera":
      "この環境ではgetUserMediaが利用できないか、Secure Contextではありません（HTTPS/localhostが必要です）。",
    "camera.readyPrompt": "「カメラ開始」を押すとブラウザの許可ダイアログが表示されます。",
    "camera.startFailed": "カメラを起動できませんでした: {message}",
    "camera.scannerError": "スキャナエラー: {message}",
    "camera.detected": "✓ 検出",

    "numbers.heading": "数字で見る",
    "numbers.parityTitle": "デコーダ・パリティ",
    "numbers.parityValue": "214 / 214",
    "numbers.parityDesc":
      "jsQR自身の254枚コーパスで、jsQRとテキスト完全一致。jsQR自身も読めない40枚も正しく棄却。",
    "numbers.speedTitle": "デコーダ速度",
    "numbers.speedValue": "0.77x / 0.75x",
    "numbers.speedDesc":
      "640×480でのjsQR比フレーム時間 — QRあり／なし。数値が小さいほど高速。",
    "numbers.encodeTitle": "エンコーダ・パリティ",
    "numbers.encodeValue": "160 / 160",
    "numbers.encodeDesc":
      "qrcode npmパッケージと全バージョン×ECレベルの組み合わせでセル単位一致。",
    "numbers.bundleTitle": "バンドルサイズ",
    "numbers.bundleValue": "6.4KB / 約50KB",
    "numbers.bundleDesc":
      "gzip、エンコード専用サブパス／フルデコーダ。使う分だけimportできます。",
    "numbers.evidence": "bench/RESULT.mdを見る →",

    "moonbit.heading": "なぜMoonBitか",
    "moonbit.body1":
      "MoonBitはWasm・JS・ネイティブをターゲットにできるモダンな静的型付け言語です。ブラウザ向けにはjsとwasm-gcという2つのバックエンドがコンパイル可能なため、採用を決める前に、境界コストも含めて実際のデコード処理で両方を計測しました。",
    "moonbit.body2":
      "結果: jsバックエンドはwasm-gcより1.99倍高速（Node・Chromeの幾何平均）でした。wasm-gcにはUint8ArrayをFixedArray[Byte]へ一括転送する経路がまだ無く、ピクセルごとに1要素ずつJS↔wasm境界を越える必要があります。そのためこのプロジェクトはjsバックエンドを採用しています。",
    "moonbit.evidence": "詳しい計測方法 →",

    "story.heading": "実録: モニター越しのQRコード撮影",
    "story.body1":
      "モニターに表示したQRコードを撮影すると、写真には画面のサブピクセル格子が高周波ノイズとして写り込みます。素朴なブロック単位二値化はこれを「ほぼ50%のスペックル（黒白が細かく入り乱れた領域）」と誤認し、ファインダパターンを検出できません — jsQRも同じ写真で失敗するため、これは自前の二値化のバグではありません。",
    "story.body2":
      "単発の縮小はさらに悪化させます — 格子をフィルタする代わりにエイリアシングしてしまうためです。解決策は「小スケール優先のマルチスケールピラミッド」— 2x2ボックス平均（本物のローパスフィルタ）による段階的な縮小を、小さいスケールから順に試します。実際のモニター撮影写真では、これによりデコード時間が約5.4秒から約62ミリ秒に短縮されました。実際に効く小スケールへ、より大きいスケールを全部失敗させることなくすぐ到達できるためです。",
    "story.evidence": "詳しい記録を見る →",

    "install.heading": "インストール",
    "install.note":
      "@elchika-inc/moonqr と @elchika-inc/moonqr-scanner はまだnpmに公開されていません — 以下のコードは公開後に使えるAPIです。今すぐ試すにはリポジトリをcloneしてローカルビルドしてください。",
    "install.encodeTitle": "エンコード → SVG",
    "install.decodeTitle": "デコード → ImageDataから",
    "install.cameraTitle": "カメラ・ライブスキャン",

    "limitations.heading": "制限事項",
    "limitations.kanji":
      "漢字モードでのエンコードは非対応です — 日本語（および非ASCII文字）は常にバイトモードUTF-8としてエンコードされます。これは有効なQRコードですが、最小サイズにはなりません。他のエンコーダが生成した漢字モードQRコードのデコードは完全にサポートしています。",
    "limitations.segments":
      "混在モードのセグメント最適化は非対応です — 入力全体に単一モード（数字/英数字/バイト）を選択し、混在コンテンツをセグメントごとの最適モードに分割することはしません。",
    "limitations.eci":
      "ECI・構造的連接・マイクロQRは非対応です — 標準（モデル2）QRコード、デフォルトのバイトモード処理のみに対応しています。",

    "footer.github": "GitHub",
    "footer.npm": "npm",
    "footer.mooncakes": "mooncakes.io",
    "footer.license": "ライセンス",
    "footer.attribution":
      'デコーダの一部は<a href="https://github.com/cozmo/jsQR" target="_blank" rel="noopener">jsQR</a>（Apache-2.0）から移植。Reed–Solomonブロック/アライメントパターン位置テーブルは<a href="https://github.com/kazuhikoarase/qrcode-generator" target="_blank" rel="noopener">qrcode-generator</a>（MIT）由来です。',
    "footer.comingSoon": "（公開準備中）",
  },
};

let currentLang = translations[localStorage.getItem(STORAGE_KEY)]
  ? localStorage.getItem(STORAGE_KEY)
  : DEFAULT_LANG;

const listeners = new Set();

export function getLang() {
  return currentLang;
}

export function onLangChange(fn) {
  listeners.add(fn);
  return () => listeners.delete(fn);
}

export function t(key, vars) {
  const dict = translations[currentLang] || translations[DEFAULT_LANG];
  let str = dict[key] ?? translations[DEFAULT_LANG][key] ?? key;
  if (vars) {
    for (const [k, v] of Object.entries(vars)) {
      str = str.replaceAll(`{${k}}`, String(v));
    }
  }
  return str;
}

function applyStaticI18n() {
  document.querySelectorAll("[data-i18n]").forEach((el) => {
    el.textContent = t(el.getAttribute("data-i18n"));
  });
  // data-i18n-html: for the handful of strings that need inline markup (<code>/<a>).
  // The dictionary values for these keys are hand-written HTML with no interpolated user
  // data — never route t()-templated/user-supplied strings through this path.
  document.querySelectorAll("[data-i18n-html]").forEach((el) => {
    el.innerHTML = t(el.getAttribute("data-i18n-html"));
  });
  document.querySelectorAll("[data-i18n-attr]").forEach((el) => {
    for (const pair of el.getAttribute("data-i18n-attr").split(";")) {
      const [attr, key] = pair.split(":");
      if (attr && key) el.setAttribute(attr.trim(), t(key.trim()));
    }
  });
}

export function setLang(lang) {
  if (!translations[lang] || lang === currentLang) return;
  currentLang = lang;
  localStorage.setItem(STORAGE_KEY, lang);
  document.documentElement.lang = lang;
  applyStaticI18n();
  for (const fn of listeners) fn(lang);
}

export function initI18n() {
  document.documentElement.lang = currentLang;
  applyStaticI18n();
}
