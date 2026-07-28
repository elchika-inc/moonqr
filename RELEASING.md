# Releasing

Publishing is deliberately manual. npm's 2FA prompt is the human gate — there is no CI job that
can publish on its own, and that is by design.

Three registries are involved, published in this order:

1. `@elchika-inc/moonqr` (npm)
2. `@elchika-inc/moonqr-scanner` (npm) — depends on the above, so the order is not optional
3. `naoto24kawa/moonqr` (mooncakes.io) — the MoonBit source module

## 1. Preflight

```sh
gh api repos/elchika-inc/moonqr/rulesets --jq '.[] | "\(.name) \(.enforcement)"'
```

Expected: `main protection active`. If it says `disabled`, someone turned it off for an emergency
fix and did not turn it back on. Re-enable it before releasing (see the last section).

Confirm you are logged in to both registries:

```sh
npm whoami          # your npm username
moon whoami         # "Logged in as <user>"
```

## 2. Bump versions

All three carry the same version number:

- `packages/moonqr/package.json`
- `packages/scanner/package.json`
- `core/moon.mod.json`

Open a pull request for the bump like any other change — `main` is protected.

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

All layers must be green before anything is published.

## 4. Verify the tarballs before publishing

`pnpm pack` works even when a package is marked private, so you can inspect exactly what would be
uploaded without risking a publish.

```sh
pnpm --filter @elchika-inc/moonqr pack --pack-destination /tmp
pnpm --filter @elchika-inc/moonqr-scanner pack --pack-destination /tmp
tar tzf /tmp/elchika-inc-moonqr-*.tgz | sort
tar xzOf /tmp/elchika-inc-moonqr-scanner-*.tgz package/package.json | grep -A3 '"dependencies"'
```

Check that:

- Only `dist/`, `README.md`, `LICENSE`, `NOTICE`, and `THIRD_PARTY_LICENSES` are included — no
  sources, no tests, no configs.
- The scanner's dependency on the core reads as a real version (`^0.1.0`), not `workspace:^`.
  pnpm rewrites this automatically; verifying it is what proves the package works outside the
  monorepo.

## 5. Publish to npm

```sh
pnpm --filter @elchika-inc/moonqr publish --no-git-checks
pnpm --filter @elchika-inc/moonqr-scanner publish --no-git-checks
```

npm asks for a one-time password. That prompt is the human gate.

## 6. Verify from outside the repository

This step is what actually proves the release works. Running things inside the workspace proves
nothing: pnpm's workspace links hide broken dependency declarations.

```sh
mkdir /tmp/verify && cd /tmp/verify && npm init -y
npm install @elchika-inc/moonqr @elchika-inc/moonqr-scanner
node -e 'import("@elchika-inc/moonqr/encode").then(m => console.log(m.encode("HELLO", {ecLevel:"M"}).size))'
node -e 'console.log(typeof require("@elchika-inc/moonqr/encode").encode)'
```

Expect a module count (`21` for `HELLO`) from the ESM path and `function` from the CJS path. Both
matter — a broken `exports` map often fails in only one of them.

## 7. Publish to mooncakes

```sh
cd core
moon publish --dry-run   # exits non-zero even on success; look for "202 Accepted"
moon publish             # look for "200 OK"
```

Verify from outside the same way:

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

`README.md` and `site/` mention published versions and links. Update them in a pull request, then
confirm the Pages deploy succeeded **and** that the live page actually renders. A green workflow
is not proof that the page works.

## Signals that lie

These cost real time during the v0.1.0 release. Do not repeat them.

- **`npm view <pkg>` returning 404 right after publishing does not mean the publish failed.** The
  registry takes time to propagate. Check `https://registry.npmjs.org/<pkg>` directly and wait
  before concluding anything.
- **pnpm's `There are no new packages that should be published` has two meanings**: the version is
  already published (success), or the package still has `private: true` (nothing happened). The
  message is identical. Check `package.json` and the registry to tell them apart.
- **mooncakes' `api/v0/user/<user>/<mod>` returns `Not Found` whether or not the module is
  published.** It cannot verify a release. Use `moon add` from a scratch module instead.
- **A green Pages workflow does not mean the demo works.** The site resolves bare specifiers
  through an import map pointing at `./assets/`; one missing file makes the page fail to load
  entirely while the workflow still reports success.

## Emergency: fixing a broken `main`

Branch protection applies to administrators, so a broken `main` cannot be fixed with a direct
push. If a pull request is genuinely not viable:

```sh
gh api repos/elchika-inc/moonqr/rulesets/19899601 -X PUT -f enforcement=disabled
# fix main
gh api repos/elchika-inc/moonqr/rulesets/19899601 -X PUT -f enforcement=active
```

The partial update preserves the rules — verified by round-tripping it when the ruleset was
created: after `disabled`, all four rules (`deletion`, `non_fast_forward`, `pull_request`,
`required_status_checks`) were still present, and re-enabling restored the protection (a direct
push to `main` was rejected again).

Re-enabling is the step that gets forgotten. The preflight check in step 1 exists to catch it.
