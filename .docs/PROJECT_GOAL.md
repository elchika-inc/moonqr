# PROJECT_GOAL — moonqr

MoonBit で書いた QR コードのエンコーダ / デコーダを、プレーンな JavaScript へコンパイルし、依存ゼロの npm パッケージとして提供する。WASM も native addon も使わない。

MoonBit で実用ライブラリを書き、既存実装と同等以上の正しさと速度に到達できるかを実測で確かめることが動機である。したがって性能・正確性の主張はすべて再現可能な計測に接地させる（[`bench/RESULT.md`](../bench/RESULT.md) が計測の正本）。

## SuccessCriteria

達成済みの基準。いずれも `bench/RESULT.md` に方法と結果を記録している。

| 基準 | 状態 |
|---|---|
| デコーダの正しさ: jsQR の e2e コーパスで同等 | ✅ 214/214（jsQR も 214/214、残る 40 件は両者とも読めず偽陽性も出さない） |
| デコーダの速度: jsQR 以下のフレーム時間 | ✅ 0.77x（QR あり）/ 0.75x（なし） |
| エンコーダの正しさ: qrcode npm と行列一致 | ✅ 160/160（version 1-40 × EC L/M/Q/H） |
| エンコーダの圧縮: 混在入力を区間ごとに最適なモードへ | ✅ qrcode npm と 44 ケースで同等以上。`https://ex.com/id/<100桁>` が v7 → v4 |
| バンドルサイズ: encode だけ使うならデコーダを含めない | ✅ `/encode` は gzip 7.5 KB（デコーダのコードはゼロ） |
| 実機で読めること | ✅ 実カメラでの読み取り、モニタ越し撮影のマルチスケール再試行を含む |

## DoneCriteria（公開物としての完了条件）

| 条件 | 状態 |
|---|---|
| npm へ公開され、リポジトリ外から install して動く | ✅ ESM / CJS 両経路で検証 |
| CLI パッケージを npm から install してターミナルへ QR コードを出力できる | ✅ `@elchika-inc/moonqr-cli` |
| MoonBit プロジェクトから使える | ✅ mooncakes.io に `naoto24kawa/moonqr` |
| 動作を試せるデモがある | ✅ https://elchika-inc.github.io/moonqr/ |
| 外部から Issue / PR を受けられる | ✅ CONTRIBUTING / SECURITY / PR・Issue テンプレート / ブランチ保護 |
| リリース手順が再現可能 | ✅ [`RELEASING.md`](../RELEASING.md) |

## スコープ外

意図的に実装しない。要望が実際に来た時点で再検討する。

- **漢字モードのエンコード** — Unicode → Shift-JIS の変換テーブルが必要で、`/encode` のバンドルサイズを大きく損なう（デコーダ側の SJIS テーブルは 141 KB）。デコードは対応済み
- **ECI / Structured Append / Micro QR** — 実需要が確認できていない
- **Model 2 以外の QR 規格**

## 判定に使う実測コマンド

主張が今も真であることは、次で確認できる。

```sh
export PATH="$HOME/.moon/bin:$PATH"
pnpm install --frozen-lockfile
cd core && moon test --target js && moon build --target js --release && cd ..
pnpm -r build
pnpm -r typecheck
node scripts/fetch-fixtures.mjs
node --test packages/moonqr/test/*.test.mjs   # jsQR パリティ・qrcode 比較・往復を含む
pnpm -r test:unit
node scripts/report-bundle-sizes.mjs          # バンドルサイズの実測値
```
