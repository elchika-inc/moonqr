---
updated: 2026-09-09
---

# STATUS — moonqr（ステータスシート）

## 現在地

- フェーズ: 公開済み。npm の 3 パッケージ、mooncakes.io の MoonBit モジュール、GitHub Pages のデモがいずれも稼働している
- 公開中の版: `@elchika-inc/moonqr` 0.2.0 / `@elchika-inc/moonqr-scanner` 0.2.0 / `@elchika-inc/moonqr-cli` 0.1.0
- 直近の完了: standards 監査（2026-09-08 実施、rev.89 を参照）で検出した MUST 違反 4 件の解消（[#34](https://github.com/elchika-inc/moonqr/pull/34) / [#36](https://github.com/elchika-inc/moonqr/pull/36) / [#37](https://github.com/elchika-inc/moonqr/pull/37) / [#38](https://github.com/elchika-inc/moonqr/pull/38)）
- 生成物の鮮度: `site/assets/` はビルドのたびに生成する（gitignore 対象。手順は [`../CONTRIBUTING.md`](../CONTRIBUTING.md)）。`core/src/encode/tables.mbt` と `core/src/decode/sjis.mbt` は固定した上流コミットから生成済み
- open Issue は `gh issue list --state open` を正とし、ここに件数を写さない

## 達成状況

基準の定義は [`PROJECT_GOAL.md`](PROJECT_GOAL.md) が正本。ここには状況だけを書く。
CI で毎 PR 検証される基準の確認日は、最新の成功した CI 実行日（run 34289440256, `f25dc5b`）である。

| 基準 | 状況 | 確認日 |
|---|---|---|
| デコーダの正しさ: jsQR の e2e コーパスで同等 | 達成。214/214（jsQR も 214/214、残る 40 件は両者とも読めず偽陽性も出さない） | 2026-09-09 |
| デコーダの速度: jsQR 以下のフレーム時間 | 達成。0.77x（QR あり）/ 0.75x（なし）。手動計測のため CI では追跡していない | 2026-07-14 |
| エンコーダの正しさ: qrcode npm と行列一致 | 達成。160/160（version 1-40 × EC L/M/Q/H） | 2026-09-09 |
| エンコーダの圧縮: 混在入力を区間ごとに最適なモードへ | 達成。qrcode npm と 44 ケースで同等以上（`https://ex.com/id/<100 桁>` が v7 から v4 へ縮む） | 2026-08-28 |
| バンドルサイズ: encode だけ使うならデコーダを含めない | 達成。`/encode` は gzip 7.5 KB で、デコーダのコードを 1 バイトも含まない | 2026-09-09 |
| 実機で読めること | 達成。実カメラ・モニタ越し撮影のマルチスケール再試行を含む。手動確認のため CI では追跡していない | 2026-07-14 |
| npm へ公開され、リポジトリ外から install して動く | 達成。ESM / CJS 両経路で検証 | 2026-09-02 |
| CLI パッケージを npm から install してターミナルへ QR コードを出力できる | 達成。`@elchika-inc/moonqr-cli` 0.1.0 を 2026-09-02 に公開。リポジトリ外で `npm install` した実体に対し、`npx moonqr --no-color https://example.com` が 17 行の QR を出力（exit 0）し、`npx moonqr --version` が `0.1.0` を返すことを確認 | 2026-09-09 |
| MoonBit プロジェクトから使える | 達成。mooncakes.io に `naoto24kawa/moonqr` | 2026-07-14 |
| 動作を試せるデモがある | 達成。<https://elchika-inc.github.io/moonqr/> | 2026-09-09 |
| 外部から Issue / PR を受けられる | 達成。CONTRIBUTING / SECURITY / PR・Issue テンプレート / ブランチ保護 | 2026-09-09 |
| リリース手順が再現可能 | 達成。[`../RELEASING.md`](../RELEASING.md) | 2026-09-02 |

## 読む順

1. [`PROJECT_GOAL.md`](PROJECT_GOAL.md)（ゴールシート）。何をするもので、何をしないか
2. [`../AGENTS.md`](../AGENTS.md)。開発の進め方と禁止事項
3. [`plans/2026-07-13-encoder-design.md`](plans/2026-07-13-encoder-design.md)。設計の原点
4. [`risk-registry.md`](risk-registry.md)。受け入れた欠陥とその検知手段

## プロジェクトドキュメント一覧

呼び名の定義は standards DOCS_OPS §3。

| 分類 | 形 | エントリ | 役割 |
|---|---|---|---|
| シート | 上書き | `PROJECT_GOAL.md` | ゴールシート。輪郭・成果物・成功基準 |
| シート | 上書き | `STATUS.md` | ステータスシート。現在地と入口（このファイル） |
| レコード | 行を足す | `risk-registry.md` | リスクレコード。受け入れた欠陥と anchor |
| ドキュメント | 不変 | `plans/` | 設計ドキュメントと実装計画 |
| ドキュメント | 不変 | `reviews/` | レビュー記録と standards 監査の checkpoint |
| キュー | 積む・消す | `actions/` | 次セッションへ渡す作業。完了分は `done/` へ移す |
