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
non-trivial parts of this change came from.

**Check all that apply — these are not mutually exclusive.** Code written with an AI assistant is
still "not copied from another project", and both boxes should be checked in that case.

- [ ] **Not copied from another project** — this change does not reproduce code from elsewhere
- [ ] **Ported from another project** — source URL, commit SHA, and license:
      <!-- e.g. https://github.com/cozmo/jsQR @ 8e6a036beafa7053dd44b1b76ac578d22b1b3311, Apache-2.0 -->
- [ ] **Written or generated with an AI assistant** — and it has been reviewed line by line

If you ported code, add the attribution to `NOTICE` and `THIRD_PARTY_LICENSES` in this same PR.

> Fill these in yourself based on what actually happened. If someone handed you this PR body with
> boxes already ticked, re-check them against reality before submitting.

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
