// moonqr ランディングページに埋め込まれたデモのロジック。CDN不使用・importmap経由で
// ビルド済みdistのみを読む（site/index.html の importmap と scripts/build-site.mjs 参照）。
// i18n（英語デフォルト・日本語切替）は ./i18n.js を参照。
import { encode, toSvgString } from "@elchika-inc/moonqr/encode";
import { QrScanner } from "@elchika-inc/moonqr-scanner";
import { t, getLang, setLang, onLangChange, initI18n } from "./i18n.js";

initI18n();

// ---------------------------------------------------------------------------
// 言語切替
// ---------------------------------------------------------------------------
const langToggleBtn = document.getElementById("lang-toggle");
langToggleBtn.addEventListener("click", () => {
  setLang(getLang() === "en" ? "ja" : "en");
});

// ---------------------------------------------------------------------------
// 1. 生成
// ---------------------------------------------------------------------------
const textInput = document.getElementById("text-input");
const ecSelect = document.getElementById("ec-select");
const versionSelect = document.getElementById("version-select");
const qrPreview = document.getElementById("qr-preview");
const generateStatus = document.getElementById("generate-status");
const downloadBtn = document.getElementById("download-svg-btn");

// バージョン選択肢（自動 + 1..40）を動的生成。
for (let v = 1; v <= 40; v++) {
  const opt = document.createElement("option");
  opt.value = String(v);
  opt.textContent = `${v}`;
  versionSelect.appendChild(opt);
}

let lastSvg = null;

function renderQr() {
  const text = textInput.value;
  const ecLevel = ecSelect.value;
  const versionRaw = versionSelect.value;
  const version = versionRaw === "auto" ? undefined : Number(versionRaw);

  if (text === "") {
    qrPreview.innerHTML = "";
    generateStatus.textContent = t("generate.enterText");
    generateStatus.className = "note";
    downloadBtn.disabled = true;
    lastSvg = null;
    return;
  }

  const matrix = encode(text, { ecLevel, version });
  if (!matrix) {
    qrPreview.innerHTML = "";
    generateStatus.textContent = t("generate.cannotGenerate");
    generateStatus.className = "status-err";
    downloadBtn.disabled = true;
    lastSvg = null;
    return;
  }

  const svg = toSvgString(matrix, { margin: 4, cell: 4 });
  qrPreview.innerHTML = svg;
  const versionNote = version
    ? t("generate.versionNote", { version })
    : t("generate.versionAutoNote");
  generateStatus.textContent = t("generate.statusOk", {
    size: matrix.size,
    ec: ecLevel,
    versionNote,
  });
  generateStatus.className = "status-ok";
  lastSvg = svg;
  downloadBtn.disabled = false;
}

textInput.addEventListener("input", renderQr);
ecSelect.addEventListener("change", renderQr);
versionSelect.addEventListener("change", renderQr);

downloadBtn.addEventListener("click", () => {
  if (!lastSvg) return;
  const blob = new Blob([lastSvg], { type: "image/svg+xml" });
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = "moonqr.svg";
  a.click();
  URL.revokeObjectURL(url);
});

renderQr();

// ---------------------------------------------------------------------------
// 2. 読取（画像ファイル）
// ---------------------------------------------------------------------------
const dropZone = document.getElementById("drop-zone");
const fileInput = document.getElementById("file-input");
const readResults = document.getElementById("read-results");

dropZone.addEventListener("click", () => fileInput.click());
dropZone.addEventListener("keydown", (e) => {
  if (e.key === "Enter" || e.key === " ") {
    e.preventDefault();
    fileInput.click();
  }
});
dropZone.addEventListener("dragover", (e) => {
  e.preventDefault();
  dropZone.classList.add("dragover");
});
dropZone.addEventListener("dragleave", () => dropZone.classList.remove("dragover"));
dropZone.addEventListener("drop", (e) => {
  e.preventDefault();
  dropZone.classList.remove("dragover");
  if (e.dataTransfer) handleFiles(e.dataTransfer.files);
});
fileInput.addEventListener("change", (e) => {
  handleFiles(e.target.files);
});

function escapeHtml(text) {
  const div = document.createElement("div");
  div.textContent = text;
  return div.innerHTML;
}

// 過去の読取結果を記述子として保持し、言語切替時に再レンダリングできるようにする
// （dt/dd のラベルや状態テキストは言語依存のため、生成時の言語に固定されないようにする）。
const readResultDescriptors = [];

/**
 * File（Blob）をそのまま公開API `QrScanner.scanImage()` に渡して読み取り、結果の記述子を
 * 返す。戻り値の `ScanImageResult` は DecodeResult に加えて成功スケール（scale）と
 * 試行スケール列（attemptedScales）を含むため、内部APIを迂回せずに
 * 「どのスケールで読めたか」まで表示できる（このデモは公開APIのリファレンス実装）。
 */
async function decodeImageFile(file) {
  const thumbUrl = URL.createObjectURL(file);
  const fileName = file.name;

  try {
    const result = await QrScanner.scanImage(file);
    if (result) {
      const { text, version, ecLevel, scale, attemptedScales } = result;
      return { kind: "ok", fileName, thumbUrl, text, version, ecLevel, scale, attemptedScales };
    }
    return { kind: "fail", fileName, thumbUrl };
  } catch (err) {
    return {
      kind: "error",
      fileName,
      thumbUrl,
      message: err instanceof Error ? err.message : String(err),
    };
  }
}

function buildResultCard(desc) {
  const card = document.createElement("div");
  card.className = "result-card";

  let body;
  if (desc.kind === "ok") {
    const scaleNote =
      desc.scale === 1 ? t("read.scaleNative") : t("read.scaleN", { scale: desc.scale });
    const attemptsNote = desc.attemptedScales.map((s) => `1/${s}`).join(" → ");
    body = `
      <p class="status-ok">${escapeHtml(t("read.success", { scaleNote }))}</p>
      <dl>
        <dt>${escapeHtml(t("read.text"))}</dt><dd>${escapeHtml(desc.text)}</dd>
        <dt>${escapeHtml(t("read.version"))}</dt><dd>${desc.version}</dd>
        <dt>${escapeHtml(t("read.ecLevel"))}</dt><dd>${desc.ecLevel}</dd>
        <dt>${escapeHtml(t("read.attempts"))}</dt><dd>${escapeHtml(attemptsNote)}</dd>
      </dl>`;
  } else if (desc.kind === "fail") {
    body = `<p class="status-err">${escapeHtml(t("read.fail"))}</p>`;
  } else {
    body = `<p class="status-err">${escapeHtml(t("read.error", { message: desc.message }))}</p>`;
  }
  card.innerHTML = `<img src="${desc.thumbUrl}" alt="${escapeHtml(desc.fileName)}"><div><strong>${escapeHtml(desc.fileName)}</strong>${body}</div>`;
  return card;
}

function renderReadResults() {
  readResults.innerHTML = "";
  for (const desc of readResultDescriptors) {
    readResults.appendChild(buildResultCard(desc));
  }
}

async function handleFiles(files) {
  for (const file of files) {
    const desc = await decodeImageFile(file);
    readResultDescriptors.unshift(desc);
    readResults.prepend(buildResultCard(desc));
  }
}

// ---------------------------------------------------------------------------
// 3. 読取（カメラ）
// ---------------------------------------------------------------------------
const cameraStartBtn = document.getElementById("camera-start-btn");
const cameraStopBtn = document.getElementById("camera-stop-btn");
const cameraStatus = document.getElementById("camera-status");
const cameraVideo = document.getElementById("camera-video");
const cameraOverlay = document.getElementById("camera-overlay");
const cameraResult = document.getElementById("camera-result");
const overlayCtx = cameraOverlay.getContext("2d");

let scanner = null;
// 現在の状態を保持し、言語切替時に同じ状態を新しい言語で再表示できるようにする。
let cameraStateKey = "camera.noCamera";
let cameraStateVars = null;
let cameraStateKind = "note";
let lastCameraResult = null;

function setCameraState(key, kind, vars) {
  cameraStateKey = key;
  cameraStateKind = kind;
  cameraStateVars = vars ?? null;
  cameraStatus.textContent = t(key, vars ?? undefined);
  cameraStatus.className = kind === "err" ? "status-err" : kind === "ok" ? "status-ok" : "note";
}

function clearOverlay() {
  overlayCtx.clearRect(0, 0, cameraOverlay.width, cameraOverlay.height);
}

function drawCorners(corners) {
  if (
    cameraOverlay.width !== cameraVideo.videoWidth ||
    cameraOverlay.height !== cameraVideo.videoHeight
  ) {
    cameraOverlay.width = cameraVideo.videoWidth;
    cameraOverlay.height = cameraVideo.videoHeight;
  }
  clearOverlay();
  overlayCtx.strokeStyle = "#3ddc84";
  overlayCtx.lineWidth = Math.max(2, cameraOverlay.width / 200);
  overlayCtx.beginPath();
  corners.forEach((p, i) => {
    if (i === 0) overlayCtx.moveTo(p.x, p.y);
    else overlayCtx.lineTo(p.x, p.y);
  });
  overlayCtx.closePath();
  overlayCtx.stroke();
}

function renderCameraResult() {
  if (!lastCameraResult) {
    cameraResult.innerHTML = "";
    return;
  }
  const { text, version, ecLevel } = lastCameraResult;
  cameraResult.innerHTML = `
    <div class="result-card" style="border:none; padding:0; margin-top:10px;">
      <div>
        <p class="status-ok">${escapeHtml(t("camera.detected"))}</p>
        <dl>
          <dt>${escapeHtml(t("read.text"))}</dt><dd>${escapeHtml(text)}</dd>
          <dt>${escapeHtml(t("read.version"))}</dt><dd>${version}</dd>
          <dt>${escapeHtml(t("read.ecLevel"))}</dt><dd>${ecLevel}</dd>
        </dl>
      </div>
    </div>`;
}

function onScanResult(result) {
  drawCorners(result.corners);
  lastCameraResult = result;
  renderCameraResult();
}

cameraStartBtn.addEventListener("click", async () => {
  cameraStartBtn.disabled = true;
  setCameraState("camera.requesting", "note");

  const secure = typeof window !== "undefined" && window.isSecureContext;
  if (!secure) {
    setCameraState("camera.insecure", "err");
    cameraStartBtn.disabled = false;
    return;
  }

  scanner = new QrScanner(cameraVideo, onScanResult, {
    preferredCamera: "environment",
    onError: (error) => {
      // 握りつぶさない: スキャナ稼働中に起きたエラー（Workerクラッシュ等）を surface する。
      setCameraState("camera.scannerError", "err", { message: error.message });
    },
  });

  try {
    await scanner.start();
    setCameraState("camera.scanning", "ok");
    cameraStopBtn.disabled = false;
  } catch (error) {
    // 権限拒否・デバイスなし・非対応環境などをクラッシュさせずグレースフルに表示する。
    const message = error instanceof Error ? error.message : String(error);
    setCameraState("camera.startFailed", "err", { message });
    cameraStartBtn.disabled = false;
    scanner = null;
  }
});

cameraStopBtn.addEventListener("click", () => {
  scanner?.stop();
  scanner = null;
  clearOverlay();
  cameraStopBtn.disabled = true;
  cameraStartBtn.disabled = false;
  setCameraState("camera.stopped", "note");
});

// 起動可否を事前に知らせる（実際の起動試行はボタン操作時に行う。エラー経路の実演を
// 妨げないよう、ボタン自体は無効化しない）。
QrScanner.hasCamera().then((available) => {
  if (!available) {
    setCameraState("camera.noCamera", "err");
  } else {
    setCameraState("camera.readyPrompt", "note");
  }
});

// ---------------------------------------------------------------------------
// 言語切替時の動的テキスト再レンダリング
// ---------------------------------------------------------------------------
onLangChange(() => {
  renderQr();
  renderReadResults();
  cameraStatus.textContent = t(cameraStateKey, cameraStateVars ?? undefined);
  cameraStatus.className =
    cameraStateKind === "err" ? "status-err" : cameraStateKind === "ok" ? "status-ok" : "note";
  renderCameraResult();
});
