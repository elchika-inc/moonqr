import { genFrame } from "./gen-frame.mjs";

const WARMUP = 30, ITERS = 200;
const frame = genFrame();

function measure(label, fn) {
  for (let i = 0; i < WARMUP; i++) fn();
  const times = [];
  for (let i = 0; i < ITERS; i++) {
    const t0 = performance.now();
    const hits = fn();
    times.push(performance.now() - t0);
    if (i === 0) console.log(`${label} hits=${hits}`); // 結果一致の目視確認用
  }
  times.sort((a, b) => a - b);
  const median = times[Math.floor(ITERS / 2)];
  console.log(`${label}: median ${median.toFixed(3)} ms/frame`);
  return median;
}

// --- js backend（moon 0.1.20260703 の実際のビルド出力: core/_build/js/release/build/bench/bench.js）---
const jsMod = await import("../core/_build/js/release/build/bench/bench.js");
const jsTime = measure("js     ", () => jsMod.bench_kernel(frame, 640, 480));

// --- wasm-gc backend（core/_build/wasm-gc/release/build/bench/bench.wasm、import不要）---
const { readFile } = await import("node:fs/promises");
const wasmBytes = await readFile(
  new URL("../core/_build/wasm-gc/release/build/bench/bench.wasm", import.meta.url));
const { instance } = await WebAssembly.instantiate(wasmBytes, {});
const w = instance.exports;
const wasmTime = measure("wasm-gc", () => {
  // 境界コスト込み: フレーム転送も計測に含める（これが本番の姿）
  // MoonBit docs に Uint8Array -> FixedArray[Byte] の専用高速パスは見つからず、
  // make_frame + per-element frame_set が現状の境界コスト（RESULT.md 参照）。
  const f = w.make_frame(frame.length);
  for (let i = 0; i < frame.length; i++) w.frame_set(f, i, frame[i]);
  return w.bench_kernel_arr(f, 640, 480);
});

console.log(`ratio (wasm/js): ${(wasmTime / jsTime).toFixed(2)}`);
