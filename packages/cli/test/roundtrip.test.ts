/**
 * 描画した文字列が「本当に読める QR」であることを機械的に検証する。
 *
 * 端末出力は目視でしか確認できないと思われがちだが、ブロック文字と上下 2
 * モジュールの対応規則が決まっているため、出力文字列から論理行列を復元できる。
 * 復元した行列を画素へ展開してデコーダに通せば、「見た目は QR に見えるが 1
 * モジュールずれている」類の不具合を CI で検出できる。
 */
import { describe, it, expect } from "vitest";
import { encode } from "@elchika-inc/moonqr/encode";
import { decode } from "@elchika-inc/moonqr/decode";
import { render } from "../src/render.js";

/** render の出力（色なし）から論理行列を復元する */
function parse(rendered: string): boolean[][] {
  const lines = rendered.split("\n").filter((l) => l.length > 0);
  const width = lines[0]!.length;
  const rows: boolean[][] = [];
  for (const line of lines) {
    const top: boolean[] = [];
    const bottom: boolean[] = [];
    for (let x = 0; x < width; x++) {
      const c = line[x];
      top.push(c === "█" || c === "▀");
      bottom.push(c === "█" || c === "▄");
    }
    rows.push(top, bottom);
  }
  return rows;
}

/** 論理行列を 4px/セルの RGBA へ展開する */
function rasterize(rows: boolean[][]): { data: Uint8ClampedArray; size: number } {
  const CELL = 4;
  const h = rows.length;
  const w = rows[0]!.length;
  const px = Math.max(w, h) * CELL;
  const data = new Uint8ClampedArray(px * px * 4).fill(255);
  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      if (!rows[y]![x]) continue;
      for (let dy = 0; dy < CELL; dy++) {
        for (let dx = 0; dx < CELL; dx++) {
          const i = ((y * CELL + dy) * px + x * CELL + dx) * 4;
          data[i] = data[i + 1] = data[i + 2] = 0;
        }
      }
    }
  }
  return { data, size: px };
}

function roundTrip(text: string, ec: "L" | "M" | "Q" | "H" = "M"): string | undefined {
  const m = encode(text, { ecLevel: ec });
  if (!m) throw new Error(`encode failed: ${text}`);
  const { data, size } = rasterize(parse(render(m, { color: false })));
  return decode(data, size, size)?.text;
}

const CASES = [
  "https://example.com",
  "https://elchika-inc.github.io/moonqr/",
  "HELLO WORLD",
  "1234567890",
  "https://github.com/elchika-inc/moonqr/pull/10",
];

describe("rendered output is a readable QR code", () => {
  for (const text of CASES) {
    it(`round-trips: ${text}`, () => {
      expect(roundTrip(text)).toBe(text);
    });
  }

  it("round-trips at every error correction level", () => {
    for (const ec of ["L", "M", "Q", "H"] as const) {
      const text = `https://example.com/ec-${ec}`;
      expect(roundTrip(text, ec)).toBe(text);
    }
  });
});
