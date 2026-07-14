import { describe, it, expect } from "vitest";
import { encode, toSvgString } from "./index.js";

describe("encode", () => {
  it("encodes and auto-selects version", () => {
    const m = encode("01234567")!;
    expect(m.size).toBe(21); // v1
    expect(typeof m.get(0, 0)).toBe("boolean");
    expect(m.get(0, 0)).toBe(true); // TL ファインダ左上は黒
    expect(m.get(1, 1)).toBe(false); // 白リング
  });
  it("honors ecLevel and version", () => {
    const m = encode("HI", { ecLevel: "H", version: 5 })!;
    expect(m.size).toBe(37); // v5
  });
  it("returns null on empty text", () => expect(encode("")).toBeNull());
  it("returns null on capacity overflow", () =>
    expect(encode("A".repeat(5000), { ecLevel: "H", version: 1 })).toBeNull());
  it("returns null on invalid version", () => expect(encode("HI", { version: 41 })).toBeNull());
  it("returns null on invalid ecLevel (non-TS caller)", () =>
    // biome-ignore: 型を無視した不正呼び出しを意図的に検証する
    expect(encode("HI", { ecLevel: "X" as any })).toBeNull());
  it("get() is bounds-safe", () => {
    const m = encode("HI")!;
    expect(m.get(-1, 0)).toBe(false);
    expect(m.get(999, 0)).toBe(false);
  });
});

describe("toSvgString", () => {
  it("produces valid svg with expected viewBox", () => {
    const m = encode("HI")!;
    const svg = toSvgString(m, { margin: 4, cell: 10 });
    expect(svg).toContain("<svg");
    expect(svg).toContain(`viewBox="0 0 ${(m.size + 8) * 10} ${(m.size + 8) * 10}"`);
    expect(svg).toContain("</svg>");
  });

  it("uses default margin/cell when options are omitted", () => {
    const m = encode("HI")!;
    const svg = toSvgString(m);
    expect(svg).toContain(`viewBox="0 0 ${(m.size + 8) * 4} ${(m.size + 8) * 4}"`);
  });

  it("draws no modules for an all-false matrix (still valid svg)", () => {
    const empty = { size: 3, get: () => false };
    const svg = toSvgString(empty);
    expect(svg).toContain('<path d=""');
  });
});
