# standards 監査の checkpoint

standards `AUDIT.md`「エージェント PR 監査 checkpoint」が求める記録。次回の監査は `last_verified_commit` を除外し、その次のコミットから `HEAD` までを完全走査する。

last_verified_commit: 38f29a6ae63559868b983a3c680f8f00514aab44

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
