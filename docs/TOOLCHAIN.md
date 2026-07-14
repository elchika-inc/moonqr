# MoonBit toolchain: pinning, why it's hard, and how to upgrade

## Verified-good version

```
moon 0.1.20260713 (75c7e1f 2026-07-13)
```

This is the toolchain `core/` is currently developed and verified against (98/98 `moon test`
passing, zero warnings). It was `latest` on 2026-07-14, the day this migration landed. Treat
it as the baseline for any toolchain-related CI/local debugging — but see the next section
before assuming it will still be installable by the time you read this.

## Why CI isn't pinned to an exact version string

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

Every dated version tried returned 403 — including `0.1.20260703` (the toolchain this repo
was originally developed on, before the migration below), every date from `0.1.20260704`
through `0.1.20260712`, and even `0.1.20260713`, which was *that day's own `latest`*
requested by its dated name a few hours after being published. Only the literal strings
`latest` and `nightly` resolved (`bleeding`/`stable`/`release` also 403). There is also no
official `moonbitlang/moonbit` Docker image with version tags
(`hub.docker.com/v2/repositories/moonbitlang/moonbit/tags` returns zero results) that could
serve as an alternate pinned distribution channel.

**Conclusion: there is currently no supported way to install a specific historical MoonBit
version in CI (or anywhere) once it's no longer `latest`.** `unix.sh`'s version argument only
makes sense for switching between the `latest`/`nightly` channels, not for reproducible
pinning to a dated build.

## What we do instead: track latest, migrate code when it breaks

Since a real version pin isn't available, this repo's policy is:

1. CI always installs whatever `latest` is (no version argument passed to the installer).
2. `.github/workflows/ci.yml` / `pages.yml` cache the installed toolchain directory
   (`~/.moon`) via `actions/cache`, keyed on the moon version this repo has actually been
   verified against (e.g. `moonbit-toolchain-<os>-0.1.20260713`). **This is a build-speed
   cache, not a version pin** — it exists only to skip the ~30s download/install on every CI
   run between deliberate upgrades. It does not, and is not meant to, protect against
   `latest` drifting further after the cached version — when that happens the fix is the
   upgrade procedure below, not trying to hold onto the cached build forever.
3. CI also prints `moon version` in the log unconditionally, so a toolchain version change
   (whether from a deliberate cache-key bump or a first-ever cache miss) is visible at a
   glance in the run log instead of showing up only as a mysterious new failure.
4. When `latest` moves and breaks `core/` (as it did going from `0.1.20260703` to
   `0.1.20260713`, requiring the `Debug`-trait and deprecated-API migration below), **the fix
   is to migrate the code to the new toolchain, not to try to pin the old one** — pinning the
   old one is not achievable (see above). This is an accepted tradeoff of building on a
   pre-1.0 language: staying buildable requires periodically following upstream forward.

If you find a legitimate way to obtain historical MoonBit binaries by version (e.g. someone
still has them cached locally, or MoonBit adds real historical retention / a tagged Docker
image), that would let CI genuinely pin instead of just caching-with-manual-bump — revisit
this doc if that becomes possible.

## 2026-07-14 migration: `0.1.20260703` → `0.1.20260713`

The previous verified-good version (`0.1.20260703`) stopped being installable (403, see
above), forcing a move to whatever was then `latest` (`0.1.20260713`). That newer
`moonbitlang/core` changed `assert_eq`'s bound and deprecated several APIs `core/` used.
Everything below was fixed in the same commit that bumped the toolchain, with **no algorithm
or assertion changes** — purely mechanical toolchain-compatibility updates:

- **`assert_eq` now requires `@moonbitlang/core/debug.Debug`, not just `Show`.** Every custom
  type compared via `assert_eq` needs `derive(Debug)`. Per
  [`moonbitlang/core`'s debug README](https://github.com/moonbitlang/core/blob/main/debug/README.mbt.md):
  "Use `derive(Debug)` for custom types. Implement `Show` manually only for non-debug textual
  formats such as JSON, XML, or domain-specific display text." None of this repo's types
  (`Mode`, `EcLevel`, `FormatInfo`, `DecodedData`) are used for JSON/XML/display formatting,
  so `derive(Eq, Show)` was replaced outright with `derive(Eq, Debug)` in:
  `core/src/encode/segment.mbt` (`Mode`), `core/src/encode/tables.mbt` (`EcLevel`, also
  regenerated from `scripts/gen-tables.mjs` — updated the generator too so regeneration
  doesn't reintroduce `Show`), `core/src/decode/info.mbt` (`FormatInfo`),
  `core/src/decode/data.mbt` (`DecodedData`). One test (`info_test.mbt`) used `\{ec}` string
  interpolation in an `abort()` diagnostic message, which needs `Show`, not `Debug`; since it
  was a debug-only message, it was rewritten to interpolate the loop index instead of the
  `EcLevel` value, avoiding the need to keep `Show` around just for that.
- **`Bytes::from_fixedarray` → `Bytes::from_array`.** The new signature takes an
  `ArrayView[Byte]` instead of `FixedArray[Byte]`; `FixedArray` supports `[:]` slicing into a
  view, so all 11 call sites became `Bytes::from_array(buf[:])`.
- **`Char::from_int` → `Int::unsafe_to_char`.** Both compile to the same intrinsic
  (`%char_from_int`); this is a pure rename with identical semantics (no validation either
  way). 11 call sites in `core/src/decode/data.mbt`.
- **`not(x)` → `!x`** (`core/src/encode/assemble.mbt`).
- **`fn meth(self : Type, ..)` method syntax → `fn Type::meth(self : Type, ..)`**
  (`core/src/encode/matrix.mbt`: `get`, `set`, `is_function`, `set_function`).
- **`BytesView::to_bytes()` → `BytesView::to_owned()`** (`core/src/decode/decode_test.mbt`).

Result: `moon test --target js` in `core/` is 98/98 passing with **zero warnings** (down from
14 errors + ~40 deprecation warnings on `0.1.20260713` before this migration). The jsQR e2e
parity corpus (`packages/moonqr/test/jsqr-parity.test.mjs`) still resolves 214/214 ground-truth
cases — the migration did not change decode behavior.

## Upgrade procedure (for the next time `latest` breaks `core/`)

1. Pick a target toolchain (realistically: whatever `latest` currently is, since dated
   pinning doesn't work — see above).
2. Install it locally (`curl -fsSL https://cli.moonbitlang.com/install/unix.sh | bash`) and
   run `cd core && moon test --target js` to see the actual current error/warning list
   (`Debug` requirements and deprecated APIs may have expanded further since this doc was
   written).
3. Fix all resulting errors (add `derive(Debug)`, replace deprecated APIs, etc.) across all
   touched files in one PR — this is a real code change, not a CI config change, and needs
   its own review pass (all 4 test layers per `CONTRIBUTING.md`, not just `moon test`).
4. Once green locally, update the "verified-good version" at the top of this file and in
   `CONTRIBUTING.md`, and bump the `actions/cache` key (e.g.
   `moonbit-toolchain-<os>-<new-moon-version>`) in both `.github/workflows/ci.yml` and
   `.github/workflows/pages.yml` in the same commit, so the cache doesn't keep serving the
   old broken-for-the-new-code toolchain.
