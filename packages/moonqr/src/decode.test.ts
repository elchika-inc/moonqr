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
