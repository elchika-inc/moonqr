# OSS 受け入れ体制の整備（設計）

- 日付: 2026-07-28
- 対象: `elchika-inc/moonqr`
- 前提: v0.1.0 を npm 2 パッケージ・mooncakes・GitHub Pages へ公開済み

## 背景

公開は完了したが、リポジトリは「公開されただけ」の状態にある。外部から Issue / PR
を受け取る導線も、main への誤ったコミットを止める仕組みも無い。実測した欠落は次のとおり。

| 項目 | 状態 |
|---|---|
| CONTRIBUTING.md | あり（前提・ビルド順・4層テスト・生成ファイル・コード来歴ルール・PR 期待値） |
| SECURITY.md | あり |
| Issue テンプレート | `bug_report.yml` のみ |
| PR テンプレート | 無し |
| ブランチ保護 | 無し（main へ直接 push できる） |
| エージェント向け指示（CLAUDE.md / AGENTS.md） | 無し |
| リリース手順書 | 無し（v0.1.0 は手探りで実施した） |
| CODE_OF_CONDUCT / Discussions / CODEOWNERS | 無し |

## 決定事項

ブレストで確定した前提。以降の設計はすべてこれに従う。

1. **メンテナンス体制**: ソロ（human 1 名）＋ AI エージェント。人間のコントリビュータより先に、
   エージェントの誤操作を機械的に止めることを優先する。
2. **ブランチ保護**: PR 必須・CI 必須・**管理者にも適用**（bypass 不可）・force push 禁止・
   ブランチ削除禁止・必要な承認数 0。
3. **外部貢献**: 受け付けるが積極募集はしない。受け皿は最小限にとどめ、実際に PR が来てから拡張する。
4. **リリース**: 手動を維持する（npm の 2FA がそのまま human-gate として機能する）。
   代わりに手順を文書化して再現可能にする。

### 2 の補足: なぜ管理者にも適用するのか

エージェントは `gh` CLI で人間と同じトークンを使う。GitHub 側からエージェントと人間は区別できない。
「管理者は bypass 可」に設定すると、エージェントも同じ権限で bypass できるため防御にならない。
エージェントを止めるには、人間にも同じ制約をかける以外に方法がない。この不便は意図的に受け入れる。

## 成果物

### 1. `.github/pull_request_template.md`（新規）

このリポジトリで最も効くのは**来歴チェック**である。デコーダは jsQR（Apache-2.0）からの移植を含み、
Reed–Solomon / アライメントパターンのテーブルは qrcode-generator（MIT）由来である。出典不明の
コード（特に AI 生成物）が混入すると、ライセンス上の実害になる。CONTRIBUTING.md に文章として
書かれている来歴ルールを、PR ごとに機械的に確認させる形へ落とす。

チェック項目:

- 変更の種別（bugfix / feature / docs / chore）と目的
- **来歴の申告**: 自作 / 他プロジェクトからの移植（出典 URL・コミット SHA・ライセンスを明記）/
  AI 生成（人間がレビュー済みか）
- 実行したテスト: 4 層（`moon test` / `node --test` / vitest ×2）のどれを回したか、出力を貼る
- 生成ファイル（gitignore 対象だがビルドに必須）の扱いを理解しているか

### 2. Issue テンプレートの補強

- `.github/ISSUE_TEMPLATE/feature_request.yml`（新規）
- `.github/ISSUE_TEMPLATE/config.yml`（新規）— 脆弱性報告を SECURITY.md の私的報告経路へ誘導し、
  公開 Issue に書かせない

### 3. `RELEASING.md`（新規）

手動リリースを選んだ以上、この文書が「次回だれか（人間でもエージェントでも）が手探りしない」ための
唯一の防波堤になる。v0.1.0 の実施手順をそのまま固定化する。

1. `private: true` を両 package.json から外してコミット（このコミットが公開の意思表示）
2. 全 4 層のテストを回して緑を確認
3. `pnpm pack` で tarball の中身を検証（dist・法務 3 点のみ、ソース混入なし、
   `workspace:^` が実バージョンへ書き換わること）
4. publish を **core → scanner の順**で実行（scanner が core に依存するため順序は固定）
5. **リポジトリ外の新規プロジェクト**で install し、ESM / CJS 両経路で動作を検証
6. mooncakes: `moon publish`（`moon add` + `moon test` で外部から検証）
7. タグ `vX.Y.Z` と GitHub Release を作成
8. README / site の記述を更新

あわせて、v0.1.0 で実際に踏んだ罠を明記する。

- publish 直後は npm registry の反映が遅れ、`npm view` の 404 は「未公開」の証拠にならない
- pnpm の `There are no new packages that should be published` は「publish 済み」と
  「`private: true` でスキップ」の**両方**で出る。package.json とレジストリ実体の両方を見る
- mooncakes の `api/v0/user/...` は公開済み・未公開のどちらでも `Not Found` を返し、判別に使えない

### 4. `AGENTS.md`（新規）

ブランチ保護を入れると、エージェントの既定動作（main に直コミットして push）は必ず失敗する。
失敗したエージェントは「push できない」を別の問題と誤診し、force push を試したり保護を外しに
行ったりする。保護という sensor を入れる以上、対になる guide を同時に置く。

standards の `templates/AGENTS.md.template` を土台に、最小限の内容を書く。

- main は保護されている。作業は必ず feature branch → PR
- ビルド順序（MoonBit core が先）と 4 層テストの回し方は CONTRIBUTING.md を参照
- 生成ファイル（gitignore 対象だが必須）の扱い
- リリースは RELEASING.md に従う

### 5. `CONTRIBUTING.md` への追記

main が保護されていること、作業は必ず feature branch から PR を出すことを追記する。

### 6. ブランチ保護 ruleset

決定事項 2 の内容を GitHub 側へ設定する。設定はコードに残らないため、**内容を
`CONTRIBUTING.md` か `RELEASING.md` に転記**し、失われないようにする。

方式は **repository ruleset**（`/repos/{owner}/{repo}/rulesets`）を使う。classic branch
protection でも同じ制約はかけられるが、ruleset は bypass する主体を `bypass_actors` として
明示的に列挙する形になっており、「誰も bypass できない」を空配列として表現できる。classic の
`enforce_admins` フラグより意図が読み取りやすい。

required status check に指定するチェック名は **`test`**（`.github/workflows/ci.yml` の
ジョブ名）。ワークフロー名 `CI` ではない点に注意する。名前を間違えると、存在しないチェックを
待ち続けて PR が永久にマージ不能になる。設定後に実際の PR で緑になることを確認する（検証の節）。

## 作らないもの（YAGNI）

いずれも「実際に外部 PR / コントリビュータが現れてから」で間に合う。先に作ると、使われないまま
陳腐化する。

| 見送るもの | 理由 |
|---|---|
| CODE_OF_CONDUCT.md | 貢献者が現れてから。現時点で規律すべき相手がいない |
| GitHub Discussions | Issue で足りる。無人の掲示板は放置感を与える |
| CODEOWNERS | ソロなので自分を指名するだけになる |
| good first issue ラベル整備・ロードマップ公開 | 積極募集をしない方針のため |
| DCO / CLA | 受け入れる PR が実在してから判断する |
| リリースの CI 自動化 | 2FA を human-gate として維持する方針のため |

## 運用フローの変更

これまで（v0.1.0 まで）は main へ直接コミット・push していた。今後は次の形に統一する。

```
feature branch → PR → CI 緑 → merge（承認 0 なので自分で即マージ可）
```

この変更はエージェントの動作に直接影響するため、`AGENTS.md` に明記する（成果物 4）。

## 検証（完了ゲート）

「設定した」で完了とせず、実際に効いていることを確かめる。設定 API が 200 を返すことは、
保護が機能する証拠にはならない。

| 対象 | 検証方法 | 期待 |
|---|---|---|
| ブランチ保護 | `main` へ実際に push を試みる | **拒否される**（成功したら設計失敗） |
| required status check | PR を 1 本作る | CI が緑になるまでマージ不可 |
| PR テンプレート | 同じ PR を作成する | 本文にテンプレートが自動で入る |
| Issue テンプレート | 新規 Issue 画面を開く | bug / feature の選択肢と SECURITY 誘導が出る |

テンプレートを追加する PR 自体は、テンプレート未反映の状態で作られる（追加前だから）。
そのため**2 本目の小さな PR** で PR テンプレートの反映を確認する。

## 緊急時の抜け道

保護は管理者にも適用されるため、壊れた main を直接修正できない。手順を用意する。

1. ruleset を一時的に `disabled` にする
2. 修正する
3. **必ず再有効化する**

再有効化の失念が最大のリスクなので、`RELEASING.md` のリリース手順に「ruleset が `active` で
あることを確認する」を入れ、次のリリース時に必ず目視される形にする（定期実行の仕組みは作らない）。

## スコープ外

- **B: standards への一般化** — 本設計の実施で得た知見を `naoto24kawa/standards` へ
  横断ルールとして定義する。本設計の完了後に着手する。
- **C: Phase 4（機能開発）** — 漢字モード encode、混在モードのセグメント最適化、
  ECI / Structured Append / Micro QR。独立しており、いつでも着手できる。

## この設計自体のコミットについて

ブランチ保護を入れるのは実装フェーズであるため、本設計ドキュメントは main へ直接コミットする。
以降の変更（成果物 1〜6）から PR 運用に移行する。
