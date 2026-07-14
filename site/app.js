// moonqr デモページのロジック。CDN不使用・importmap経由でビルド済みdistのみを読む
// （site/index.html の importmap と scripts/build-site.mjs 参照）。
import { encode, toSvgString } from "@elchika-inc/moonqr/encode";
import { QrScanner } from "@elchika-inc/moonqr-scanner";

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
    generateStatus.textContent = "テキストを入力してください";
    generateStatus.className = "note";
    downloadBtn.disabled = true;
    lastSvg = null;
    return;
  }

  const matrix = encode(text, { ecLevel, version });
  if (!matrix) {
    qrPreview.innerHTML = "";
    generateStatus.textContent = "生成できません（容量超過、またはバージョンとECレベルの組み合わせが不正）";
    generateStatus.className = "status-err";
    downloadBtn.disabled = true;
    lastSvg = null;
    return;
  }

  const svg = toSvgString(matrix, { margin: 4, cell: 4 });
  qrPreview.innerHTML = svg;
  generateStatus.textContent = `OK: ${matrix.size}x${matrix.size} モジュール / EC ${ecLevel}${version ? ` / v${version}` : "（自動選択）"}`;
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

async function handleFiles(files) {
  for (const file of files) {
    const card = await decodeImageFile(file);
    readResults.prepend(card);
  }
}

function escapeHtml(text) {
  const div = document.createElement("div");
  div.textContent = text;
  return div.innerHTML;
}

/**
 * File（Blob）をそのまま公開API `QrScanner.scanImage()` に渡して読み取る。
 * 戻り値の `ScanImageResult` は DecodeResult に加えて成功スケール（scale）と
 * 試行スケール列（attemptedScales）を含むため、内部APIを迂回せずに
 * 「どのスケールで読めたか」まで表示できる（このデモは公開APIのリファレンス実装）。
 */
async function decodeImageFile(file) {
  const card = document.createElement("div");
  card.className = "result-card";
  const thumbUrl = URL.createObjectURL(file);

  try {
    const result = await QrScanner.scanImage(file);

    let body;
    if (result) {
      const { scale, attemptedScales } = result;
      const attemptsNote = attemptedScales.map((s) => `1/${s}`).join(" → ");
      body = `
        <p class="status-ok">✓ 読取成功（${scale === 1 ? "等倍" : `1/${scale} スケール`}）</p>
        <dl>
          <dt>テキスト</dt><dd>${escapeHtml(result.text)}</dd>
          <dt>バージョン</dt><dd>${result.version}</dd>
          <dt>ECレベル</dt><dd>${result.ecLevel}</dd>
          <dt>試行スケール（小→大）</dt><dd>${attemptsNote}</dd>
        </dl>`;
    } else {
      body = `<p class="status-err">✗ 読取失敗（QRコードを検出できませんでした）</p>`;
    }
    card.innerHTML = `<img src="${thumbUrl}" alt="${escapeHtml(file.name)}"><div><strong>${escapeHtml(file.name)}</strong>${body}</div>`;
  } catch (err) {
    card.innerHTML = `<div><strong>${escapeHtml(file.name)}</strong><p class="status-err">✗ エラー: ${escapeHtml(err instanceof Error ? err.message : String(err))}</p></div>`;
  }

  return card;
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

function setCameraStatus(text, kind) {
  cameraStatus.textContent = text;
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

function onScanResult(result) {
  drawCorners(result.corners);
  cameraResult.innerHTML = `
    <div class="result-card" style="border:none; padding:0; margin-top:10px;">
      <div>
        <p class="status-ok">✓ 検出</p>
        <dl>
          <dt>テキスト</dt><dd>${escapeHtml(result.text)}</dd>
          <dt>バージョン</dt><dd>${result.version}</dd>
          <dt>ECレベル</dt><dd>${result.ecLevel}</dd>
        </dl>
      </div>
    </div>`;
}

cameraStartBtn.addEventListener("click", async () => {
  cameraStartBtn.disabled = true;
  setCameraStatus("カメラへのアクセスを要求しています…（ブラウザの許可ダイアログを確認してください）");

  const secure = typeof window !== "undefined" && window.isSecureContext;
  if (!secure) {
    setCameraStatus(
      "このページは Secure Context（HTTPS または localhost）ではないため、カメラを起動できません。",
      "err",
    );
    cameraStartBtn.disabled = false;
    return;
  }

  scanner = new QrScanner(cameraVideo, onScanResult, {
    preferredCamera: "environment",
    onError: (error) => {
      // 握りつぶさない: スキャナ稼働中に起きたエラー（Workerクラッシュ等）を surface する。
      setCameraStatus(`スキャナエラー: ${error.message}`, "err");
    },
  });

  try {
    await scanner.start();
    setCameraStatus("スキャン中… QRコードをカメラに向けてください。", "ok");
    cameraStopBtn.disabled = false;
  } catch (error) {
    // 権限拒否・デバイスなし・非対応環境などをクラッシュさせずグレースフルに表示する。
    const message = error instanceof Error ? error.message : String(error);
    setCameraStatus(`カメラを起動できませんでした: ${message}`, "err");
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
  setCameraStatus("停止しました。");
});

// 起動可否を事前に知らせる（実際の起動試行はボタン操作時に行う。エラー経路の実演を
// 妨げないよう、ボタン自体は無効化しない）。
QrScanner.hasCamera().then((available) => {
  if (!available) {
    setCameraStatus(
      "この環境では getUserMedia が利用できないか、Secure Context ではありません（HTTPS/localhost が必要です）。",
      "err",
    );
  } else {
    setCameraStatus("「カメラ開始」を押すとブラウザの許可ダイアログが表示されます。");
  }
});
