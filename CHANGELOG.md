# Changelog

Notable changes to the published packages. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the packages follow
[semantic versioning](https://semver.org/spec/v2.0.0.html).

The three npm packages are versioned separately, so each entry names the package it applies to.
`@elchika-inc/moonqr` and `@elchika-inc/moonqr-scanner` share a version number with the MoonBit
module (`core/moon.mod.json`); `@elchika-inc/moonqr-cli` is versioned independently.

Entries here summarise what changed for someone consuming the packages. The full reasoning,
measurements and migration notes live in the linked GitHub Release — that page is the source of
truth for the details, and this file is the index.

## [Unreleased]

### Fixed

- **decode**: small images no longer panic. Neighbour indices in the adaptive binarizer are now
  clamped to the block grid; MoonBit's `FixedArray` panics on an out-of-range read where jsQR's
  `TypedArray` returns `undefined`, and the port had inherited the assumption ([#23]).
- **decode**: mode indicators that the decoder does not implement are rejected instead of being
  read as data ([#23]).
- **encode**: invalid explicit version numbers are rejected instead of producing a malformed
  symbol ([#23]).
- **scanner**: worker crash recovery is bounded, so a repeatedly failing worker no longer restarts
  without limit. Errors thrown by a consumer's callback are preserved rather than swallowed ([#23]).
- Public API contracts were tightened where review found them under-specified ([#26]).

### Changed

- **encode**: `optimal_segments` runs in O(n) instead of O(n²). Long alternating inputs that
  previously took seconds now complete in well under a second; the chosen segmentation is
  unchanged ([#22]).

## [@elchika-inc/moonqr-cli 0.1.0] — 2026-09-02

First release of the command-line tool: prints a QR code to the terminal using half-block
characters, so a URL in your shell can be picked up by a phone camera instead of retyped.
Options: `-e, --ec <L|M|Q|H>`, `--no-color` (also honours `NO_COLOR`), `-h`, `-v`.

Versioned independently of the core; the published package depends on `@elchika-inc/moonqr ^0.2.0`.

→ [Release notes](https://github.com/elchika-inc/moonqr/releases/tag/cli-v0.1.0)

## [0.2.0] — 2026-07-29

Mixed input is now split into per-segment optimal modes, so the same content fits into a smaller
symbol — `https://ex.com/id/` followed by a 100-digit ID drops from version 7 to version 4 at
EC M. Measured against the `qrcode` npm package across 11 inputs × 4 EC levels: never larger.

No API change, and decoded text is unchanged — only the symbol size can differ.

→ [Release notes](https://github.com/elchika-inc/moonqr/releases/tag/v0.2.0)

## [0.1.0] — 2026-07-28

First public release. A QR encoder and decoder written in MoonBit and compiled to plain
JavaScript — no WASM, no native addons, no runtime dependencies. Ships as `@elchika-inc/moonqr`
(encode / decode / DOM rendering, with subpath exports), `@elchika-inc/moonqr-scanner` (live
camera scanning in a Web Worker), and the MoonBit module `naoto24kawa/moonqr`.

→ [Release notes](https://github.com/elchika-inc/moonqr/releases/tag/v0.1.0)

[#22]: https://github.com/elchika-inc/moonqr/pull/22
[#23]: https://github.com/elchika-inc/moonqr/pull/23
[#26]: https://github.com/elchika-inc/moonqr/pull/26
[Unreleased]: https://github.com/elchika-inc/moonqr/compare/v0.2.0...HEAD
[@elchika-inc/moonqr-cli 0.1.0]: https://github.com/elchika-inc/moonqr/releases/tag/cli-v0.1.0
[0.2.0]: https://github.com/elchika-inc/moonqr/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/elchika-inc/moonqr/releases/tag/v0.1.0
