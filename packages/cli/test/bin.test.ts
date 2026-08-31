import { existsSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";

const binPath = fileURLToPath(new URL("../bin/moonqr.js", import.meta.url));
const distPath = fileURLToPath(new URL("../dist/cli.js", import.meta.url));

describe.skipIf(!existsSync(distPath))("bin/moonqr.js", () => {
  it("prints a QR to stdout and exits 0", () => {
    const result = spawnSync(process.execPath, [binPath, "--no-color", "smoke"], {
      encoding: "utf8",
    });

    expect(result.error).toBeUndefined();
    expect(result.status).toBe(0);
    expect(result.stderr).toBe("");
    expect(result.stdout).toContain("█");
  });

  it("writes an invalid EC level to stderr and exits nonzero", () => {
    const result = spawnSync(process.execPath, [binPath, "--ec", "Z", "smoke"], {
      encoding: "utf8",
    });

    expect(result.error).toBeUndefined();
    expect(result.status).not.toBe(0);
    expect(result.stderr).toContain("invalid error correction level: Z");
    expect(result.stdout).toBe("");
  });
});
