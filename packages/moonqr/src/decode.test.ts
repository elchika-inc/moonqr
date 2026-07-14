import { describe, it, expect } from "vitest";
import { decode } from "./decode.js";
import { encodeJs } from "./core-encode.js";
import { rasterize } from "../test/lib/rasterize.mjs";

const EC = { L: 0, M: 1, Q: 2, H: 3 } as const;

describe("decode", () => {
  it("roundtrips a clean rasterized QR", () => {
    const flat = encodeJs("HELLO DECODE", EC.M, 2);
    expect(flat.length).not.toBe(0);
    const { data, width, height } = rasterize(flat, { scale: 4, margin: 4 });
    const result = decode(data, width, height);
    expect(result).not.toBeNull();
    expect(result?.text).toBe("HELLO DECODE");
    expect(result?.version).toBe(2);
    expect(result?.ecLevel).toBe("M");
  });

  it("roundtrips after a 90 degree rotation", () => {
    const flat = encodeJs("ROTATE ME", EC.M, 2);
    const { data, width, height } = rasterize(flat, { scale: 4, margin: 4, rotate: 90 });
    const result = decode(data, width, height);
    expect(result).not.toBeNull();
    expect(result?.text).toBe("ROTATE ME");
  });

  it("returns bytes as a Uint8Array matching the decoded text", () => {
    const flat = encodeJs("BYTES", EC.M, 2);
    const { data, width, height } = rasterize(flat, { scale: 4, margin: 4 });
    const result = decode(data, width, height);
    expect(result).not.toBeNull();
    expect(result?.bytes).toBeInstanceOf(Uint8Array);
    const asText = Array.from(result?.bytes ?? [])
      .map((b) => String.fromCharCode(b))
      .join("");
    expect(asText).toBe("BYTES");
  });

  it("returns corners as a 4-point tuple", () => {
    const flat = encodeJs("CORNERS", EC.M, 2);
    const { data, width, height } = rasterize(flat, { scale: 4, margin: 4 });
    const result = decode(data, width, height);
    expect(result).not.toBeNull();
    expect(result?.corners).toHaveLength(4);
    for (const p of result?.corners ?? []) {
      expect(typeof p.x).toBe("number");
      expect(typeof p.y).toBe("number");
    }
  });

  it("fails to read an inverted image with invert:false, succeeds with invert:true", () => {
    const flat = encodeJs("INVERT ME", EC.M, 2);
    const { data, width, height } = rasterize(flat, {
      scale: 4,
      margin: 4,
      black: 220,
      white: 30,
    });
    expect(decode(data, width, height, { invert: false })).toBeNull();
    const result = decode(data, width, height, { invert: true });
    expect(result).not.toBeNull();
    expect(result?.text).toBe("INVERT ME");
  });

  it("tries the inverted orientation automatically when options are omitted (default invert=true)", () => {
    const flat = encodeJs("DEFAULT INVERT", EC.M, 2);
    const { data, width, height } = rasterize(flat, {
      scale: 4,
      margin: 4,
      black: 220,
      white: 30,
    });
    const result = decode(data, width, height);
    expect(result).not.toBeNull();
    expect(result?.text).toBe("DEFAULT INVERT");
  });

  it("accepts a Uint8ClampedArray view without copying the underlying buffer", () => {
    const flat = encodeJs("CLAMPED", EC.M, 2);
    const { data, width, height } = rasterize(flat, { scale: 4, margin: 4 });
    const clamped = new Uint8ClampedArray(data.buffer, data.byteOffset, data.byteLength);
    const result = decode(clamped, width, height);
    expect(result).not.toBeNull();
    expect(result?.text).toBe("CLAMPED");
  });

  it("returns null for invalid input (data.length !== width*height*4)", () => {
    const bad = new Uint8Array(10); // 10 !== 5*5*4
    expect(decode(bad, 5, 5)).toBeNull();
  });

  // --- totality 契約: decode は「いかなる入力でも」例外を投げず DecodeResult|null を返す。
  // MoonBit 側 decode_js は width/height を BigInt(width) に通すため、NaN/小数/Infinity が
  // 境界を越えると RangeError で throw する（`width <= 0` ガードは NaN 比較が常に false に
  // なるためすり抜ける）。data が null/undefined なら `data.length` 参照で TypeError。
  // 小数の width は `canvas.width * devicePixelRatio` 等で現実に発生しうる経路であり、
  // Task 6 の scanner がホストアプリを未捕捉例外でクラッシュさせる。JS 呼び出し元は型で
  // 守られないため、境界の手前で全て null に倒す。
  const INVALID_DIMENSIONS: Array<[string, unknown, unknown]> = [
    ["NaN", Number.NaN, Number.NaN],
    ["fractional (2.5)", 2.5, 2.5],
    ["Infinity", Number.POSITIVE_INFINITY, Number.POSITIVE_INFINITY],
    ["negative", -1, -1],
    ["zero", 0, 0],
  ];
  it.each(INVALID_DIMENSIONS)(
    "returns null (never throws) for %s width/height",
    (_label, width, height) => {
      const data = new Uint8Array(100);
      expect(() =>
        decode(data, width as number, height as number),
      ).not.toThrow();
      expect(decode(data, width as number, height as number)).toBeNull();
    },
  );

  it.each([
    ["null", null],
    ["undefined", undefined],
  ])("returns null (never throws) for %s data", (_label, data) => {
    expect(() => decode(data as unknown as Uint8Array, 5, 5)).not.toThrow();
    expect(decode(data as unknown as Uint8Array, 5, 5)).toBeNull();
  });

  it("returns null for garbage (non-QR) pixel data", () => {
    const width = 50;
    const height = 50;
    const data = new Uint8Array(width * height * 4);
    for (let i = 0; i < data.length; i++) {
      data[i] = (i * 37) % 256;
    }
    expect(decode(data, width, height)).toBeNull();
  });
});
