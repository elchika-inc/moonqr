# @elchika-inc/moonqr-cli

Print a QR code to your terminal.

Useful when something in your terminal produces a URL — a dev server address, a preview
deployment, a pull request, an agent handing you a link — and you want it on your phone. Point a
camera at the screen instead of retyping it.

```sh
npx @elchika-inc/moonqr-cli "https://example.com"
```

Or install it:

```sh
npm install -g @elchika-inc/moonqr-cli
moonqr "https://example.com"
```

## Options

| Option | Default | |
|---|---|---|
| `-e, --ec <L\|M\|Q\|H>` | `M` | Error correction level |
| `--no-color` | | Do not emit ANSI colors |
| `-h, --help` | | Show usage |
| `-v, --version` | | Show the version |

`NO_COLOR` is honoured as well.

## Why the output is always colored

Most CLI tools drop color when their output is not a terminal. This one does not, because the
output here is not text to be read — it is an image to be photographed.

A QR code needs a light background and dark modules. If the colors are left to the terminal theme,
a dark theme inverts them and readability becomes a matter of luck. So the background is declared
explicitly, always. Use `--no-color` or `NO_COLOR` if you want the raw block characters.

## How it fits on screen

Terminal cells are roughly twice as tall as they are wide, so drawing one module per cell would
stretch the code vertically past the point of being readable. Two module rows are packed into each
cell using half-block characters instead.

Measured output sizes:

| Input | Rows × columns |
|---|---|
| `http://192.168.1.10:3000` | 17 × 33 |
| `https://github.com/elchika-inc/moonqr/pull/17` | 21 × 41 |
| A 76-character deploy-preview URL | 23 × 45 |

An 80×24 terminal fits all of these. Longer payloads keep growing — the code is `modules + 8`
columns wide and `ceil((modules + 8) / 2)` rows tall, where `modules` is 21 for the smallest QR
version and 177 for the largest. Text long enough to need a high version will not fit on screen;
that is a limitation of the medium rather than something this tool can work around.

## Development

This package is part of the [moonqr](https://github.com/elchika-inc/moonqr) monorepo. The `bin`
entry loads from `dist/`, so build before running from a clone:

```sh
pnpm install
cd core && moon build --target js --release && cd ..   # the MoonBit core comes first
pnpm -r build
node packages/cli/bin/moonqr.js "https://example.com"
```

Rendering is verified mechanically: tests parse the rendered string back into a module matrix,
rasterize it, and run it through the decoder, so a one-module offset fails CI rather than reaching
a camera.

## License

Apache-2.0. See [LICENSE](LICENSE), [NOTICE](NOTICE), and
[THIRD_PARTY_LICENSES](THIRD_PARTY_LICENSES).
