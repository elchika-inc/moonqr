# OSS 受け入れ体制の整備 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** moonqr が外部からの Issue / PR を受け取れる状態にし、あわせて main への誤ったコミット（特に AI エージェントによるもの）を機械的に止める。

**Architecture:** 3 タスクを「各タスクが次のタスクの検証を兼ねる」順序で実施する。まずブランチ保護を入れて運用を PR 経由へ切り替え（Task 1）、次にテンプレート類を最初の PR として提出することで保護が効いていることを実証し（Task 2）、最後にドキュメント類を 2 本目の PR として提出することで PR テンプレートの反映を実証する（Task 3）。

**Tech Stack:** GitHub repository rulesets（`/repos/{owner}/{repo}/rulesets` API）、GitHub Issue Forms（YAML）、`gh` CLI。コード変更は無い。

## Global Constraints

- **公開ドキュメントは英語**で書く。README.md / CONTRIBUTING.md / SECURITY.md / `bug_report.yml` が既に英語であり、外部コントリビュータが読む文書のため。
- **コミットメッセージは日本語**で書く。リポジトリの既存履歴がすべて日本語のため。
- リポジトリは `elchika-inc/moonqr`。デフォルトブランチは `main`。
- CI ワークフローのジョブ名は **`test`**（`.github/workflows/ci.yml` の `jobs.test`）。required status check にはワークフロー名 `CI` ではなくこの `test` を指定する。
- `docs/superpowers/` と `.superpowers/` は `.gitignore` 対象。設計・計画はコミットしない。
- 作らないもの: CODE_OF_CONDUCT.md、GitHub Discussions、CODEOWNERS、good first issue ラベル整備、DCO / CLA、リリースの CI 自動化。

---

### Task 1: ブランチ保護 ruleset を設定する

**Files:**
- Create: なし（GitHub 側の設定のみ。設定内容は Task 3 で `CONTRIBUTING.md` へ転記する）

**Interfaces:**
- Consumes: なし
- Produces: `main` が保護された状態。以降の Task 2 / Task 3 はすべて feature branch → PR 経由で実施することになる。

- [ ] **Step 1: 現状のベースラインを確認する**

保護が「無い」ことを先に確認しておく。これを記録しておかないと、あとで拒否された時に「元から拒否されていたのか、設定が効いたのか」が区別できない。

```bash
gh api repos/elchika-inc/moonqr/rulesets
gh api repos/elchika-inc/moonqr/branches/main/protection
```

Expected: rulesets は `[]`（空配列）、protection は `Branch not protected`（HTTP 404）。

- [ ] **Step 2: ruleset の定義を書く**

`/tmp` などリポジトリ外に `ruleset.json` を作る（リポジトリに残さない）。

```json
{
  "name": "main protection",
  "target": "branch",
  "enforcement": "active",
  "conditions": {
    "ref_name": {
      "include": ["~DEFAULT_BRANCH"],
      "exclude": []
    }
  },
  "bypass_actors": [],
  "rules": [
    { "type": "deletion" },
    { "type": "non_fast_forward" },
    {
      "type": "pull_request",
      "parameters": {
        "required_approving_review_count": 0,
        "dismiss_stale_reviews_on_push": false,
        "require_code_owner_review": false,
        "require_last_push_approval": false,
        "required_review_thread_resolution": false
      }
    },
    {
      "type": "required_status_checks",
      "parameters": {
        "strict_required_status_checks_policy": false,
        "required_status_checks": [
          { "context": "test" }
        ]
      }
    }
  ]
}
```

各ルールの意味:

- `deletion` — `main` の削除を禁止
- `non_fast_forward` — force push を禁止
- `pull_request` with `required_approving_review_count: 0` — PR は必須だが承認は不要（ソロなので自分でマージできる）
- `required_status_checks` with `context: "test"` — CI ジョブ `test` の成功を必須にする
- `bypass_actors: []` — **誰も bypass できない**。管理者も対象になる
- `strict_required_status_checks_policy: false` — main が進んでも PR ブランチの rebase を強制しない（ソロで直列に作業するため不要）

- [ ] **Step 3: ruleset を作成する**

```bash
gh api repos/elchika-inc/moonqr/rulesets -X POST --input /tmp/ruleset.json
```

Expected: 作成された ruleset の JSON が返り、`"enforcement": "active"` と `"bypass_actors": []` を含む。

- [ ] **Step 4: 保護が実際に効くことを確認する（最重要）**

API が 200 を返したことは、保護が機能する証拠にはならない。実際に push を試して**拒否されること**を確認する。

```bash
git switch main
git pull
# 空コミットで試す（内容を汚さない）
git commit --allow-empty -m "test: ブランチ保護の動作確認（拒否されるはず）"
git push origin main
```

Expected: push が **拒否される**。エラーに `Changes must be made through a pull request` が含まれる。

もし push が成功してしまったら設定が効いていない。その場合はコミットを取り消し（`git reset --hard origin/main` は push 済みなら使えないので、`git revert` するか、ruleset を直してから対応する）、Step 2 の JSON を見直す。

- [ ] **Step 5: ローカルの空コミットを捨てる**

push は拒否されているので、ローカルのコミットだけを取り消す。

```bash
git reset --hard origin/main
git log --oneline -1
```

Expected: `17afb08 docs(site): 公開済みリンクへ差し替え（npm 2パッケージ・mooncakes）`（＝ Task 1 開始時点の HEAD に戻っている）。

- [ ] **Step 6: ruleset の ID を控える**

このタスクにはコミットが無い（GitHub 側の設定のみ）。設定内容が失われないよう、Task 3 で `CONTRIBUTING.md` へ転記する。ここでは ruleset の ID を控えておく。

```bash
gh api repos/elchika-inc/moonqr/rulesets --jq '.[] | "\(.id) \(.name) \(.enforcement)"'
```

Expected: `<数値ID> main protection active` の 1 行。この ID は緊急時に ruleset を無効化する際に使う。

- [ ] **Step 7: 緊急時手順（無効化 → 再有効化）が実際に動くことを確認する**

`RELEASING.md`（Task 3）に緊急時の抜け道を書くが、**その手順を書くだけで検証しないと、本当に緊急のときに初めて動かないことが分かる**。今のうちに 1 往復させて確かめる。

`<id>` は Step 6 で得た数値 ID に置き換える。

```bash
# 無効化
gh api repos/elchika-inc/moonqr/rulesets/<id> -X PUT -f enforcement=disabled
gh api repos/elchika-inc/moonqr/rulesets/<id> --jq .enforcement
```

Expected: `disabled`。

ここで、無効化したときに **他のルールが消えていないこと**も確認する。`-f enforcement=...` の部分更新が `rules` を空にしてしまう API 実装だと、再有効化しても保護が空になる。

```bash
gh api repos/elchika-inc/moonqr/rulesets/<id> --jq '.rules | map(.type)'
```

Expected: `["deletion","non_fast_forward","pull_request","required_status_checks"]` の 4 件が残っている。もし空配列や欠落があれば、部分更新は使えない。その場合は Step 2 の JSON に `"enforcement": "disabled"` を入れたものを `--input` で PUT する方式に切り替え、`RELEASING.md` にもその方式を書く。

```bash
# 再有効化
gh api repos/elchika-inc/moonqr/rulesets/<id> -X PUT -f enforcement=active
gh api repos/elchika-inc/moonqr/rulesets/<id> --jq '{enforcement, rules: (.rules | map(.type))}'
```

Expected: `enforcement` が `active`、`rules` が 4 件そろっている。

最後に、保護が戻っていることを実測で確認する（Step 4 と同じ手順）。

```bash
git commit --allow-empty -m "test: 再有効化後の保護確認（拒否されるはず）"
git push origin main
git reset --hard origin/main
```

Expected: push が拒否され、`git reset` 後の HEAD が `origin/main` と一致する。

---

### Task 2: PR テンプレートと Issue テンプレートを追加する

**Files:**
- Create: `.github/pull_request_template.md`
- Create: `.github/ISSUE_TEMPLATE/feature_request.yml`
- Create: `.github/ISSUE_TEMPLATE/config.yml`

**Interfaces:**
- Consumes: Task 1 で設定したブランチ保護（この PR がその動作確認を兼ねる）
- Produces: `.github/pull_request_template.md` の存在。Task 3 の PR 作成時に本文へ自動挿入されることで、テンプレートの反映が実証される。

- [ ] **Step 1: feature branch を作る**

Task 1 で main が保護されたので、ここから先は必ずブランチを切る。

```bash
git switch -c chore/contribution-templates
```

- [ ] **Step 2: PR テンプレートを作る**

`.github/pull_request_template.md` を次の内容で作成する。主眼は来歴チェック。`moon fmt` の禁止と生成ファイルの扱いは `CONTRIBUTING.md` に既にあるルールを、PR ごとに確認させる形にしたもの。

```markdown
## What this changes

<!-- One or two sentences. Link the issue if there is one. -->

## Type of change

- [ ] Bug fix
- [ ] New feature
- [ ] Documentation
- [ ] Chore / build / CI

## Provenance

This project vendors ported code (jsQR, Apache-2.0) and derived tables (qrcode-generator, MIT).
Keeping provenance explicit is what makes the license story auditable. Please state where the
non-trivial parts of this change came from — pick all that apply.

- [ ] **Written by me** — not copied from another project
- [ ] **Ported from another project** — source URL, commit SHA, and license:
      <!-- e.g. https://github.com/cozmo/jsQR @ 8e6a036beafa7053dd44b1b76ac578d22b1b3311, Apache-2.0 -->
- [ ] **Generated with an AI assistant** — and I have read every line and can explain what it does

If you ported code, add the attribution to `NOTICE` and `THIRD_PARTY_LICENSES` in this same PR.

## Tests

Which layers did you run? Paste the output.

- [ ] `cd core && moon test --target js`
- [ ] `node --test packages/moonqr/test/*.test.mjs`
- [ ] `pnpm --filter @elchika-inc/moonqr test:unit`
- [ ] `pnpm --filter @elchika-inc/moonqr-scanner test:unit`
- [ ] `pnpm -r typecheck`

<details>
<summary>Test output</summary>

```
paste here
```

</details>

## Checklist

- [ ] I did **not** run `moon fmt` (see CONTRIBUTING.md — on some toolchain versions it starts a repo-wide config migration that touches unrelated files)
- [ ] I understand `core/_build/` is gitignored but required — the MoonBit core must be built before the TS packages
- [ ] Changes are scoped; no unrelated reformatting (this codebase is diffed against upstream sources)
```

- [ ] **Step 3: feature request テンプレートを作る**

`.github/ISSUE_TEMPLATE/feature_request.yml` を次の内容で作成する。既存の `bug_report.yml` と同じ Issue Forms 形式・同じ英語の語り口に合わせる。

```yaml
name: Feature request
description: Suggest a capability moonqr doesn't have yet
labels: ["enhancement"]
body:
  - type: markdown
    attributes:
      value: |
        The known gaps are listed under "Limitations" in the README — Kanji-mode encoding,
        mixed-mode segment optimization, and ECI / Structured Append / Micro QR. If your
        request is one of those, say so: knowing which ones people actually need is what
        decides the order they get built in.

  - type: textarea
    id: problem
    attributes:
      label: What are you trying to do
      description: Describe the use case, not only the feature. What are you building, and where does moonqr fall short?
    validations:
      required: true

  - type: textarea
    id: proposal
    attributes:
      label: What you would like moonqr to do
    validations:
      required: true

  - type: dropdown
    id: area
    attributes:
      label: Area
      options:
        - Encoder
        - Decoder
        - Scanner (camera)
        - Build / packaging
        - Docs
        - Not sure
    validations:
      required: true

  - type: checkboxes
    id: contribution
    attributes:
      label: Contribution
      options:
        - label: I would be willing to open a pull request for this (please read CONTRIBUTING.md first — provenance rules apply to ported and AI-generated code)
```

- [ ] **Step 4: Issue テンプレートの config を作る**

`.github/ISSUE_TEMPLATE/config.yml` を次の内容で作成する。脆弱性を公開 Issue に書かせないための誘導が目的。空の Issue は許可したままにする（質問を締め出さないため）。

```yaml
blank_issues_enabled: true
contact_links:
  - name: Security vulnerability
    url: https://github.com/elchika-inc/moonqr/security/policy
    about: Please report vulnerabilities privately. Do not open a public issue for them.
```

- [ ] **Step 5: コミットして push する**

```bash
git add .github/pull_request_template.md .github/ISSUE_TEMPLATE/feature_request.yml .github/ISSUE_TEMPLATE/config.yml
git commit -m "chore: PR/Issueテンプレートを追加（来歴チェックを必須化）

外部からのPRを受け取る前提で、CONTRIBUTING.mdの来歴ルールをPRごとに
機械的に確認させる形へ落とす。jsQR/qrcode-generator からの移植を含む
ため、出典不明コード（特にAI生成物）の混入はライセンス上の実害になる。

脆弱性は config.yml で SECURITY.md の私的報告経路へ誘導し、公開Issueに
書かせない。空Issueは質問を締め出さないため許可のまま。"
git push -u origin chore/contribution-templates
```

- [ ] **Step 6: PR を作ってブランチ保護の動作を確認する**

この PR 自体にはテンプレートが適用されない（マージ前だから）。ここで確認するのは**保護が効いていること**。

```bash
gh pr create --title "chore: PR/Issueテンプレートを追加" --body "Task 1 で入れたブランチ保護の動作確認を兼ねる最初の PR。

- PR テンプレート（来歴チェック主眼）
- feature request テンプレート
- Issue config（脆弱性を SECURITY.md へ誘導）

このPR自体はテンプレート追加前に作成されるため本文は手書き。テンプレートの
反映は次のPRで確認する。"
gh pr checks --watch
```

Expected: `test` チェックが走り、緑になるまでマージできない。

- [ ] **Step 7: CI 緑を確認してマージする**

```bash
gh pr view --json mergeable,mergeStateStatus,statusCheckRollup --jq '{mergeable, mergeStateStatus}'
gh pr merge --squash --delete-branch
```

Expected: マージ成功。マージ前の `mergeStateStatus` が `BLOCKED`（CI 待ち）から `CLEAN` へ変わっていること。

- [ ] **Step 8: Issue テンプレートが反映されたことを確認する**

```bash
gh api repos/elchika-inc/moonqr/contents/.github/ISSUE_TEMPLATE --jq '.[].name'
```

Expected: `bug_report.yml`、`config.yml`、`feature_request.yml` の 3 件。

---

### Task 3: AGENTS.md・RELEASING.md を作り CONTRIBUTING.md を更新する

**Files:**
- Create: `AGENTS.md`
- Create: `RELEASING.md`
- Modify: `CONTRIBUTING.md`（`## PR expectations` の直前に `## Branch protection` を追加）

**Interfaces:**
- Consumes: Task 1 の ruleset（内容を `CONTRIBUTING.md` へ転記する）、Task 2 の `pull_request_template.md`（この PR の本文へ自動挿入されることを確認する）
- Produces: なし（最終タスク）

- [ ] **Step 1: feature branch を作る**

```bash
git switch main
git pull
git switch -c docs/agent-guide-and-releasing
```

- [ ] **Step 2: AGENTS.md を作る**

ブランチ保護（sensor）と対になる guide。保護だけ入れると、push を拒否されたエージェントが force push や保護解除を試みる。

`AGENTS.md` を次の内容で作成する。

```markdown
# Notes for AI coding agents

Human contributors: read [CONTRIBUTING.md](CONTRIBUTING.md) instead. This file covers the
things agents specifically get wrong in this repository.

## `main` is protected — never commit to it directly

`main` requires a pull request and a green CI run, and the protection applies to
administrators too. A direct push will be rejected.

This is deliberate. An agent and its human operator share the same GitHub token, so GitHub
cannot tell them apart — protection that administrators can bypass would not protect anything.

Work like this:

```sh
git switch -c <branch>
# make changes, run the tests below
git push -u origin <branch>
gh pr create
```

If a push to `main` is rejected, **that is the protection working.** Do not force push, do not
disable the ruleset, and do not try to "fix" it. Open a pull request.

## Build order: the MoonBit core comes first

`core/` compiles to JavaScript that tsup inlines into the TS packages. Building the TS packages
without building the core first silently uses stale or missing output.

```sh
export PATH="$HOME/.moon/bin:$PATH"
cd core && moon build --target js && cd ..
pnpm -r build
```

`core/_build/` is gitignored but required. A clean checkout builds nothing useful until the core
is built.

## Never run `moon fmt`

On some toolchain versions it starts a repo-wide MoonBit config migration (`moon.mod.json` →
`moon.mod` and similar) that rewrites unrelated files. Format MoonBit code by hand to match the
surrounding style.

## Tests: four layers, all must pass

```sh
cd core && moon test --target js && cd ..     # MoonBit unit tests
node scripts/fetch-fixtures.mjs               # jsQR corpus — network, cached after first run
node --test packages/moonqr/test/*.test.mjs   # jsQR parity + encoder sweep
pnpm -r test:unit                             # vitest, both packages
pnpm -r typecheck
```

## Provenance applies to generated code

Parts of the decoder are ported from [jsQR](https://github.com/cozmo/jsQR) (Apache-2.0), and the
Reed–Solomon block / alignment-pattern tables are derived from
[qrcode-generator](https://github.com/kazuhikoarase/qrcode-generator) (MIT).

Code you generate must not reproduce code from other projects without attribution in `NOTICE`
and `THIRD_PARTY_LICENSES`. State the provenance in the pull request description — the PR
template asks for it.

## Releasing

Follow [RELEASING.md](RELEASING.md). Publishing is deliberately manual and requires a human.
```

- [ ] **Step 3: RELEASING.md を作る**

v0.1.0 の実施手順をそのまま固定化する。踏んだ罠も明記する。

`RELEASING.md` を次の内容で作成する。

```markdown
# Releasing

Publishing is deliberately manual. npm's 2FA prompt is the human gate — there is no CI job that
can publish on its own, and that is by design.

Three registries are involved, and they are published in this order:

1. `@elchika-inc/moonqr` (npm)
2. `@elchika-inc/moonqr-scanner` (npm) — depends on the above, so the order is not optional
3. `naoto24kawa/moonqr` (mooncakes.io) — the MoonBit source module

## 1. Preflight

```sh
gh api repos/elchika-inc/moonqr/rulesets --jq '.[] | "\(.name) \(.enforcement)"'
```

Expected: `main protection active`. If it says `disabled`, someone turned it off for an
emergency fix and did not turn it back on. Re-enable it before releasing.

Confirm you are logged in to both registries:

```sh
npm whoami          # expect your npm username
moon whoami         # expect "Logged in as <user>"
```

## 2. Bump versions

Both packages and the MoonBit module carry the same version number.

- `packages/moonqr/package.json`
- `packages/scanner/package.json`
- `core/moon.mod.json`

Open a PR for the bump like any other change — `main` is protected.

## 3. Run every test layer

```sh
export PATH="$HOME/.moon/bin:$PATH"
cd core && moon test --target js && cd ..
node scripts/fetch-fixtures.mjs
node --test packages/moonqr/test/*.test.mjs
pnpm -r test:unit
pnpm -r typecheck
pnpm -r build
```

All four layers must be green before anything is published.

## 4. Verify the tarballs before publishing

`pnpm pack` works even when a package is marked private, so you can inspect exactly what would
be uploaded without risking a publish.

```sh
pnpm --filter @elchika-inc/moonqr pack --pack-destination /tmp
pnpm --filter @elchika-inc/moonqr-scanner pack --pack-destination /tmp
tar tzf /tmp/elchika-inc-moonqr-*.tgz | sort
tar xzOf /tmp/elchika-inc-moonqr-scanner-*.tgz package/package.json | grep -A3 '"dependencies"'
```

Check:

- Only `dist/`, `README.md`, `LICENSE`, `NOTICE`, `THIRD_PARTY_LICENSES` are included — no
  sources, no tests, no configs.
- The scanner's dependency on the core reads as a real version (`^0.1.0`), not `workspace:^`.
  pnpm rewrites this automatically; verifying it is what proves the package works outside the
  monorepo.

## 5. Publish to npm

```sh
pnpm --filter @elchika-inc/moonqr publish --no-git-checks
pnpm --filter @elchika-inc/moonqr-scanner publish --no-git-checks
```

npm will ask for a one-time password. This is the human gate.

## 6. Verify from outside the repository

This is the step that actually proves the release works. Running things inside the workspace
proves nothing: pnpm's workspace links hide broken dependency declarations.

```sh
mkdir /tmp/verify && cd /tmp/verify && npm init -y
npm install @elchika-inc/moonqr @elchika-inc/moonqr-scanner
node -e 'import("@elchika-inc/moonqr/encode").then(m => console.log(m.encode("HELLO", {ecLevel:"M"}).size))'
node -e 'console.log(typeof require("@elchika-inc/moonqr/encode").encode)'
```

Expect a module size (21 for `HELLO`) from the ESM path and `function` from the CJS path.
Both matter: a broken `exports` map often fails in only one of them.

## 7. Publish to mooncakes

```sh
cd core
moon publish --dry-run   # ends with a non-zero exit even on success; look for "202 Accepted"
moon publish             # look for "200 OK"
```

Verify from outside, the same way:

```sh
cd /tmp && moon new consumer --user verify && cd consumer
moon add naoto24kawa/moonqr    # expect "Downloading naoto24kawa/moonqr@<version>"
```

## 8. Tag and release

```sh
git tag -a vX.Y.Z <merge commit> -m "vX.Y.Z"
git push origin vX.Y.Z
gh release create vX.Y.Z --title "vX.Y.Z" --notes-file <notes>
```

## 9. Update the docs that quote the release

`README.md` and `site/` mention published versions and links. Update them in a PR, then confirm
the Pages deploy succeeded and the live page actually renders — a green workflow is not proof
that the page works.

## Signals that lie

These cost real time during the v0.1.0 release. Do not repeat them.

- **`npm view <pkg>` returning 404 right after publishing does not mean the publish failed.**
  The registry takes time to propagate. Check `https://registry.npmjs.org/<pkg>` directly, and
  wait before concluding anything.
- **pnpm's `There are no new packages that should be published` has two meanings**: the version
  is already published (success), or the package still has `private: true` (nothing happened).
  The message is identical. Check `package.json` and the registry to tell them apart.
- **mooncakes' `api/v0/user/<user>/<mod>` returns `Not Found` whether or not the module is
  published.** It cannot be used to verify a release. Use `moon add` from a scratch module.
- **A green Pages workflow does not mean the demo works.** The site resolves bare specifiers
  through an import map pointing at `./assets/`; one missing file makes the page fail to load
  entirely while the workflow still reports success.

## Emergency: fixing a broken `main`

Branch protection applies to administrators, so a broken `main` cannot be fixed with a direct
push. If a PR is genuinely not viable:

```sh
gh api repos/elchika-inc/moonqr/rulesets/<id> -X PUT -f enforcement=disabled
# fix main
gh api repos/elchika-inc/moonqr/rulesets/<id> -X PUT -f enforcement=active
```

Re-enabling is the step that gets forgotten. The preflight check in step 1 exists to catch it.
```

- [ ] **Step 4: CONTRIBUTING.md にブランチ保護の節を追加する**

`## PR expectations` の直前に、次の節を挿入する。ruleset の設定内容はここに転記しておく（GitHub 側の設定はコードに残らないため、記録が無いと失われる）。

```markdown
## Branch protection

`main` is protected. All changes — including from maintainers — go through a pull request:

```sh
git switch -c <branch>
git push -u origin <branch>
gh pr create
```

The ruleset requires a pull request (0 approvals — this is a solo-maintained project), requires
the `test` CI job to pass, forbids force pushes and branch deletion, and has an empty bypass
list, so it applies to administrators too. AI agents share their operator's GitHub token, so a
protection that admins could bypass would not protect anything.

See [RELEASING.md](RELEASING.md) for how to disable it in an emergency — and for the reminder to
turn it back on.

```

- [ ] **Step 5: コミットして push する**

```bash
git add AGENTS.md RELEASING.md CONTRIBUTING.md
git commit -m "docs: AGENTS.md・RELEASING.md を追加し CONTRIBUTING にブランチ保護を明記

ブランチ保護（sensor）と対になる guide を置く。保護だけ入れると、push を
拒否されたエージェントが誤診して force push や保護解除を試みる。

RELEASING.md は v0.1.0 の手順をそのまま固定化し、実際に踏んだ偽シグナル
（npm registry の反映遅延・pnpm の no new packages の二重の意味・mooncakes
APIの判別不能・Pages緑でもデモが壊れうる点）を明記した。

ruleset の設定内容は CONTRIBUTING.md に転記した。GitHub側の設定はコードに
残らないため、記録がないと失われるため。"
git push -u origin docs/agent-guide-and-releasing
```

- [ ] **Step 6: テンプレートに沿って PR を作る（Task 2 の検証）**

`gh pr create` は Web UI と違い、テンプレートを本文へ自動挿入しない（`--body` を渡せばその内容がそのまま本文になる）。そのため検証は 2 つに分ける。

**(a) テンプレートが実用に耐えるかの検証** — この PR 自身をテンプレートに沿って書く。テンプレートを使う最初の実例になる。

```bash
gh pr create --title "docs: AGENTS.md・RELEASING.md を追加" --template pull_request_template.md
```

`--template` はエディタを開いてテンプレートを読み込む。埋める内容は次のとおり。

- Type of change: Documentation
- Provenance: 「Written by me」にチェック（移植も AI 生成コードも含まないため）
- Tests: ドキュメントのみの変更だがビルドに影響しないことを示すため `pnpm -r typecheck` を実行して貼る
- Checklist: 3 項目すべてにチェック

エディタを開きたくない場合は、テンプレートの内容を埋めたファイルを作って `--body-file` で渡してもよい。

**(b) Web UI で自動挿入されることの目視確認** — 外部コントリビュータが見る画面を実際に確認する。

```bash
gh pr create --web
```

ブラウザで新規 PR 画面が開き、本文にテンプレートが入っていることを目視する。確認したらブラウザを閉じ、(a) で作った PR をそのまま使う（この `--web` は確認専用で、PR は作らない）。

リポジトリ上にファイルが存在することの確認:

```bash
gh api repos/elchika-inc/moonqr/contents/.github/pull_request_template.md --jq '.name'
```

Expected: `pull_request_template.md`。

- [ ] **Step 7: CI 緑を確認してマージする**

```bash
gh pr checks --watch
gh pr merge --squash --delete-branch
```

- [ ] **Step 8: 最終確認**

```bash
git switch main && git pull
ls AGENTS.md RELEASING.md
grep -n "## Branch protection" CONTRIBUTING.md
gh api repos/elchika-inc/moonqr/rulesets --jq '.[] | "\(.name) \(.enforcement)"'
git status --short
```

Expected: 両ファイルが存在、CONTRIBUTING に節が入っている、ruleset が `active`、作業ツリーがクリーン（`.codex/` の untracked を除く）。

---

## 完了条件

- `main` へ直接 push すると拒否される（Task 1 Step 4 で実測済み）
- PR は CI（`test`）が緑になるまでマージできない（Task 2 Step 6-7 で実測済み）
- `.github/` に PR テンプレートと 3 種の Issue テンプレート設定が存在する
- `AGENTS.md` / `RELEASING.md` が存在し、`CONTRIBUTING.md` にブランチ保護の節がある
- ruleset が `active` である
