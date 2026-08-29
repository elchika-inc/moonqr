import { readFileSync } from "node:fs";
import { describe, it, expect } from "vitest";
import { run } from "../src/cli.js";

const noEnv = {} as NodeJS.ProcessEnv;
const packageJson = JSON.parse(
  readFileSync(new URL("../package.json", import.meta.url), "utf8"),
) as { version: string };

describe("run", () => {
  it("prints a QR to stdout and exits 0", () => {
    const r = run(["https://example.com"], noEnv);
    expect(r.code).toBe(0);
    expect(r.stderr).toBe("");
    expect(r.stdout).toContain("█");
  });

  it("colors output by default", () => {
    expect(run(["hi"], noEnv).stdout).toContain("\x1b[107m");
  });

  it("drops color with --no-color", () => {
    const r = run(["--no-color", "hi"], noEnv);
    expect(r.stdout).not.toContain("\x1b[");
    expect(r.code).toBe(0);
  });

  it("drops color when NO_COLOR is set", () => {
    const r = run(["hi"], { NO_COLOR: "1" } as NodeJS.ProcessEnv);
    expect(r.stdout).not.toContain("\x1b[");
  });

  it("does not consult isTTY", () => {
    // 設計上の決定: 端末かどうかで色を変えない。QR における背景色は装飾では
    // なく機能であり、落とすと端末テーマ次第で反転する。加えてエージェント
    // 経由の実行では isTTY が undefined になるため、自動判定は主用途で必ず
    // 裏目に出る。将来この判定が足されないようテストで固定する。
    expect(String(run)).not.toContain("isTTY");
  });

  it("accepts an error-correction level", () => {
    const r = run(["-e", "H", "hi"], noEnv);
    expect(r.code).toBe(0);
    expect(r.stdout).toContain("█");
  });

  it("rejects an invalid error-correction level", () => {
    const r = run(["-e", "Z", "hi"], noEnv);
    expect(r.code).toBe(1);
    expect(r.stderr).toContain("Z");
    expect(r.stdout).toBe("");
  });

  it("shows usage and exits 1 when given no text", () => {
    const r = run([], noEnv);
    expect(r.code).toBe(1);
    expect(r.stderr).toContain("Usage");
    expect(r.stdout).toBe("");
  });

  it("shows help on --help and exits 0", () => {
    const r = run(["--help"], noEnv);
    expect(r.code).toBe(0);
    expect(r.stdout).toContain("Usage");
  });

  it("reports the version declared in package.json", () => {
    const r = run(["--version"], noEnv);
    expect(r.code).toBe(0);
    expect(r.stderr).toBe("");
    expect(r.stdout).toBe(`${packageJson.version}\n`);
  });

  it("reports input that does not fit in a QR code", () => {
    // Model 2 の byte モード最大は 2953 バイト。確実に超える長さを渡す
    const r = run(["x".repeat(5000)], noEnv);
    expect(r.code).toBe(1);
    expect(r.stderr).toContain("too long");
    expect(r.stdout).toBe("");
  });
});
