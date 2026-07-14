# @elchika-inc/moonqr

QR code encoder and decoder written in [MoonBit](https://www.moonbitlang.com/). No runtime dependencies, works in the browser.

> このドキュメントは暫定版です（Task 8 で拡張予定）。

## Install

```sh
npm install @elchika-inc/moonqr
```

## Usage

```ts
import { encode, toSvgString } from "@elchika-inc/moonqr/encode";

const matrix = encode("HELLO", { ecLevel: "M" });
if (matrix) {
  console.log(matrix.size); // 21 (v1)
  console.log(matrix.get(0, 0)); // true（左上ファインダ）
  const svg = toSvgString(matrix, { margin: 4, cell: 8 });
}
```

`encode()` は容量超過・空文字・不正オプション（`version` が 1..40 外、`ecLevel` が `L`/`M`/`Q`/`H` 以外）で `null` を返します（例外を投げません）。

```ts
import { decode } from "@elchika-inc/moonqr/decode";

// data は RGBA ピクセル配列（ImageData.data 相当、Uint8Array/Uint8ClampedArray どちらも可）
const result = decode(imageData.data, imageData.width, imageData.height);
if (result) {
  console.log(result.text, result.version, result.ecLevel, result.corners);
}
```

`decode()` は見つからない場合・不正入力（`data.length !== width*height*4` 等）で `null` を返します。`options.invert`（既定 `true`）で反転配色QRも自動で試すかを制御できます。

```ts
import { toCanvas } from "@elchika-inc/moonqr/dom";
import { encode } from "@elchika-inc/moonqr/encode";

const matrix = encode("HELLO")!;
toCanvas(matrix, document.querySelector("canvas")!, { margin: 4, cell: 8 });
```

## サブパスエクスポート（バンドルサイズ）

**サイズが気になる場合は、ルート（`@elchika-inc/moonqr`）ではなくサブパスから import してください。**

| エントリ | 用途 | サイズ（ESM, minified） |
|---|---|---|
| `@elchika-inc/moonqr/encode` | エンコードのみ | raw 21.3 KB / gzip 6.4 KB |
| `@elchika-inc/moonqr/decode` | デコードのみ | raw 129.4 KB / gzip 49.8 KB |
| `@elchika-inc/moonqr/dom` | `toCanvas`（DOM描画） | raw 0.3 KB / gzip 0.2 KB（MoonBit非依存） |
| `@elchika-inc/moonqr` | 全部（DX 優先） | raw 150.7 KB / gzip 55.9 KB |

デコーダは SJIS テーブルを含むため raw 261 KB / gzip 62 KB と大きく、**QR の生成しかしない利用者がこれをバンドルする必要はありません**。`encode` サブパスはデコーダと物理的に別ファイルなので、ダウンストリームのバンドラのツリーシェイキング品質に依存せず確実に除外されます。

ルートエントリ経由でも `sideEffects: false` を宣言しているためモダンなバンドラなら除去できますが、保証はできません。サイズが要件ならサブパスを使ってください。
