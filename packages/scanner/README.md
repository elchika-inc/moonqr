# @elchika-inc/moonqr-scanner

Live camera QR scanner built on [`@elchika-inc/moonqr`](../moonqr). Decoding runs in a Web
Worker off the main thread (frame buffers are transferred, not copied), with a transparent
same-thread fallback for environments without Worker/OffscreenCanvas support.

## Install

```sh
npm install @elchika-inc/moonqr-scanner
```

`@elchika-inc/moonqr` is a regular dependency (installed automatically) — you don't need to add
it yourself unless you also want its `encode`/`decode`/`dom` subpaths directly.

## HTTPS requirement

`QrScanner` uses `navigator.mediaDevices.getUserMedia`, which browsers only expose in a
[secure context](https://developer.mozilla.org/en-US/docs/Web/Security/Secure_Contexts) — i.e.
HTTPS, or `http://localhost` during development. `QrScanner.hasCamera()` (below) checks this for
you and returns `false` on an insecure origin instead of letting `getUserMedia` throw.

## Usage

### Live camera scanning

```ts
import { QrScanner } from "@elchika-inc/moonqr-scanner";

const video = document.querySelector("video")!;

const scanner = new QrScanner(
  video,
  (result) => {
    console.log("scanned:", result.text, result.version, result.ecLevel);
  },
  {
    preferredCamera: "environment", // "environment" (back camera, default) | "user"
    onError: (error) => console.error(error),
  },
);

await scanner.start(); // requests camera permission, starts the video + decode loop
// ...
scanner.stop(); // releases the camera stream and worker (idempotent, safe to call anytime)
```

`start()` rejects if `getUserMedia` fails (permission denied, no camera, etc.) — it never fails
silently. `stop()` is idempotent and safe to call multiple times or before `start()` resolves.

### One-shot image scanning

```ts
import { QrScanner } from "@elchika-inc/moonqr-scanner";

// source: HTMLImageElement | HTMLCanvasElement | ImageBitmap | Blob
const result = await QrScanner.scanImage(fileInput.files[0]);
if (result) {
  console.log(result.text);
  console.log(`decoded at 1/${result.scale} scale`); // 1 = native resolution
  console.log("scales tried (small -> large):", result.attemptedScales);
}
```

`scanImage()` runs a **multiscale retry**: it doesn't just try the image at native resolution.
Photos of a QR code shown on a monitor pick up the screen's sub-pixel grid as high-frequency
noise that defeats naive binarization — a single-step resize makes this *worse* (aliasing), so
`scanImage()` builds a box-averaged (2x2 mean, a real low-pass filter) downscale pyramid and
tries the smallest images first, escalating to the full-resolution image only as a last resort.
The returned `scale` (e.g. `8` for a 1/8-scale success) and `attemptedScales` tell you which
level actually worked, so you're not left guessing why a "successful" scan took longer than
expected. In local benchmarks this small-to-large search order cut a real monitor-photo decode
from ~5.4s (large-first) to ~60ms (small-first) — see [`bench/RESULT.md`](../../bench/RESULT.md)
for the full writeup.

The live-camera path (`QrScanner.start()`) does *not* run the full pyramid every frame — that
would tank the frame rate. It scans at native capture resolution on the fast path, and only
escalates to a multiscale retry after enough consecutive frames have failed (see
`DEFAULT_ESCALATE_AFTER_FAILURES` in `src/index.ts`), resetting immediately after one attempt so
it doesn't camp on the slow path.

## Options

`new QrScanner(video, onResult, options?)`:

| Option | Type | Default | Description |
|---|---|---|---|
| `preferredCamera` | `"environment" \| "user"` | `"environment"` | Back or front camera. |
| `maxScansPerSecond` | `number` | `25` | Throttles the decode loop. |
| `invert` | `boolean` | `true` | Also try an inverted-color QR (black/white swapped). |
| `onError` | `(error: Error) => void` | logs to `console.error` | Camera disconnects, worker crashes, etc. Never silently swallowed — the default still surfaces to the console rather than dropping the error. |

## API reference

- `new QrScanner(video: HTMLVideoElement, onResult: (result: DecodeResult) => void, options?: QrScannerOptions)`
- `scanner.start(): Promise<void>` — requests camera access and starts scanning. Rejects on
  failure.
- `scanner.stop(): void` — releases the camera stream and worker. Idempotent.
- `QrScanner.scanImage(source: HTMLImageElement | HTMLCanvasElement | ImageBitmap | Blob): Promise<ScanImageResult | null>` — one-shot decode of a still image with multiscale retry.
- `QrScanner.hasCamera(): Promise<boolean>` — checks `getUserMedia` availability and secure-context status.

`DecodeResult` (`text`, `bytes`, `version`, `ecLevel`, `corners`) and `ScanImageResult`
(`DecodeResult` + `scale` + `attemptedScales`) are re-exported — see
[`@elchika-inc/moonqr`'s README](../moonqr/README.md#api-reference) for the shared type shapes.

## Browser support

Requires `getUserMedia` (camera access), `Worker`, and ideally `OffscreenCanvas` for
off-main-thread decoding — evergreen desktop and mobile browsers all support these. Where
`Worker`/`OffscreenCanvas` aren't available, decoding transparently falls back to the main
thread instead of failing. `scanImage()` only needs `Blob`/`ImageBitmap`/canvas support (no
camera), so it also works in Node.js test environments with a DOM shim.

## License and attribution

Apache License 2.0 — see [LICENSE](../../LICENSE) (also bundled in this package's published
tarball).

This package's own logic (camera capture, worker orchestration, multiscale retry) is original.
It depends on [`@elchika-inc/moonqr`](../moonqr), whose decoder is partly ported from
[jsQR](https://github.com/cozmo/jsQR) (Apache-2.0) — see [NOTICE](../../NOTICE) and
[THIRD_PARTY_LICENSES](../../THIRD_PARTY_LICENSES) (also bundled) for the full attribution.
