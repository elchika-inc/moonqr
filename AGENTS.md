# moonqr

Written for AI coding agents. Human contributors: read [CONTRIBUTING.md](CONTRIBUTING.md) — it
covers the same ground with more context.

This file follows an internal `AGENTS.md` contract. The contract itself lives in a private
repository, so the `standards_version` below is recorded as a plain value rather than a link, and
the corresponding README badge is omitted: a badge linking into a private repository reads as a
broken link to everyone outside it.

## Project Overview

QR code encoder and decoder written in MoonBit, compiled to plain JavaScript and shipped as
zero-dependency npm packages. See [README.md](README.md) for the user-facing description,
[bench/RESULT.md](bench/RESULT.md) for the measurements behind every number quoted in the docs,
and [RELEASING.md](RELEASING.md) for how a release is cut.

Working documents live under `.docs/`:

- [`.docs/PROJECT_GOAL.md`](.docs/PROJECT_GOAL.md) — what this builds, and the criteria it has to meet
- [`.docs/plans/`](.docs/plans/) — design documents and implementation plans (`*-design.md` / `*-plan.md`)
- [`.docs/risk-registry.md`](.docs/risk-registry.md) — risks accepted on purpose, with the reasoning
- [`.docs/actions/`](.docs/actions/) — queued work for a later session

**Write design documents and implementation plans to `.docs/plans/`, not to a tool-specific
directory.** Some agent tooling defaults to `docs/<tool>/specs/` or similar; those paths are
gitignored here, so anything written there is invisible to everyone reading the repository. One
location, tracked in git.

## Tech Stack

- MoonBit (`core/`, compiled with `moon build --target js`) + TypeScript packages bundled by tsup.
- pnpm workspace. Node.js 18.18+.
- Not the standard Cloudflare web-service stack — this is a published library, so there is no app,
  no database, and no deploy target beyond npm / mooncakes.io / GitHub Pages.
- standards_version: 2026-08-15 (rev.71).
- branch_policy: protected — `main` requires a pull request and a passing `test` check, with an
  empty bypass list, so the rule applies to administrators as well. An agent and its operator
  share one GitHub token, so a bypass for administrators would also be a bypass for the agent.

## Key Commands

Every command assumes the MoonBit toolchain is on `PATH`: `export PATH="$HOME/.moon/bin:$PATH"`.

- build: `cd core && moon build --target js --release && cd .. && pnpm -r build` — **order matters**, see
  Architecture below.
- test: `cd core && moon test --target js` (MoonBit), `node --test packages/moonqr/test/*.test.mjs`
  (jsQR parity + encoder sweep), `pnpm -r test:unit` (vitest, all packages).
- check: `pnpm -r typecheck`.
- fixtures: `node scripts/fetch-fixtures.mjs` — required once before the parity test; downloads the
  jsQR corpus at a pinned commit and caches it.
- site: `node scripts/build-site.mjs` — regenerates `site/assets/` from the built packages.
- release: manual, see [RELEASING.md](RELEASING.md).

## Architecture

- `core/` — MoonBit source: encoder, decoder, Reed–Solomon, binarization, locator, extractor.
  Compiles to JavaScript under `core/_build/`.
- `packages/moonqr/` — TypeScript wrapper. tsup **inlines** the core's JavaScript output, so the
  core must be built first or the packages get stale or missing code. `core/_build/` is gitignored
  but required; a clean checkout builds nothing useful until the core is built.
- `packages/scanner/` — camera scanner built on the above, decode loop in a Web Worker.
- `site/` — the GitHub Pages demo. Resolves bare specifiers through an import map pointing at
  `./assets/`; a single missing file makes the page fail to load while the workflow still reports
  success.
- `bench/` — measurement harnesses and `RESULT.md`, the source of every performance claim.

## 重要な設計原則（What NOT to Do）

- **Never push to `main`.** It is rejected by the ruleset. Work on a branch and open a pull
  request. If a push is rejected, that is the protection working — do not force push, do not
  disable the ruleset, and do not try to "fix" it.
- **Never run `moon fmt`.** On some toolchain versions it starts a repo-wide MoonBit config
  migration (`moon.mod.json` → `moon.mod` and similar) that rewrites unrelated files. Format
  MoonBit code by hand to match the surrounding style.
- **Never build the TypeScript packages without building the core first.** The failure is silent:
  you get a stale bundle, not an error.
- **Do not reproduce code from other projects without attribution.** Parts of the decoder are
  ported from [jsQR](https://github.com/cozmo/jsQR) (Apache-2.0) and the Reed–Solomon block /
  alignment-pattern tables are derived from
  [qrcode-generator](https://github.com/kazuhikoarase/qrcode-generator) (MIT). Anything ported —
  including code you generate — needs attribution in `NOTICE` and `THIRD_PARTY_LICENSES`, and the
  provenance stated in the pull request. The PR template asks for it.
- **Do not hand-edit generated MoonBit files.** `core/src/encode/tables.mbt` and
  `core/src/decode/sjis.mbt` are generated by `scripts/gen-tables.mjs` and `scripts/gen-sjis.mjs`
  from pinned upstream commits. Change the generator and regenerate.
- **Do not trust a green workflow as proof that something works.** A passing Pages deploy does not
  mean the demo renders, and `npm view` returning 404 right after a publish does not mean the
  publish failed. `RELEASING.md` lists the signals that lie.

## エージェント連携

- dev-data-safety: local — there is no shared environment, database, or deploy target. All
  verification runs locally or in CI.
- Publishing is the only irreversible outward action, it is manual by design, and it requires a
  human at the npm 2FA prompt. Do not attempt to automate it.
