// @vitest-environment jsdom
//
// jsdom は canvas の 2D コンテキストを実装しない（`getContext("2d")` は既定で null を返す。
// `canvas` npm パッケージを追加インストールしない限り native な描画はできない）。
// そのため `HTMLCanvasElement#getContext` をモックに差し替え、`fillRect` 呼び出しの
// 回数・引数のみを検証する（ブリーフの指示通り）。
import { describe, expect, it, vi } from "vitest";
import { toCanvas } from "./dom.js";
import type { QrMatrix } from "./types.js";

function makeMatrix(size: number, blackCoords: Array<[number, number]>): QrMatrix {
  const blacks = new Set(blackCoords.map(([x, y]) => `${x},${y}`));
  return {
    size,
    get(x: number, y: number): boolean {
      if (x < 0 || y < 0 || x >= size || y >= size) return false;
      return blacks.has(`${x},${y}`);
    },
  };
}

interface MockContext {
  fillStyle: string;
  fillRect: (x: number, y: number, w: number, h: number) => void;
}

function mockCanvas(): { canvas: HTMLCanvasElement; calls: Array<[number, number, number, number]> } {
  const calls: Array<[number, number, number, number]> = [];
  const ctx: MockContext = {
    fillStyle: "",
    fillRect: vi.fn((x: number, y: number, w: number, h: number) => {
      calls.push([x, y, w, h]);
    }),
  };
  const canvas = document.createElement("canvas");
  // jsdom は 2d コンテキストを提供しないため、テスト用に差し替える。
  canvas.getContext = vi.fn(() => ctx) as unknown as HTMLCanvasElement["getContext"];
  return { canvas, calls };
}

describe("toCanvas", () => {
  it("sizes the canvas to (size + margin*2) * cell", () => {
    const matrix = makeMatrix(3, []);
    const { canvas } = mockCanvas();
    toCanvas(matrix, canvas, { margin: 2, cell: 5 });
    expect(canvas.width).toBe((3 + 2 * 2) * 5);
    expect(canvas.height).toBe((3 + 2 * 2) * 5);
  });

  it("uses default margin=4/cell=4 when options are omitted", () => {
    const matrix = makeMatrix(1, []);
    const { canvas } = mockCanvas();
    toCanvas(matrix, canvas);
    expect(canvas.width).toBe((1 + 8) * 4);
    expect(canvas.height).toBe((1 + 8) * 4);
  });

  it("fillRect count == black module count + 1 background fill", () => {
    const matrix = makeMatrix(3, [
      [0, 0],
      [2, 2],
      [1, 0],
    ]);
    const { canvas, calls } = mockCanvas();
    toCanvas(matrix, canvas);
    expect(calls.length).toBe(1 + 3);
  });

  it("draws only the background fillRect for an all-white matrix", () => {
    const matrix = makeMatrix(2, []);
    const { canvas, calls } = mockCanvas();
    toCanvas(matrix, canvas);
    expect(calls.length).toBe(1);
    // 背景は canvas 全体を塗る
    expect(calls[0]).toEqual([0, 0, canvas.width, canvas.height]);
  });

  it("draws each black module at its (margin+x)*cell, (margin+y)*cell position with cell size", () => {
    const matrix = makeMatrix(2, [[1, 0]]);
    const { canvas, calls } = mockCanvas();
    toCanvas(matrix, canvas, { margin: 1, cell: 10 });
    // calls[0] = background, calls[1] = the single black module at (x=1,y=0)
    expect(calls[1]).toEqual([(1 + 1) * 10, (0 + 1) * 10, 10, 10]);
  });
});
