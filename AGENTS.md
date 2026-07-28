# Notes for AI coding agents

Human contributors: read [CONTRIBUTING.md](CONTRIBUTING.md) instead. This file covers the things
agents specifically get wrong in this repository.

## `main` is protected — never commit to it directly

`main` requires a pull request and a green CI run, and the protection applies to administrators
too. A direct push will be rejected.

This is deliberate. An agent and its human operator share the same GitHub token, so GitHub cannot
tell them apart — protection that administrators could bypass would not protect anything.

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

Code you generate must not reproduce code from other projects without attribution in `NOTICE` and
`THIRD_PARTY_LICENSES`. State the provenance in the pull request description — the PR template
asks for it.

## Releasing

Follow [RELEASING.md](RELEASING.md). Publishing is deliberately manual and requires a human.
