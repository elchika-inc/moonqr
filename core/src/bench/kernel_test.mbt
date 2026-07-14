///| 128x128 の合成フレーム: 白地(200)に 7x7 モジュール相当の
///| ファインダ様パターン(1:1:3:1:1)を1つ描く。検出数 >= 1 を期待。
///| 一様データはインデックスバグを隠すため、背景に位置依存ノイズを乗せる。
fn synth_frame(w : Int, h : Int) -> Bytes {
  let buf = FixedArray::make(w * h * 4, b'\x00')
  for y = 0; y < h; y = y + 1 {
    for x = 0; x < w; x = x + 1 {
      // 位置依存の明背景 (180..219)
      let mut v = 180 + (x * 7 + y * 13) % 40
      // (32,32)-(88,88) にファインダ様パターン: 外周黒・中黒芯
      let fx = x - 32
      let fy = y - 32
      if fx >= 0 && fx < 56 && fy >= 0 && fy < 56 {
        let mx = fx / 8 // 0..6
        let my = fy / 8
        let ring = mx == 0 || mx == 6 || my == 0 || my == 6
        let core_ = mx >= 2 && mx <= 4 && my >= 2 && my <= 4
        v = if ring || core_ { 30 } else { 220 }
      }
      let i = (y * w + x) * 4
      buf[i] = v.to_byte()
      buf[i + 1] = v.to_byte()
      buf[i + 2] = v.to_byte()
      buf[i + 3] = b'\xFF'
    }
  }
  Bytes::from_array(buf[:])
}

test "kernel finds finder-like runs in synthetic frame" {
  let frame = synth_frame(128, 128)
  let hits = @bench.bench_kernel(frame, 128, 128)
  assert_true(hits >= 1)
}

test "kernel finds nothing in noise-only frame" {
  let w = 64
  let buf = FixedArray::make(w * w * 4, b'\x00')
  for i = 0; i < w * w; i = i + 1 {
    let v = 100 + (i * 31) % 80
    buf[i * 4] = v.to_byte()
    buf[i * 4 + 1] = v.to_byte()
    buf[i * 4 + 2] = v.to_byte()
    buf[i * 4 + 3] = b'\xFF'
  }
  assert_eq(@bench.bench_kernel(Bytes::from_array(buf[:]), w, w), 0)
}
