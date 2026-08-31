# 2026-08-29 main 全体レビュー

## 対象と方法

- 対象: main 全体（対象 HEAD `1cb32e9`）
- レンズ: Fresh Eyes / Security / Core Logic / Tests / Domain / Ambiguity Hunter / Altitude Checker の7レンズ
- 初回 findings: flag 13件、optional 16件
- レンズ別 flag: Fresh Eyes 2 / Security 2 / Core Logic 1 / Tests 2 / Domain 2 / Ambiguity Hunter 3 / Altitude Checker 1

この文書は findings の全文を複製せず、解消先と判断記録への索引だけを残す。各修正の詳細と検証根拠は対応 PR 本文、修正後の収束結果は [`review-cycle-log.md`](review-cycle-log.md) を正本とする。

## flag 13件の解消先

| # | 指摘の要約 | 解消 PR |
|---|---|---|
| 1 | 小寸法画像の二値化が範囲外アクセスで panic する | [#23](https://github.com/elchika-inc/moonqr/pull/23) |
| 2 | MoonBit native encode の範囲外 version 指定が abort する | [#23](https://github.com/elchika-inc/moonqr/pull/23) |
| 3 | デモのファイル名を HTML 属性へ連結し、属性 XSS が成立する | [#23](https://github.com/elchika-inc/moonqr/pull/23) |
| 4 | decoder 例外が Worker の無限再生成につながる | [#23](https://github.com/elchika-inc/moonqr/pull/23) |
| 5 | 未対応の Structured Append を空文字の成功と誤認する | [#23](https://github.com/elchika-inc/moonqr/pull/23) |
| 6 | 公開 decode 実装へ到達する小寸法の totality テストがない | [#23](https://github.com/elchika-inc/moonqr/pull/23) |
| 7 | CLI の `isTTY` 禁止検査が `run` 関数だけを見ている | [#24](https://github.com/elchika-inc/moonqr/pull/24) |
| 8 | リリース手順の pack / publish / 外部検証から CLI が抜けている | [#24](https://github.com/elchika-inc/moonqr/pull/24) |
| 9 | CLI の package version と `--version` 出力の一致が CI で検査されない | [#24](https://github.com/elchika-inc/moonqr/pull/24) |
| 10 | `AGENTS.md` の build 手順に core の release build がない | [#25](https://github.com/elchika-inc/moonqr/pull/25) |
| 11 | PROJECT_GOAL / RELEASING の検証手順が必要な build 順を欠く | [#25](https://github.com/elchika-inc/moonqr/pull/25) |
| 12 | CONTRIBUTING のテスト手順が CLI パッケージを取りこぼす | [#25](https://github.com/elchika-inc/moonqr/pull/25) |
| 13 | 規範的な検証文書に変動するテスト件数が焼き込まれている | [#25](https://github.com/elchika-inc/moonqr/pull/25) |

PR [#22](https://github.com/elchika-inc/moonqr/pull/22) はこの main 全体レビューに先行する `optimal_segments` の性能改善と独立レビューサイクルであり、上記13件のカウントには含めない。

## optional 16件の扱い

### この文書修正束で解消: 5件

- README / SECURITY へ CLI パッケージを統合
- README の ECI / Structured Append 制約を実装に合わせる
- PROJECT_GOAL の版番号焼き込みを外し、CLI の DoneCriteria を追加
- RELEASING の GitHub ruleset ID を動的に取得
- RELEASING に npm / mooncakes 公開物の版一致検査を追加

### 明示受容: 5件

次の判断は [`../risk-registry.md`](../risk-registry.md) に影響、受容理由、再検討条件を記録した。

- デコーダの入力上限内でのピークメモリ
- SVG 出力の `margin` / `cell` 未検証
- npm パッケージの `prepack` が build を含まないこと
- 検証済み MoonBit ツールチェイン版文字列の重複管理
- 完了済み CLI 実装計画内の生成物全文の複製

### 既に解消済み: 2件

- CLI の `minify: false` に関する誤ったコメント: [#24](https://github.com/elchika-inc/moonqr/pull/24)
- CONTRIBUTING / TOOLCHAIN の変動テスト件数: [#25](https://github.com/elchika-inc/moonqr/pull/25)

### 別ブランチで対応中: 4件

2026-08-31 時点の照合では main の HEAD は `390e3f4`。次のコード・テスト側 optional は別ブランチで修正中であり、この時点で PR は未作成のため番号は記録しない。

- MoonBit native decode の入力長検証
- セグメント容量ガードのコメント
- `rs_decode` の clean path における配列所有権
- CLI `bin/moonqr.js` の実プロセス smoke test

## 記録の読み方

- 当時の指摘内容と修正根拠: PR #23〜#25 の本文
- 修正後のラウンド数、収束理由、確定した偽陽性: [`review-cycle-log.md`](review-cycle-log.md)
- 修正しない optional の判断: [`../risk-registry.md`](../risk-registry.md)
