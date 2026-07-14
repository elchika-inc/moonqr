///| 移植元: jsQR (Apache-2.0), commit 8e6a036beafa7053dd44b1b76ac578d22b1b3311
///| https://github.com/cozmo/jsQR/blob/8e6a036beafa7053dd44b1b76ac578d22b1b3311/src/binarizer/index.ts
///| BLOCK_SIZE=8 / MIN_DYNAMIC_RANGE=24、低分散ブロックの
///| 「左・上・左上ブロックしきい値の平均を継承する」規則、5x5近傍ブロック
///| 平均によるしきい値化を忠実に移植した（詳細な行対応は task-2-report.md）。
///| NOTICE ファイルへの正式なクレジット記載は Phase 2 Task 3 で行う。

let block_size : Int = 8

let min_dynamic_range : Int = 24

///| `Uint8ClampedArray` への代入相当（四捨五入して 0..255 にクランプ）。
///| jsQR は greyscalePixels / blackPoints の両方をこの型のバッファに
///| 格納しており、丸め込みの結果が後続の平均計算に反映される。
fn clamp_u8(v : Double) -> Int {
  if v <= 0.0 {
    0
  } else if v >= 255.0 {
    255
  } else {
    (v + 0.5).to_int()
  }
}

///| `value` を [lo, hi] にクランプする（jsQR `numBetween` 相当）。
fn num_between(value : Int, lo : Int, hi : Int) -> Int {
  if value < lo {
    lo
  } else if value > hi {
    hi
  } else {
    value
  }
}

///| RGBA → 二値行列。返り値 (binarized, inverted)。
///| jsQR 同様、反転版も同時生成する（invertAttempts 用）
pub fn binarize(data : Bytes, width : Int, height : Int) -> (BitMatrix, BitMatrix) {
  // 1. グレースケール化（jsQR L37: 0.2126R + 0.7152G + 0.0722B）
  let gray = FixedArray::make(width * height, 0)
  for y = 0; y < height; y = y + 1 {
    for x = 0; x < width; x = x + 1 {
      let i = (y * width + x) * 4
      let r = data[i].to_int().to_double()
      let g = data[i + 1].to_int().to_double()
      let b = data[i + 2].to_int().to_double()
      gray[y * width + x] = clamp_u8(0.2126 * r + 0.7152 * g + 0.0722 * b)
    }
  }

  // jsQR は width/height が block_size の倍数でない場合、最終ブロックの
  // 読み出しが次行へオーバーランする未定義動作になる（Uint8ClampedArray
  // の範囲外読み出しは undefined → NaN 伝播）。ここではクラッシュや
  // 未定義値を避けるため端の座標をクランプする（意図的な適応。
  // 詳細は task-2-report.md の「アダプテーション」参照）。
  let sample = fn(x : Int, y : Int) -> Int {
    let cx = if x >= width { width - 1 } else { x }
    let cy = if y >= height { height - 1 } else { y }
    gray[cy * width + cx]
  }
  let h_regions = (width + block_size - 1) / block_size
  let v_regions = (height + block_size - 1) / block_size

  // 2. ブロック平均 → 低分散判定 → 近傍しきい値継承（jsQR L44-88 を移植）
  let black_points = FixedArray::make(h_regions * v_regions, 0)
  for vr = 0; vr < v_regions; vr = vr + 1 {
    for hr = 0; hr < h_regions; hr = hr + 1 {
      let mut sum = 0
      let mut min_v = 256
      let mut max_v = 0
      for dy = 0; dy < block_size; dy = dy + 1 {
        for dx = 0; dx < block_size; dx = dx + 1 {
          let lum = sample(hr * block_size + dx, vr * block_size + dy)
          sum = sum + lum
          if lum < min_v {
            min_v = lum
          }
          if lum > max_v {
            max_v = lum
          }
        }
      }
      let mut average = sum.to_double() / (block_size * block_size).to_double()
      if max_v - min_v <= min_dynamic_range {
        // ブロック内の分散が低い = 一様な明/暗ブロックとみなす。
        // この場合 average をそのまま使うとノイズから偽のデータ境界を
        // 作ってしまうため、min の半分をデフォルトのしきい値とする
        // （＝実質的に白側へ倒す）。
        average = min_v.to_double() / 2.0
        if vr > 0 && hr > 0 {
          // 「白背景」前提の補正: 近傍（上・左・左上）ブロックのしきい値
          // 平均と比較する。暗いシンボルは必ず妥当なしきい値が推定できる
          // 明るい背景に囲まれているという前提に基づき、境界で推定された
          // しきい値を内部（一様ブロック）へ伝播させる。
          let neighbor_avg = (
            black_points[(vr - 1) * h_regions + hr].to_double() +
            2.0 * black_points[vr * h_regions + hr - 1].to_double() +
            black_points[(vr - 1) * h_regions + hr - 1].to_double()
          ) /
          4.0
          if min_v.to_double() < neighbor_avg {
            average = neighbor_avg
          }
        }
      }
      black_points[vr * h_regions + hr] = clamp_u8(average)
    }
  }

  // 3. 5x5近傍ブロック平均でしきい値化（jsQR L95-118）
  let binarized = BitMatrix::make(width, height)
  let inverted = BitMatrix::make(width, height)
  for vr = 0; vr < v_regions; vr = vr + 1 {
    for hr = 0; hr < h_regions; hr = hr + 1 {
      let left = num_between(hr, 2, h_regions - 3)
      let top = num_between(vr, 2, v_regions - 3)
      let mut sum = 0
      for yr = -2; yr <= 2; yr = yr + 1 {
        for xr = -2; xr <= 2; xr = xr + 1 {
          sum = sum + black_points[(top + yr) * h_regions + (left + xr)]
        }
      }
      let threshold = sum.to_double() / 25.0
      for yr = 0; yr < block_size; yr = yr + 1 {
        for xr = 0; xr < block_size; xr = xr + 1 {
          let x = hr * block_size + xr
          let y = vr * block_size + yr
          if x < width && y < height {
            let lum = gray[y * width + x].to_double()
            let black = lum <= threshold
            binarized.set(x, y, black)
            inverted.set(x, y, !black)
          }
        }
      }
    }
  }
  (binarized, inverted)
}
