# moonqr

[![CI](https://img.shields.io/github/actions/workflow/status/elchika-inc/moonqr/ci.yml?branch=main&label=CI)](https://github.com/elchika-inc/moonqr/actions/workflows/ci.yml)
[![License](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](LICENSE)

QR code encoder and decoder written in [MoonBit](https://www.moonbitlang.com/), compiled to
plain JavaScript, and shipped as zero-dependency npm packages that run in Node.js and the
browser (no WASM, no native addons).

- **`@elchika-inc/moonqr`** — encode / decode core, plus DOM canvas rendering.
- **`@elchika-inc/moonqr-scanner`** — a live camera scanner (`QrScanner`) built on top of it,
  with the decode loop offloaded to a Web Worker.

## Live demo

**<https://elchika-inc.github.io/moonqr/>** — encode text into a QR code, decode an uploaded
image, or scan with your camera. Everything runs client-side: no server, no external requests.
The page is the `site/` app, built and deployed by
[`.github/workflows/pages.yml`](.github/workflows/pages.yml).

## Why MoonBit

The QR encode/decode algorithms (bit-level codeword packing, Reed–Solomon, binarization, finder
pattern location, perspective extraction, mask scoring, …) live in `core/` as MoonBit source and
compile to JavaScript via `moon build --target js`. MoonBit supports two relevant compile targets
for browser/Node use — `js` and `wasm-gc` — and we benchmarked both before committing to one
(see [`bench/RESULT.md`](bench/RESULT.md)): `wasm-gc` has no bulk-transfer path for `Uint8Array`
into `FixedArray[Byte]` yet, so every pixel of a decoded frame crosses the JS↔wasm boundary one
element at a time. Measured on Node and Chrome, that per-element marshalling made `wasm-gc`
1.5–2.6x **slower** than the `js` target for this workload, so `js` is the backend this project
ships (`core/moon.mod.json` → `preferred-target: "js"`). The generated JS is bundled straight into
the npm packages via [tsup](https://tsup.egoist.dev/) — there is no separate WASM artifact to
fetch or instantiate.

## Headline numbers

- **Decoder correctness**: full parity with [jsQR](https://github.com/cozmo/jsQR) on its own
  end-to-end test corpus — **214/214** ground-truth cases decoded to the exact expected text
  (jsQR itself also gets 214/214; the 40 remaining corpus cases have no ground truth because jsQR
  can't read them either, and neither implementation reports a false positive on them).
- **Decoder speed**: faster than jsQR (npm `jsqr@1.4.0`) on both a QR-bearing frame and a
  no-QR frame, measured with the same harness on Node.js — **0.77x** of jsQR's median time on a
  hit, **0.75x** on a miss (lower is faster; see [`bench/RESULT.md`](bench/RESULT.md) for the full
  methodology, including inversion-attempt settings and anti-JIT-elision measures).
- **Encoder correctness**: bit-for-bit module matrix match against the
  [`qrcode`](https://www.npmjs.com/package/qrcode) npm package across all **160** version×EC-level
  combinations (versions 1–40 × levels L/M/Q/H), with the reference regenerated at our chosen mask
  pattern to make the comparison exact rather than mask-dependent.
- **Encoder compaction**: mixed input is split into per-segment optimal modes, so a URL with a long
  numeric ID encodes into a smaller symbol than a single-mode encoder would produce (measured:
  **v7 → v4** for a 100-digit ID, matching or beating the `qrcode` npm package on every case tested).

Full measurement methodology, environment details, and additional gates (real-camera photos,
monitor-glare multiscale retry, etc.) are in [`bench/RESULT.md`](bench/RESULT.md).

## Packages

| Package | What it is | Docs |
|---|---|---|
| [`@elchika-inc/moonqr`](packages/moonqr) | Encode/decode core + DOM canvas rendering. Subpath exports (`/encode`, `/decode`, `/dom`) so you only bundle what you use. | [README](packages/moonqr/README.md) |
| [`@elchika-inc/moonqr-scanner`](packages/scanner) | Camera-based live QR scanner (`QrScanner` class), decode loop runs in a Web Worker off the main thread. | [README](packages/scanner/README.md) |

```sh
npm install @elchika-inc/moonqr @elchika-inc/moonqr-scanner
```

Both packages are pure ESM+CJS (moonqr) / ESM (scanner), have no runtime dependencies outside
each other (`moonqr-scanner` depends on `moonqr`), and declare `sideEffects: false` for clean
tree-shaking.

### Using it from MoonBit

The `core/` module is published to [mooncakes.io](https://mooncakes.io/docs/naoto24kawa/moonqr)
as `naoto24kawa/moonqr`, so MoonBit projects can depend on the encoder/decoder directly instead
of going through the JS packages:

```sh
moon add naoto24kawa/moonqr
```

```moonbit
// in moon.pkg: import { "naoto24kawa/moonqr/encode" }
let matrix = @encode.encode("HELLO", @encode.EcLevel::M, None)
```

## Development

Requires the MoonBit toolchain (for `core/`) and Node.js 18.18+ / pnpm 10.

```sh
# MoonBit toolchain
curl -fsSL https://cli.moonbitlang.com/install/unix.sh | bash
export PATH="$HOME/.moon/bin:$PATH"

# JS/TS workspace
pnpm install --frozen-lockfile
```

Build and test everything:

```sh
# MoonBit core
cd core && moon test --target js && moon build --target js --release && cd ..

# TS packages (build first — tsup inlines core's JS output)
pnpm -r build
pnpm -r typecheck

# Node test suite (needs the jsQR parity fixtures, fetched once and cached)
node scripts/fetch-fixtures.mjs
node --test packages/moonqr/test/*.test.mjs

# Vitest suites
pnpm -r test:unit
```

`.github/workflows/ci.yml` runs the same sequence on every push/PR.

## Repository layout

```
core/                MoonBit source (encode/decode algorithms) -> compiles to JS
packages/moonqr/      npm package: encode/decode/dom TS wrappers around core's JS output
packages/scanner/     npm package: camera QrScanner built on packages/moonqr
bench/                Benchmark harness + bench/RESULT.md (methodology + all results)
site/                 GitHub Pages demo (built by scripts/build-site.mjs)
scripts/               repo-level dev scripts (fixtures, site build, table generation, ...)
```

## Limitations

- **Kanji-mode encoding is not supported.** The encoder always emits Japanese (and other
  non-ASCII) text as byte-mode UTF-8, never as ISO 18004 Kanji mode — this produces a valid but
  slightly larger QR code than a Kanji-mode-aware encoder would. **Decoding** Kanji-mode QR
  codes produced by other encoders **is** fully supported.
- **No ECI, Structured Append, or Micro QR support** on either encode or decode. Only standard
  (Model 2) QR codes with the default byte-mode ECI (implicit ISO-8859-1/UTF-8-ish handling
  matching common encoders, per Kanji-mode decode above) are handled.

## License and attribution

Apache License 2.0 — see [LICENSE](LICENSE).

Portions of the decoder are ported from [jsQR](https://github.com/cozmo/jsQR) (Apache-2.0), and
the Reed–Solomon block / alignment-pattern position tables are derived from
[qrcode-generator](https://github.com/kazuhikoarase/qrcode-generator) (MIT). See
[NOTICE](NOTICE) for the attribution summary and
[THIRD_PARTY_LICENSES](THIRD_PARTY_LICENSES) for the full upstream license texts. Both npm
packages include copies of `LICENSE`, `NOTICE`, and `THIRD_PARTY_LICENSES` in their published
tarballs.
