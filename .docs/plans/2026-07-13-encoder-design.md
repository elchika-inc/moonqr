# moonqr 設計ドキュメント

- 日付: 2026-07-13
- ステータス: 承認済み（ブレインストーミング完了）
- 作成者: nishikawa + Claude

## 概要

MoonBit 製のQRコード生成・読取ライブラリ。フロントエンド（ブラウザ）のみで完結する。
純粋関数の core パッケージ `moonqr` と、カメラ統合の `@moonqr/scanner` の2パッケージ構成で、npm と mooncakes.io の両方に配布する。

## 背景・ポジショニング（調査結果 2026-07）

- 生成側は `qrcode`（週1700万DL）が支配的で参入余地なし。ただし読取と対で持つ意味はある。
- 読取側の「軽量・純粋」枠は空席: jsQR は 2021年から開発停止（dormant 公認）、派生の qr-scanner も 2022年で停止。アクティブな代替は zxing-wasm（C++移植・大型）と barcode-detector ponyfill のみ。
- `BarcodeDetector` API は Safari/Firefox 未対応・Baseline 外。ネイティブAPIでは代替できない。
- MoonBit 側に読取実装は存在しない（生成のみの WIP が1件: caozhanhao/qrcode.mbt）。
- **狙うポジション: 「アクティブにメンテされた軽量・純粋なQRリーダー」= jsQR の後継枠。**

## 確定要件

| 項目 | 決定 |
|---|---|
| スコープ | 生成＋読取の両方 |
| バックエンド | ベンチマークスパイクで js / wasm-gc を実測して決定 |
| 配布 | npm（`moonqr`, `@moonqr/scanner`）+ mooncakes.io（`naoto24kawa/moonqr`） |
| 読取品質 | jsQR 同等（カメラ実用級: 回転・透視歪み・照明ムラ対応） |
| 位置づけ | 実用OSS（メンテ継続前提） |
| 実装方針 | 案A: jsQR（Apache-2.0）をアルゴリズム参照とする MoonBit 実装。帰属表示する |

npm 名の空きは 2026-07-13 時点で確認済み（`moonqr`・`@moonqr/*` とも未登録）。scope 使用時は npm org `moonqr` の作成が必要。

## アーキテクチャ

```
moonqr/                        # モノレポ
├── core/                      # MoonBit モジュール（mooncakes: naoto24kawa/moonqr）
│   └── src/
│       ├── gf256/             # GF(256)演算 + Reed-Solomon（生成・読取で共有）
│       ├── encode/            # 生成器: セグメント符号化→RS→マスク→行列出力
│       ├── decode/            # 読取器: 二値化→検出→透視変換→サンプル→復号
│       └── moonqr/            # 公開API（encode/decode を束ねる façade）
├── packages/
│   ├── moonqr/                # npm: core のビルド成果物 + TS型定義 + 薄いJSラッパ
│   └── scanner/               # npm: @moonqr/scanner（TypeScript 実装、moonqr に依存）
├── bench/                     # バックエンド選定スパイク + 継続ベンチ
└── fixtures/                  # jsQR テスト画像スイート（パリティ測定用）
```

### 責務の境界

- **core（`moonqr`）は純粋関数のみ。** DOM・Canvas・カメラに一切触れない。Node/bun でそのままテスト可能。
- **`@moonqr/scanner` は TypeScript で書く。** getUserMedia → video → Canvas → Uint8Array → Web Worker 上で core 呼び出し、というブラウザAPIの糊が仕事の全部であり、FFI を挟む意味がないため。Worker でUIスレッドを塞がない構成（qr-scanner 方式）を踏襲。
- **encode の正本出力は bool のモジュール行列。** SVG/Canvas 描画はその上のユーティリティ。DOM 依存の `toCanvas` は `moonqr/dom` サブパスに分離する。
- FFI 境界は `Bytes ↔ Uint8Array` / `String ↔ string` の直接対応のみ使い、複雑な型を渡さない。

## 公開API

### core（`moonqr`）

```ts
// 読取: RGBAピクセル → 結果（jsQR と同じ入力形状 = 乗り換え容易性）
decode(data: Uint8Array, width: number, height: number, options?: {
  invertAttempts?: "none" | "attemptBoth"   // 反転色QR対応、既定 "attemptBoth"
}): {
  text: string
  bytes: Uint8Array                          // バイナリペイロード用
  version: number
  ecLevel: "L" | "M" | "Q" | "H"
  corners: { x: number, y: number }[]        // 4隅（ハイライト描画用）
} | null

// 生成
encode(text: string, options?: {
  ecLevel?: "L" | "M" | "Q" | "H"            // 既定 "M"
  version?: number                            // 省略時 1..40 から自動選択
}): QrMatrix                                  // { size, get(x,y): boolean }

toSvgString(matrix, opts): string             // 余白・セルサイズ指定
toCanvas(matrix, canvas, opts): void          // moonqr/dom サブパス
```

### `@moonqr/scanner`

```ts
const scanner = new QrScanner(videoElement, onResult, {
  preferredCamera?: "environment" | "user",
  maxScansPerSecond?: number,                 // 既定 25
  highlightRegion?: boolean,
})
await scanner.start()    // getUserMedia → Worker 起動 → ループ開始
scanner.stop()           // ストリーム・Worker を全解放
QrScanner.scanImage(imageOrBlobOrUrl)         // 静止画の一発読取
```

データフロー: `video → Canvas(drawImage) → getImageData → Uint8Array → [Worker境界: transferable でゼロコピー] → core.decode → postMessage で結果返却`

## デコードパイプライン（6段・各段独立テスト可能）

1. **グレースケール化＋二値化** — RGBA → 輝度 → ブロック局所平均しきい値（8x8ブロック格子、照明ムラ耐性）→ `BitMatrix`
2. **ファインダパターン検出** — 走査線上の 1:1:3:1:1 黒白比探索 → 候補クラスタリング → 3点選定
3. **アライメント検出＋透視変換** — バージョン推定 → アライメントパターン探索 → 射影変換行列の導出
4. **グリッドサンプリング** — 逆写像でモジュール中心をサンプルし `BitMatrix` 抽出
5. **フォーマット/バージョン情報復号** — BCH 誤り訂正付きで ECレベル・マスク確定 → マスク解除
6. **コードワード復号** — ジグザグ読み出し → デインターリーブ → Reed-Solomon 誤り訂正（gf256 共有）→ セグメント復号（数字/英数字/バイト/漢字。ECI は UTF-8 のみ）

各段の失敗は Option（`None`）で上に返す。`invertAttempts: "attemptBoth"` 時は反転でもう1周。

## バックエンド選定スパイク（実装の最初に実施）

- 課題プログラム: 640x480 RGBA → グレースケール → 局所二値化 → 全行 1:1:3:1:1 走査、を MoonBit で1回だけ書き `js` / `wasm-gc` 両ターゲットにビルド
- 測定: Node と Chrome の両方で、**FFI 境界のコピーコスト込み**のフレームあたり時間（WasmGC は線形メモリがなく Uint8Array 受け渡しにコピー/変換コストがあるため、境界込みが本番の姿）
- 判定基準: 幾何平均で **1.3倍以上速い方を採用**。差が 1.3倍未満なら**配布が単純な js backend を採用**（async init 不要・バンドラ設定不要の DX 優位で決着）
- 結果と採用根拠は `bench/RESULT.md` に記録する

## エラー処理

- **core**: 読取失敗は `null`（正常系）。例外は契約違反のみ（`data.length !== width*height*4`、encode 容量超過等）。メッセージに原因と上限を含める。
- **scanner**: カメラ拒否・デバイス無しは `start()` の reject で伝播（握りつぶさない）。Worker クラッシュは自動再起動＋ `onError` コールバックへ surface。
- フレーム単位の decode 失敗はエラーではなく「次のフレームへ」。

## テスト戦略

| レイヤ | 手法 |
|---|---|
| gf256/RS | プロパティテスト: encode → ランダム t 個破壊 → decode == 元データ（t ≤ 訂正能力） |
| encode | 既知テストベクタ（ISO 付録・`qrcode` npm 出力と突合）＋ encode→自前 decode ラウンドトリップ全バージョン×全ECレベル |
| decode | jsQR テスト画像スイートを fixtures に取り込みパリティ測定（Apache-2.0・帰属表示） |
| scanner | Playwright + fake camera（`--use-fake-device-for-media-stream`）で E2E |
| 性能 | bench/ を CI に残し jsQR とフレーム処理時間を比較 |

## v1 Done 基準（rubric・完了ゲートの正本）

1. jsQR テストスイート読取率 ≥ jsQR 本家（同等以上）
2. 640x480 フレーム処理時間 ≤ jsQR の 1.2 倍以内
3. encode: バージョン 1-40 × L/M/Q/H 全組でラウンドトリップ成功＋実機スマホスキャナで読める
4. npm 2パッケージ＋ mooncakes 公開、README・デモページ（GitHub Pages）完備

## 実装順序（概要）

1. バックエンド選定スパイク（bench/）
2. gf256 + Reed-Solomon（プロパティテストで固める）
3. encode（テストベクタで検証、実機スキャン確認）
4. decode（6段を順に、encode をテストデータ生成器として活用）
5. npm パッケージング（moonqr）+ jsQR パリティ測定
6. @moonqr/scanner + デモページ
7. 公開（npm / mooncakes / GitHub Pages）

## 参照

- jsQR (Apache-2.0): アルゴリズム参照元 — https://github.com/cozmo/jsQR
- MoonBit FFI: https://docs.moonbitlang.com/en/latest/language/ffi.html
- qr-scanner（Worker 構成の参考）: https://github.com/nimiq/qr-scanner
- ISO/IEC 18004（QRコード仕様）
