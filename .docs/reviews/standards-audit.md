# standards 監査の checkpoint

standards `AUDIT.md`「エージェント PR 監査 checkpoint」が求める記録。次回の監査は `last_verified_commit` を除外し、その次のコミットから `HEAD` までを完全走査する。

last_verified_commit: 338d3dc900be6b8c4fc57312bd39edfefd41c47f

## 2026-09-10 の監査

- フェーズ: progress
- 参照した standards: 2026-09-09 (rev.90)
- 監査時のプロジェクト宣言: 2026-09-07 (rev.89)
- 走査範囲: `38f29a6` の次から `338d3dc` まで（8 コミット）
- 対象 PR: `gh pr list --state merged --limit 100` で 41 件を取得（`--limit` に達していないため取りこぼしなし）。うち `mergeCommit.oid` が走査範囲に含まれるのは 8 件

### 監査中に standards が更新された

監査の実行時点で standards は rev.90（`5bf71e0`）だったが、対応作業の途中で rev.91（`c9567a4`）へ更新された。`AUDIT.md` の差分は 6 ハンクすべてが anchor 機械検査に閉じており（対象外件数 `anchor_uncounted` の出力追加）、他のチェック項目の表は変わっていない。moonqr は表形式の受容エントリを持たず `anchor_uncounted=0` のため、rev.91 が新設した人間レビュー行きの条件には該当しない。検出内容は rev.91 でも変わらないことを `AUDIT.md` の差分で確認した。

この更新により、rubric に焼き込んでいた `AUDIT.md` の行番号（抽出範囲 `381,1066`）がブロック途中で切れ、検証コマンドが exit 2 で落ちた。抽出範囲は `381,1092` へ訂正した。行番号のような変動する値を検証手順へ焼き込むと、正本の更新で静かに壊れる。

### エージェントのマージ記録

走査範囲の 8 件（#34 #35 #36 #37 #38 #39 #40 #42）すべてに `agent-merge-verdict/human-v2` があり、必須 4 項目（実装担当識別子・判定時 head・承認した人間・承認の所在）が全件そろっていた。verdict の判定時 head は 8 件とも実マージ head と一致した。`merge_policy: human` 下で禁じられる `agent-merge-verdict/v1` は 0 件だった。

### 検出した MUST 違反と解消先

| 違反 | 解消 PR |
|---|---|
| `AGENTS.md` の Key Commands に `deploy` の記載が無い（AI_FIRST §4） | [#43](https://github.com/elchika-inc/moonqr/pull/43) |
| `AGENTS.md` に routes / 主要ページ一覧が無い（AI_FIRST §4） | [#43](https://github.com/elchika-inc/moonqr/pull/43) |
| PR #37 の UI 変更にブラウザ検証証跡が無い（AI_FIRST §2） | [#44](https://github.com/elchika-inc/moonqr/pull/44) — RISK-012 として受容 |

### 検出した WARN と対応

| 項目 | 対応 |
|---|---|
| `standards_version` が rev.89 のまま | [#45](https://github.com/elchika-inc/moonqr/pull/45) で rev.91 へ更新 |
| README に Deploy バッジが無い（DOCS_OPS §1 — MUST。`deploy.yml` が無いため免除がファイル名の一致だけで成立） | [#45](https://github.com/elchika-inc/moonqr/pull/45) — RISK-013 として受容 |
| ブラウザ検証証跡の受け皿（PR テンプレートの Browser verification 欄）が一度も埋まった実績を持たない | 次に `site/` を変更する PR が現れるまで実証できない。RISK-012 の `Follow-up` に記録 |
| `pages.yml` の `workflow_dispatch` が任意ブランチから `pages: write` / `id-token: write` でデプロイを起動しうる | DOCS_OPS §6 の信頼境界は非 `main` push とマージ前 PR 入力を対象とするため規約上は適用範囲外。ただし `merge_policy: human` が理由とする「マージが人間の止められる最後の点」は迂回されうる。観測として記録する |

### 版を上げる判断

前回監査の慣行は「未解消の WARN が残る間は `standards_version` を上げない」だった。ブラウザ検証証跡の受け皿に関する WARN はこのセッションで原理的に実証できないため、オーナーの明示裁定（2026-09-10）により版を上げた。

### 根拠付きで N/A と判定した項目

HTTP API・データベース・認証・管理エンドポイント・Webhook・外向き HTTP・個人データをいずれも持たないため次は対象外とした: Zod 境界検証、`team_id` テナント分離、UGC 防御、CF Access、公開取得経路、GDPR、法務ページ、SSRF 防止、レートリミット、パスワードハッシュ。DESIGN は React SPA を対象とするため、素の HTML と JavaScript で書かれた `site/` は適用範囲外。ロケール JSON を持たないため i18n の同時追加検査も対象外（`site/i18n.js` の単一辞書に ja / en が同居）。`apps/` を持たないため apps 間直接 import も対象外。`.docs/guarantees.md` が無いため保証レコードの配線は対象外。「時点に依存する観測記録を置く層」を宣言していないため参照資料と要求事項の分離も対象外。`ci.yml` の `test` job は `permissions: contents: read` のみで secrets 参照・OIDC を持たないため、信頼境界の緩和 checkpoint の発火条件に当たらない（記録は不要）。

### self-test の結果

検出系のチェックはすべて既知の違反 fixture で 1 件ヒットすることを確認してから実行した。`AUDIT.md` のドキュメント検査ブロックは内蔵の self-test 群を通して exit 0。外部ヘッドレス CMS の混入検査は `@sanity/client` の fixture で 1 件検出を確認したうえで本番 0 件。公開物の `workspace:` 残留検査も `workspace:^` の fixture で 1 件検出を確認したうえで本番 0 件。ファイル名 kebab-case は Biome の `useFilenamingConvention` が error レベルで有効かつ `biome check` が 64 ファイルを処理して exit 0 のため、`AUDIT.md` の規定により `find` を省略した。

### `last_verified_commit` に `338d3dc` を記録する理由

`AUDIT.md` は「全 AUDIT 項目の判定完了後にだけ、その監査で確認した `HEAD` へ更新する」と定める。今回確認した HEAD は `338d3dc` である。対応 PR #43 / #44 / #45 はこの監査の成果物であって監査対象ではないため、次回の走査範囲に残す。現在の HEAD を記録すると、監査を経ていない 3 件を監査済みとして扱うことになる。

## 2026-09-08 の監査

- フェーズ: progress
- 参照した standards: 2026-09-07 (rev.89)
- 監査時のプロジェクト宣言: 2026-08-15 (rev.71)
- 走査範囲: root commit から `38f29a6` まで（本規則の初回適用のため全履歴）
- 対象 PR: `gh pr list --state merged --limit 100` で 33 件を取得（`--limit` に達していないため取りこぼしなし）

### エージェントのマージ記録

33 件すべてに `agent-merge-verdict/v1` と `agent-merge-verdict/human-v2` のいずれのマーカーも無く、`mergedBy` は全件が同一の人間アカウントだった。人間がマージしたものとして扱う。マーカー不在は「人間がマージした」と「エージェントが記録を怠った」を区別しない（standards `DOCS_OPS.md` §5 の残余リスク）。

この監査以降にマージした PR からは `agent-merge-verdict/human-v2` を投稿している。

### 検出した MUST 違反と解消先

| 違反 | 解消 PR |
|---|---|
| `AGENTS.md` に `merge_policy` の記録が無い（DOCS_OPS §5） | [#34](https://github.com/elchika-inc/moonqr/pull/34) |
| `risk-registry.md` の受容エントリに `anchor` が無い（DOCS_OPS §3） | [#36](https://github.com/elchika-inc/moonqr/pull/36) |
| Biome が未導入で lint 設定が存在しない（PROJECT_RULES） | [#37](https://github.com/elchika-inc/moonqr/pull/37) |
| UI 変更 PR にブラウザ検証の証跡が無い（AI_FIRST §2） | [#38](https://github.com/elchika-inc/moonqr/pull/38) |

### 未解消の項目

| 項目 | レベル | 状況 |
|---|---|---|
| `standards_version` が rev.71 のまま（rev.89 との差 18） | — | 未解消の WARN が残る間は上げない |
| README のセクション構成（Contributing 節が無い・Development がコマンドテーブルでない） | MUST（公開 OSS） | 別 PR で対応する |
| `site/index.html` に `og:image` が無い | SHOULD | 未着手 |

### 根拠付きで N/A と判定した項目

HTTP API・データベース・認証・管理エンドポイント・Webhook・外向き HTTP・個人データをいずれも持たないため、次は対象外とした: Zod 境界検証、`team_id` テナント分離、UGC 防御、CF Access、公開取得経路、GDPR、法務ページ、SSRF 防止、レートリミット、パスワードハッシュ。DESIGN の実装方式は React SPA を対象とするため、素の HTML と JavaScript で書かれた `site/` は適用範囲外。
