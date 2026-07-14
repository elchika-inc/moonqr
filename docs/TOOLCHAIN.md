# MoonBit toolchain: pinning, why it's hard, and how to upgrade

## Verified-good version

```
moon 0.1.20260703 (6fbf8c3 2026-07-03)
```

This is the toolchain `core/` was developed and last verified against (98/98 `moon test`
passing). Treat it as the baseline for any toolchain-related CI/local debugging.

## Why CI isn't pinned to that exact version

Both `.github/workflows/ci.yml` and `.github/workflows/pages.yml` install MoonBit with:

```sh
curl -fsSL https://cli.moonbitlang.com/install/unix.sh | bash
```

`unix.sh` *does* accept a version argument / `MOONBIT_INSTALL_VERSION` env var
(`version=${ARGUMENTS[0]:-${MOONBIT_INSTALL_VERSION:-latest}}`), which looks like a working
pin mechanism. **It is not, in practice**: the CDN it downloads from
(`cli.moonbitlang.com`, an S3 bucket behind CloudFront) only serves the `latest` and
`nightly` channel aliases. It does not retain dated/versioned builds.

Verified on 2026-07-14 by requesting the binary and core tarballs directly:

```sh
curl -sI https://cli.moonbitlang.com/binaries/0.1.20260703/moonbit-linux-x86_64.tar.gz
# HTTP/2 403 (S3 "key not found", surfaced via CloudFront)
```

Every dated version tried returned 403 — including `0.1.20260703` itself (the target pin),
every date from `0.1.20260704` through `0.1.20260712`, and even `0.1.20260713`, which was
*that day's own `latest`* requested by its dated name a few hours after being published.
Only the literal strings `latest` and `nightly` resolved (`bleeding`/`stable`/`release` also
403). There is also no official `moonbitlang/moonbit` Docker image with version tags
(`hub.docker.com/v2/repositories/moonbitlang/moonbit/tags` returns zero results) that could
serve as an alternate pinned distribution channel.

**Conclusion: there is currently no supported way to install a specific historical MoonBit
version in CI (or anywhere) once it's no longer `latest`.** `unix.sh`'s version argument only
makes sense for switching between the `latest`/`nightly` channels, not for reproducible
pinning to a dated build.

As a secondary check: `latest` as of 2026-07-13/14 (`0.1.20260713`) was installed and run
against `core/`'s test suite. It fails with the *same* class of error as the original CI
failure (`assert_eq` requiring `Debug` instead of `Show`), now on more types
(`Mode`, `EcLevel`, ...). So even if version pinning worked, there is no currently-fetchable
toolchain version that both (a) is obtainable via the installer and (b) passes the existing
test suite unmodified. Getting CI green again requires either recovering an old binary from
some other source, or migrating the code (see below) — pinning the install command alone
cannot do it.

## What we did instead (this fix)

Since we can't pin by version string, CI caches the *installed toolchain directory*
(`~/.moon`) via `actions/cache`, keyed on a string we control
(`moonbit-toolchain-<os>-2026-07-14`). This doesn't recover the old version, but it stops
the toolchain from silently changing on every single CI run — it only changes when someone
deliberately bumps the cache key (e.g. after validating a newer toolchain locally, per the
upgrade procedure below). CI also now prints `moon version` in the log so a version change is
visible at a glance instead of showing up only as a mysterious new failure.

If you find a legitimate way to obtain the actual `0.1.20260703` Linux binaries (e.g. someone
still has them cached locally, or MoonBit adds real historical retention), replacing the cache
with a genuine pin (self-hosted release asset, or a fixed installer URL) would be strictly
better than the cache-key workaround above — revisit this doc if that becomes possible.

## Known blockers to upgrading past `0.1.20260703`

The newer `moonbitlang/core` requires the `Debug` trait where `Show` used to be enough for
`assert_eq`, plus some now-deprecated APIs:

- `assert_eq(a, b)` now requires both operands to implement `@moonbitlang/core/debug.Debug`,
  not just `Show`. Every custom type used in an `assert_eq` (seen so far: `EcLevel`, `Mode`,
  and likely others across `core/src/**/*_test.mbt`) needs a `Debug` impl (or
  `derive(Debug)` alongside/instead of `derive(Show)`).
- `Bytes::from_fixedarray` is deprecated in favor of `Bytes::from_array` (warning today,
  will presumably become an error on some future toolchain).
- `derive(Show)` itself is deprecated in favor of `derive(Debug)` (see the warnings already
  present in `moon test` output even on `0.1.20260703`).

## Upgrade procedure

1. Pick a target toolchain (realistically: whatever `latest` currently is, since dated
   pinning doesn't work — see above).
2. Install it locally and run `cd core && moon test --target js` to see the actual current
   error/warning list (`Debug` requirements may have expanded further since this doc was
   written).
3. Fix all resulting errors (add `Debug` impls / `derive(Debug)`, replace
   `Bytes::from_fixedarray` with `Bytes::from_array`, etc.) across all touched files in one
   PR — this is a real code change, not a CI config change, and needs its own review pass
   (all 4 test layers per `CONTRIBUTING.md`, not just `moon test`).
4. Once green locally, update the "verified-good version" at the top of this file, and bump
   the `actions/cache` key (e.g. `moonbit-toolchain-<os>-<new-date>`) in both
   `.github/workflows/ci.yml` and `.github/workflows/pages.yml` in the same commit, so the
   cache doesn't keep serving the old broken-for-the-new-code toolchain.
