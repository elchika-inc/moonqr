///| RGBA → 輝度（整数近似 BT.601: (77R + 150G + 29B) >> 8）
fn to_gray(rgba : Bytes, width : Int, height : Int) -> FixedArray[Int] {
  let gray = FixedArray::make(width * height, 0)
  for p = 0; p < width * height; p = p + 1 {
    let i = p * 4
    let r = rgba[i].to_int()
    let g = rgba[i + 1].to_int()
    let b = rgba[i + 2].to_int()
    gray[p] = (77 * r + 150 * g + 29 * b) >> 8
  }
  gray
}

///| 8x8 ブロック平均でしきい値マップを作り二値化（1=黒）
fn binarize(gray : FixedArray[Int], width : Int, height : Int) -> FixedArray[Int] {
  let bw = (width + 7) / 8
  let bh = (height + 7) / 8
  let means = FixedArray::make(bw * bh, 128)
  for by = 0; by < bh; by = by + 1 {
    for bx = 0; bx < bw; bx = bx + 1 {
      let mut sum = 0
      let mut n = 0
      for dy = 0; dy < 8; dy = dy + 1 {
        for dx = 0; dx < 8; dx = dx + 1 {
          let x = bx * 8 + dx
          let y = by * 8 + dy
          if x < width && y < height {
            sum = sum + gray[y * width + x]
            n = n + 1
          }
        }
      }
      means[by * bw + bx] = sum / n
    }
  }
  let bin = FixedArray::make(width * height, 0)
  for y = 0; y < height; y = y + 1 {
    for x = 0; x < width; x = x + 1 {
      // 自ブロック単独の平均だと一様ブロック（大きな黒/白領域）で
      // mean==pixel となり全て白判定になるため、3x3近傍ブロック平均を使う
      let bx = x / 8
      let by = y / 8
      let mut sum = 0
      let mut n = 0
      for dy = -1; dy <= 1; dy = dy + 1 {
        for dx = -1; dx <= 1; dx = dx + 1 {
          let nx = bx + dx
          let ny = by + dy
          if nx >= 0 && nx < bw && ny >= 0 && ny < bh {
            sum = sum + means[ny * bw + nx]
            n = n + 1
          }
        }
      }
      let m = sum / n
      bin[y * width + x] = if gray[y * width + x] < m { 1 } else { 0 }
    }
  }
  bin
}

///| 走査線上の黒白黒白黒ラン比 1:1:3:1:1（各±50%）をカウント
fn scan_ratios(bin : FixedArray[Int], width : Int, height : Int) -> Int {
  let mut hits = 0
  for y = 0; y < height; y = y + 1 {
    let runs : Array[Int] = []
    let mut cur = bin[y * width]
    let mut len = 1
    for x = 1; x < width; x = x + 1 {
      let v = bin[y * width + x]
      if v == cur {
        len = len + 1
      } else {
        runs.push(len)
        cur = v
        len = 1
      }
    }
    runs.push(len)
    // 先頭ランが白なら奇数indexが黒。黒始まりの5連続を判定
    let start = if bin[y * width] == 1 { 0 } else { 1 }
    for i = start; i + 4 < runs.length(); i = i + 2 {
      let m = runs[i + 2].to_double() / 3.0
      let ok = fn(r : Int) -> Bool {
        r.to_double() > m * 0.5 && r.to_double() < m * 1.5
      }
      if ok(runs[i]) && ok(runs[i + 1]) && ok(runs[i + 3]) && ok(runs[i + 4]) {
        hits = hits + 1
      }
    }
  }
  hits
}

///| スパイク計測対象: フレーム1枚分の代表処理
pub fn bench_kernel(rgba : Bytes, width : Int, height : Int) -> Int {
  let gray = to_gray(rgba, width, height)
  let bin = binarize(gray, width, height)
  scan_ratios(bin, width, height)
}

///| wasm-gc 用エントリ（JS から GC 配列を直接作れないため転送ヘルパを公開）
pub fn make_frame(len : Int) -> FixedArray[Byte] {
  FixedArray::make(len, b'\x00')
}

pub fn frame_set(f : FixedArray[Byte], i : Int, v : Int) -> Unit {
  f[i] = v.to_byte()
}

pub fn bench_kernel_arr(f : FixedArray[Byte], width : Int, height : Int) -> Int {
  bench_kernel(Bytes::from_fixedarray(f), width, height)
}
