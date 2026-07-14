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

## サブパスエクスポート（バンドルサイズ）

**サイズが気になる場合は、ルート（`@elchika-inc/moonqr`）ではなくサブパスから import してください。**

| エントリ | 用途 | サイズ（ESM, minified） |
|---|---|---|
| `@elchika-inc/moonqr/encode` | エンコードのみ | raw 21.3 KB / gzip 6.4 KB |
| `@elchika-inc/moonqr/decode` | デコードのみ | （Task 4 で実装） |
| `@elchika-inc/moonqr` | 両方（DX 優先） | 上記の合算 |

デコーダは SJIS テーブルを含むため raw 261 KB / gzip 62 KB と大きく、**QR の生成しかしない利用者がこれをバンドルする必要はありません**。`encode` サブパスはデコーダと物理的に別ファイルなので、ダウンストリームのバンドラのツリーシェイキング品質に依存せず確実に除外されます。

ルートエントリ経由でも `sideEffects: false` を宣言しているためモダンなバンドラなら除去できますが、保証はできません。サイズが要件ならサブパスを使ってください。
