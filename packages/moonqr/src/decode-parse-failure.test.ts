// decode() の防御的分岐（JSON.parse 失敗 → null）のカバレッジ。
//
// 実際の MoonBit `decode_js` は常に妥当な JSON か空文字列しか返さない契約のため、
// この分岐は結合テストでは到達できない。`./core-decode.js` をモックして
// 「壊れた JSON を返す decodeJs」を注入し、decode() が例外を投げず null を返すことを固定する。
//
// `vi.mock` はファイル単位でホイストされるため、実物の decodeJs を使う decode.test.ts とは
// 別ファイルに分離している（同一ファイル内でモックと実物を混在させられない）。
import { describe, expect, it, vi } from "vitest";

const decodeJs = vi.fn();
vi.mock("./core-decode.js", () => ({
  decodeJs: (...args: unknown[]) => decodeJs(...args),
}));

const { decode } = await import("./decode.js");

const DATA = new Uint8Array(5 * 5 * 4);

describe("decode: JSON.parse failure branch", () => {
  it("returns null (never throws) when decodeJs returns malformed JSON", () => {
    decodeJs.mockReturnValue("{ not valid json");
    expect(() => decode(DATA, 5, 5)).not.toThrow();
    expect(decode(DATA, 5, 5)).toBeNull();
  });

  it("returns null when decodeJs returns valid JSON of an unexpected shape", () => {
    decodeJs.mockReturnValue('{"text":123}');
    expect(decode(DATA, 5, 5)).toBeNull();
  });

  it("returns null when decodeJs returns a JSON scalar", () => {
    decodeJs.mockReturnValue("42");
    expect(decode(DATA, 5, 5)).toBeNull();
  });

  it("still returns a DecodeResult for a well-formed payload (mock sanity)", () => {
    decodeJs.mockReturnValue(
      JSON.stringify({
        text: "OK",
        bytes: [79, 75],
        version: 2,
        ecLevel: "M",
        corners: [
          { x: 1, y: 2 },
          { x: 3, y: 4 },
          { x: 5, y: 6 },
          { x: 7, y: 8 },
        ],
      }),
    );
    const result = decode(DATA, 5, 5);
    expect(result?.text).toBe("OK");
    expect(result?.bytes).toBeInstanceOf(Uint8Array);
    expect(result?.corners).toHaveLength(4);
  });
});
