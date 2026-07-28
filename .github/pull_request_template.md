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
non-trivial parts of this change came from — check all that apply.

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
