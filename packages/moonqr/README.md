# @elchika-inc/moonqr

QR code encoder and decoder written in [MoonBit](https://www.moonbitlang.com/), compiled to
plain JavaScript. No runtime dependencies. Works in Node.js and the browser.

- `encode` / `toSvgString` — text → QR matrix → SVG string.
- `decode` — RGBA pixels → QR text (locates, extracts, corrects, and decodes; handles rotation,
  inverted color schemes, and photographed QR codes).
- `toCanvas` — draw a QR matrix onto an `HTMLCanvas​Element`.

For a live camera scanner built on top of this package, see
[`@elchika-inc/moonqr-scanner`](../scanner).

## Install

```sh
npm install @elchika-inc/moonqr
```

## Usage

### Encode

```ts
import { encode, toSvgString } from "@elchika-inc/moonqr/encode";

const matrix = encode("HELLO", { ecLevel: "M" });
if (matrix) {
  console.log(matrix.size); // 21 (v1)
  console.log(matrix.get(0, 0)); // true (top-left finder pattern)
  const svg = toSvgString(matrix, { margin: 4, cell: 8 });
}
```

`encode()` returns `null` on capacity overflow, empty input, or invalid options (`version`
outside 1..40, `ecLevel` not one of `L`/`M`/`Q`/`H`) — it never throws.

### Decode

```ts
import { decode } from "@elchika-inc/moonqr/decode";

// data is an RGBA pixel buffer (same shape as ImageData.data — Uint8Array or
// Uint8ClampedArray both work)
const result = decode(imageData.data, imageData.width, imageData.height);
if (result) {
  console.log(result.text, result.version, result.ecLevel, result.corners);
}
```

`decode()` returns `null` when no QR code is found or the input is invalid (e.g.
`data.length !== width * height * 4`) — it never throws. `options.invert` (default `true`)
controls whether an inverted-color QR code is also attempted automatically.

### Render to canvas

```ts
import { toCanvas } from "@elchika-inc/moonqr/dom";
import { encode } from "@elchika-inc/moonqr/encode";

const matrix = encode("HELLO")!;
toCanvas(matrix, document.querySelector("canvas")!, { margin: 4, cell: 8 });
```

## Subpath exports (bundle size)

**If bundle size matters, import from a subpath instead of the package root
(`@elchika-inc/moonqr`).**

| Entry | Purpose | Size (CJS, minified) |
|---|---|---|
| `@elchika-inc/moonqr/encode` | Encode only | raw 21.3 KB / gzip 6.4 KB |
| `@elchika-inc/moonqr/decode` | Decode only | raw 129.5 KB / gzip 49.8 KB |
| `@elchika-inc/moonqr/dom` | `toCanvas` (canvas rendering) | raw 0.3 KB / gzip 0.2 KB (no MoonBit dependency) |
| `@elchika-inc/moonqr` | Everything (convenience) | raw 150.9 KB / gzip 56.7 KB |

(Sizes are reproduced by `node scripts/report-bundle-sizes.mjs` at the repo root after
`pnpm -r build`, and checked in CI on every push.)

The decoder is large (its Shift-JIS table alone accounts for a good chunk of it) and
**encode-only consumers should not have to bundle it.** The `encode` subpath is a physically
separate output file from `decode`, so it's excluded regardless of how good (or not) your
downstream bundler's tree-shaking is.

The root entry also declares `sideEffects: false`, so a modern bundler *can* drop the unused
half even when importing from the root — but that's not guaranteed. If size is a requirement,
use the subpaths.

## API reference

### `encode(text: string, options?: EncodeOptions): QrMatrix | null`

```ts
interface EncodeOptions {
  ecLevel?: "L" | "M" | "Q" | "H"; // error correction level, default "M"
  version?: number;                // 1..40; omit to auto-pick the smallest that fits
}

interface QrMatrix {
  readonly size: number;
  get(x: number, y: number): boolean; // true = dark module. Out-of-range -> false, never throws.
}
```

### `toSvgString(matrix: QrMatrix, options?: SvgOptions): string`

```ts
interface SvgOptions {
  margin?: number; // quiet-zone width in modules, default 4
  cell?: number;    // module side length in px, default 4
}
```

Pure function, no DOM dependency — works in Node.js too.

### `decode(data: Uint8Array | Uint8ClampedArray, width: number, height: number, options?: DecodeOptions): DecodeResult | null`

```ts
interface DecodeOptions {
  invert?: boolean; // also try inverted color scheme, default true
}

interface DecodeResult {
  text: string;
  bytes: Uint8Array;                              // raw payload bytes (for binary payloads)
  version: number;
  ecLevel: "L" | "M" | "Q" | "H";
  corners: [Point, Point, Point, Point];          // source-image px, TL/TR/BR/BL order
}

interface Point { x: number; y: number; }
```

### `toCanvas(matrix: QrMatrix, canvas: HTMLCanvasElement, options?: SvgOptions): void`

(`@elchika-inc/moonqr/dom` only.) Sets `canvas.width`/`canvas.height` to fit the matrix and
draws it (white background, black modules), using the same margin/cell conventions as
`toSvgString`.

## Correctness

- Decoder: **214/214** exact-text match against jsQR's own end-to-end test corpus (jsQR itself
  also gets 214/214 on the cases that have ground truth).
- Encoder: bit-for-bit module match against the [`qrcode`](https://www.npmjs.com/package/qrcode)
  npm package across all 160 version (1–40) × error-correction-level (L/M/Q/H) combinations.

See [`bench/RESULT.md`](../../bench/RESULT.md) in the repo root for full methodology and
performance numbers (decoding is faster than jsQR on both hit and miss frames).

## Browser support

Ships as plain ESM + CJS with no bundler-specific syntax; targets ES2020. Works in any
evergreen browser and in Node.js 18.18+. `toCanvas` (the `/dom` subpath) requires
`HTMLCanvasElement` and its 2D context, i.e. a browser or a canvas-polyfilled environment — the
`encode` and `decode` subpaths themselves have no DOM dependency and run fine in Node.js
(see the parity/sweep tests under `test/` for examples of decoding from a Node-side pixel
buffer).

## License and attribution

Apache License 2.0 — see [LICENSE](LICENSE) (bundled in this package's published tarball).

Portions of the decoder are ported from [jsQR](https://github.com/cozmo/jsQR) (Apache-2.0), and
the Reed–Solomon block / alignment-pattern position tables are derived from
[qrcode-generator](https://github.com/kazuhikoarase/qrcode-generator) (MIT). See
[NOTICE](NOTICE) and [THIRD_PARTY_LICENSES](THIRD_PARTY_LICENSES) (also bundled) for the full
attribution and upstream license texts.
