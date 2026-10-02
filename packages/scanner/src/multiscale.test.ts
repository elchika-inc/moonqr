// halveRGBA の2x2ボックス平均を固定ベクタで検証する。
// multiScaleDecode / モニター格子写真での実効性の回帰網は
// packages/moonqr/test/monitor-lattice.test.mjs 側（Phase 2 Task 12 発）にある
// ——本ファイルはそちらが暗黙に依存する最小プリミティブ（ボックス平均の算術と
// 奇数サイズの切り捨て）を単体で固定する。
import { describe, expect, it } from "vitest";
import { halveRGBA } from "./multiscale.js";

/** width*height*4 のRGBA配列を作るヘルパー（テストの可読性のため）。 */
function rgba(pixels: Array<[number, number, number, number]>): Uint8Array {
  const out = new Uint8Array(pixels.length * 4);
  pixels.forEach(([r, g, b, a], i) => {
    out[i * 4] = r;
    out[i * 4 + 1] = g;
    out[i * 4 + 2] = b;
    out[i * 4 + 3] = a;
  });
  return out;
}

describe("halveRGBA", () => {
  it("2x2ブロックの単純平均を返す（4画素→1画素）", () => {
    // 2x2 の1ブロックのみ: (0,0,0,255) (100,100,100,255) / (200,200,200,255) (255,255,255,255)
    // 平均 = (0+100+200+255)/4 = 138.75 -> 出力は >>2 なので floor((0+100+200+255)/4) = 138
    const data = rgba([
      [0, 0, 0, 255],
      [100, 100, 100, 255],
      [200, 200, 200, 255],
      [255, 255, 255, 255],
    ]);
    const out = halveRGBA(data, 2, 2);
    expect(out.width).toBe(1);
    expect(out.height).toBe(1);
    expect(Array.from(out.data)).toEqual([138, 138, 138, 255]);
  });

  it("4x4 を 2x2 に縮小し、各ブロックを独立に平均する", () => {
    // 4x4 を4つの2x2ブロックに分割し、ブロックごとに単一色で塗る
    // (0,0)ブロック=10, (2,0)ブロック=20, (0,2)ブロック=30, (2,2)ブロック=40
    const w = 4;
    const h = 4;
    const data = new Uint8Array(w * h * 4);
    for (let y = 0; y < h; y++) {
      for (let x = 0; x < w; x++) {
        const blockX = x < 2 ? 0 : 1;
        const blockY = y < 2 ? 0 : 1;
        const value = blockY === 0 ? (blockX === 0 ? 10 : 20) : blockX === 0 ? 30 : 40;
        const i = (y * w + x) * 4;
        data[i] = value;
        data[i + 1] = value;
        data[i + 2] = value;
        data[i + 3] = 255;
      }
    }
    const out = halveRGBA(data, w, h);
    expect(out.width).toBe(2);
    expect(out.height).toBe(2);
    // 各出力画素 = 対応ブロックの一様値がそのまま平均として現れる
    expect(Array.from(out.data)).toEqual([
      10, 10, 10, 255, 20, 20, 20, 255, 30, 30, 30, 255, 40, 40, 40, 255,
    ]);
  });

  it("奇数の幅・高さは末尾の行・列を切り捨てる（floor(width/2), floor(height/2)）", () => {
    // 5x3 -> floor(5/2)=2, floor(3/2)=1。末尾の列(x=4)・行(y=2)は無視される。
    const w = 5;
    const h = 3;
    const data = new Uint8Array(w * h * 4).fill(50);
    // 末尾列・行だけ極端な値にして、出力に影響していないことを確認する
    for (let y = 0; y < h; y++) {
      const i = (y * w + 4) * 4; // x=4 (切り捨てられる列)
      data[i] = 255;
      data[i + 1] = 255;
      data[i + 2] = 255;
      data[i + 3] = 255;
    }
    for (let x = 0; x < w; x++) {
      const i = (2 * w + x) * 4; // y=2 (切り捨てられる行)
      data[i] = 255;
      data[i + 1] = 255;
      data[i + 2] = 255;
      data[i + 3] = 255;
    }
    const out = halveRGBA(data, w, h);
    expect(out.width).toBe(2);
    expect(out.height).toBe(1);
    // 全出力画素が一様値50のまま（255に汚染されていない＝切り捨てが機能している）
    expect(Array.from(out.data)).toEqual([50, 50, 50, 50, 50, 50, 50, 50]);
  });

  it("1x1 のような縮小不能な入力は 0x0 を返す（floor(1/2) = 0）", () => {
    const data = rgba([[255, 255, 255, 255]]);
    const out = halveRGBA(data, 1, 1);
    expect(out.width).toBe(0);
    expect(out.height).toBe(0);
    expect(out.data.length).toBe(0);
  });
});

import { multiScaleDecode } from "./multiscale.js";

describe("multiScaleDecode", () => {
  it("最大辺が149px → 元画像だけをscale=1で返す", () => {
    const data = new Uint8Array(149 * 100 * 4);
    const outcome = multiScaleDecode((pixels) => pixels, data, 149, 100);
    expect(outcome).toEqual({
      result: data,
      scale: 1,
      width: 149,
      height: 100,
      attemptedScales: [1],
    });
    expect(outcome?.result).toBe(data);
  });

  it.each([
    [150, 100, 75, 50],
    [100, 150, 50, 75],
  ])("%ix%iで最大辺が150px → %ix%iの段から試す", (width, height, halfWidth, halfHeight) => {
    const data = new Uint8Array(width * height * 4);
    expect(multiScaleDecode(() => "成功", data, width, height)).toEqual({
      result: "成功",
      scale: 2,
      width: halfWidth,
      height: halfHeight,
      attemptedScales: [2],
    });
  });

  it("複数段のうち300x200で成功 → 小さい順の試行列を成功段で打ち切る", () => {
    const data = new Uint8Array(600 * 400 * 4);
    const result = { text: "成功" };
    const outcome = multiScaleDecode(
      (_pixels, width, height) => (width === 300 && height === 200 ? result : null),
      data,
      600,
      400,
    );
    expect(outcome).toEqual({
      result,
      scale: 2,
      width: 300,
      height: 200,
      attemptedScales: [8, 4, 2],
    });
    expect(outcome?.result).toBe(result);
  });

  it("全段でnull → nullを返す", () => {
    const data = new Uint8Array(600 * 400 * 4);
    expect(multiScaleDecode(() => null, data, 600, 400)).toBeNull();
  });

  it.each(["", 0])("小さい段で%j → 失敗として次の段を試す", (failure) => {
    const data = new Uint8Array(300 * 200 * 4);
    expect(
      multiScaleDecode<string | number>(
        (_pixels, width) => (width === 300 ? "成功" : failure),
        data,
        300,
        200,
      ),
    ).toEqual({
      result: "成功",
      scale: 1,
      width: 300,
      height: 200,
      attemptedScales: [4, 2, 1],
    });
  });

  it("4096x4096で画素数が上限と等しい → 元解像度も試せる", () => {
    const data = new Uint8Array(4096 * 4096 * 4);
    expect(
      multiScaleDecode((_pixels, width) => (width === 4096 ? "成功" : null), data, 4096, 4096),
    ).toEqual({
      result: "成功",
      scale: 1,
      width: 4096,
      height: 4096,
      attemptedScales: [32, 16, 8, 4, 2, 1],
    });
  });

  it("4097x4097で画素数が上限超過 → 事前半減もscaleに含める", () => {
    const data = new Uint8Array(4097 * 4097 * 4);
    expect(
      multiScaleDecode((_pixels, width) => (width === 2048 ? "成功" : null), data, 4097, 4097),
    ).toEqual({
      result: "成功",
      scale: 2,
      width: 2048,
      height: 2048,
      attemptedScales: [32, 16, 8, 4, 2],
    });
  });

  it("上限超過の元解像度でしか成功しない → 元解像度は試さずnullを返す", () => {
    const data = new Uint8Array(4097 * 4097 * 4);
    expect(
      multiScaleDecode((_pixels, width) => (width === 4097 ? "成功" : null), data, 4097, 4097),
    ).toBeNull();
  });

  it("151x101の奇数画像 → 端を切り捨てた75x50の平均画素をデコーダへ渡す", () => {
    const data = new Uint8Array(151 * 101 * 4);
    data.set([0, 1, 2, 3, 40, 41, 42, 43]);
    data.set([80, 81, 82, 83, 120, 121, 122, 123], 151 * 4);
    expect(multiScaleDecode((pixels) => Array.from(pixels.slice(0, 4)), data, 151, 101)).toEqual({
      result: [60, 61, 62, 63],
      scale: 2,
      width: 75,
      height: 50,
      attemptedScales: [2],
    });
  });

  it("decodeFnが例外を投げる → 握りつぶさず呼び出し元へ伝播する", () => {
    const failure = new Error("デコード失敗");
    expect(() =>
      multiScaleDecode(
        () => {
          throw failure;
        },
        new Uint8Array(4),
        1,
        1,
      ),
    ).toThrow(failure);
  });
});
