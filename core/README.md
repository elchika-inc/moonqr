# naoto24kawa/moonqr

Pure QR code encoder/decoder written in [MoonBit](https://www.moonbitlang.com/) — no
JavaScript dependencies, no WASM runtime coupling. This is the MoonBit-native module
published to [mooncakes.io](https://mooncakes.io/); it is also the source compiled to
JS and shipped as the npm packages [`@elchika-inc/moonqr`](https://www.npmjs.com/package/@elchika-inc/moonqr)
and [`@elchika-inc/moonqr-scanner`](https://www.npmjs.com/package/@elchika-inc/moonqr-scanner) —
see the [repository README](https://github.com/elchika-inc/moonqr) for the JS/TS side
(if you're building a Node.js or browser app, you probably want the npm packages, not
this module directly).

## Packages

| Package | What it is |
|---|---|
| `naoto24kawa/moonqr/gf256` | GF(256) arithmetic + Reed–Solomon encode/decode, used by both encode and decode |
| `naoto24kawa/moonqr/encode` | Text → QR `Matrix` (module placement, masking, format/version info) + SVG rendering |
| `naoto24kawa/moonqr/decode` | RGBA pixels → decoded text (binarization, finder-pattern location, perspective extraction, codeword decode); ported from [jsQR](https://github.com/cozmo/jsQR) |

`preferred-target` is `js` — see the root README's "Why MoonBit" section for the
`js` vs `wasm-gc` benchmark that motivated this choice.

The `bench` package (a Phase-1 backend-selection spike, not part of the public API) is
excluded from the published artifact via `moon.mod.json`'s `exclude` field.

## Install

```sh
moon add naoto24kawa/moonqr
```

## Usage

### Encode

```moonbit
let matrix = @encode.encode("HELLO WORLD", @encode.EcLevel::M, None)
match matrix {
  Some(m) => {
    // m.size x m.size module grid; m.get(x, y) : Bool (true = dark module)
    let svg = @encode.to_svg_string(m, 4, 8) // margin=4 modules, cell=8px
    ...
  }
  None => ... // capacity exceeded, or an explicit `version` too small for the text
}
```

`encode(text, ec, version)` returns `Matrix?`: `None` for an empty string or when the
text doesn't fit the given/selected version. Pass `version=None` to auto-select the
smallest QR version (1–40) that fits; pass `Some(v)` to force one.

### Decode

```moonbit
// data: RGBA bytes, width * height * 4 long
let result = @decode.decode(data, width, height, true) // invert=true also tries the inverted binarization
match result {
  Some(r) => {
    // r.text : String, r.bytes : Array[Int], r.version : Int,
    // r.ec : @encode.EcLevel, r.corners : Array[Point] (TL, TR, BR, BL, in pixel space)
    ...
  }
  None => ... // no QR code found in the frame
}
```

## License and attribution

Apache License 2.0 — see [LICENSE](https://github.com/elchika-inc/moonqr/blob/main/LICENSE).

Portions of `decode` are ported from [jsQR](https://github.com/cozmo/jsQR) (Apache-2.0),
and the Reed–Solomon block / alignment-pattern position tables in `encode` are derived
from [qrcode-generator](https://github.com/kazuhikoarase/qrcode-generator) (MIT). See
[NOTICE](https://github.com/elchika-inc/moonqr/blob/main/NOTICE) and
[THIRD_PARTY_LICENSES](https://github.com/elchika-inc/moonqr/blob/main/THIRD_PARTY_LICENSES)
for the full attribution.
