// mulberry32 seeded PRNG で 640x480 RGBA 合成フレームを決定的に生成。
// 背景ノイズ + ファインダ様パターン3個（一様fixture回避）。
export function genFrame(width = 640, height = 480, seed = 42) {
  let a = seed >>> 0;
  const rand = () => {
    a |= 0; a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
  const buf = new Uint8Array(width * height * 4);
  for (let p = 0; p < width * height; p++) {
    const v = 150 + Math.floor(rand() * 80);
    buf[p * 4] = v; buf[p * 4 + 1] = v; buf[p * 4 + 2] = v; buf[p * 4 + 3] = 255;
  }
  const drawFinder = (ox, oy, mod) => {
    for (let my = 0; my < 7; my++) for (let mx = 0; mx < 7; mx++) {
      const ring = mx === 0 || mx === 6 || my === 0 || my === 6;
      const core = mx >= 2 && mx <= 4 && my >= 2 && my <= 4;
      const v = ring || core ? 25 : 230;
      for (let dy = 0; dy < mod; dy++) for (let dx = 0; dx < mod; dx++) {
        const x = ox + mx * mod + dx, y = oy + my * mod + dy;
        const i = (y * width + x) * 4;
        buf[i] = v; buf[i + 1] = v; buf[i + 2] = v;
      }
    }
  };
  drawFinder(50, 50, 8); drawFinder(450, 60, 8); drawFinder(60, 350, 8);
  return buf;
}
