import { describe, it, expect } from "vitest";
import { encode } from "@elchika-inc/moonqr/encode";
import { render } from "../src/render.js";

const matrix = () => {
  const m = encode("HELLO", { ecLevel: "M" });
  if (!m) throw new Error("encode failed");
  return m;
};

const contentLines = (out: string) => out.split("\n").filter((l) => l.length > 0);

describe("render", () => {
  it("packs two module rows into one character cell", () => {
    const m = matrix(); // v1 = 21x21
    const lines = contentLines(render(m, { color: false }));
    // 静穏帯 4 モジュール × 2 辺 = 8 を足し、縦は 2 行で 1 セル
    expect(lines.length).toBe(Math.ceil((m.size + 8) / 2));
  });

  it("adds a 4-module quiet zone on every side", () => {
    const lines = contentLines(render(matrix(), { color: false }));
    // 上 4 モジュール = 2 行分が空白のみ
    expect(lines[0]!.trim()).toBe("");
    expect(lines[1]!.trim()).toBe("");
    // 各行の左端 4 文字が空白（左の静穏帯）
    for (const line of lines) {
      expect(line.slice(0, 4)).toBe("    ");
    }
  });

  it("emits no ANSI escapes when color is disabled", () => {
    expect(render(matrix(), { color: false })).not.toContain("\x1b[");
  });

  it("wraps every line with bright-white background and black foreground when color is enabled", () => {
    const out = render(matrix(), { color: true });
    // 47m ではなく 107m（bright white）を使う。47m は端末でグレーになる
    expect(out).toContain("\x1b[107m");
    expect(out).toContain("\x1b[30m");
    expect(out).toContain("\x1b[0m");
    expect(out).not.toContain("\x1b[47m");
  });

  it("defaults to color enabled", () => {
    expect(render(matrix())).toContain("\x1b[107m");
  });

  it("uses the half-block mapping for module pairs", () => {
    const lines = contentLines(render(matrix(), { color: false }));
    // 左上ファインダパターンの角は上下とも暗いモジュールなので全ブロックになる。
    // 静穏帯 4 モジュール = 2 行の後、左から 5 文字目（index 4）がその位置。
    expect(lines[2]![4]).toBe("█");
  });
});
