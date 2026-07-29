---
trigger: next-session
created: 2026-07-29
autonomy: manual
---

v0.2.0 をリリースする（Phase 4 の混在モードセグメント最適化を含む）。

手順は RELEASING.md に従う。publish は npm の 2FA プロンプトが human-gate として機能するため、人間の操作が必要（autonomy: manual の理由）。

バージョンを上げる対象は3箇所:
- packages/moonqr/package.json
- packages/scanner/package.json
- core/moon.mod.json

公開後は README / site の記載更新と、GitHub Release の作成まで行う。
