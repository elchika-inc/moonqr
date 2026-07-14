# Security Policy

## Supported versions

moonqr is pre-1.0 (`0.x`). Only the **latest published version** of each package
(`@elchika-inc/moonqr`, `@elchika-inc/moonqr-scanner`) is supported with security fixes. There
is no backport policy for older `0.x` releases — please upgrade to the latest version before
reporting an issue.

## Reporting a vulnerability

Please **do not open a public GitHub issue** for suspected security vulnerabilities. Instead,
use GitHub's private vulnerability reporting:

**https://github.com/elchika-inc/moonqr/security/advisories/new**

This lets us discuss and fix the issue before it's public. Please include:

- The package and version affected.
- A minimal reproduction (ideally the exact input image/bytes that trigger the issue).
- What you expected vs. what happened.

This is a small project maintained on a best-effort basis. We aim to acknowledge new reports
within **7 days**, but cannot commit to a fixed resolution timeline.

## Scope

`decode()` parses untrusted input by design — camera frames, user-uploaded images, arbitrary
byte buffers — and is written to be **total**: on malformed or hostile input it returns `null`,
it never throws. Malformed QR data, corrupted images, and adversarially crafted bitstreams are
expected inputs, not exceptional ones — Reed–Solomon decoding, format/version info parsing, and
segment/data decoding all reject invalid input rather than assuming it's well-formed.

Given that, `decode()` returning `null` (or an incorrect decode) on bad input is normal
behavior, **not** a security issue by itself. What **would** be a security issue is a crafted
image or byte buffer that causes something other than a clean `null` — for example:

- A hang or unbounded loop.
- Unbounded memory growth / OOM.
- A crash or panic instead of a `null` return.

If you find an input that triggers any of the above, that's exactly the kind of report we want
via private reporting above.

`encode()` takes trusted, application-controlled input (text to encode) and is out of scope for
adversarial-input concerns, though correctness bugs there are still welcome as regular issues.
