///| @encode.Matrix（モジュール単位、true=黒）を module_px px/モジュール・
///| quiet px の白余白付きで BitMatrix（ピクセル単位、true=黒）へ直接展開する。
///| 二値化を経由しない「理想画像」を作ることで locator 単体の幾何ロジックを検証する。
fn expand_to_bitmatrix(m : @encode.Matrix, module_px : Int, quiet : Int) -> @decode.BitMatrix {
  let total = m.size * module_px + 2 * quiet
  let bm = @decode.BitMatrix::make(total, total)
  for my = 0; my < m.size; my = my + 1 {
    for mx = 0; mx < m.size; mx = mx + 1 {
      if m.get(mx, my) {
        for dy = 0; dy < module_px; dy = dy + 1 {
          for dx = 0; dx < module_px; dx = dx + 1 {
            bm.set(quiet + mx * module_px + dx, quiet + my * module_px + dy, true)
          }
        }
      }
    }
  }
  bm
}

///| 180度回転版: モジュール座標を (size-1-mx, size-1-my) に反転して展開する
///| （ピクセルバッファの点対称反転と等価）。
fn expand_to_bitmatrix_rot180(
  m : @encode.Matrix,
  module_px : Int,
  quiet : Int,
) -> @decode.BitMatrix {
  let total = m.size * module_px + 2 * quiet
  let bm = @decode.BitMatrix::make(total, total)
  for my = 0; my < m.size; my = my + 1 {
    for mx = 0; mx < m.size; mx = mx + 1 {
      if m.get(mx, my) {
        let rmx = m.size - 1 - mx
        let rmy = m.size - 1 - my
        for dy = 0; dy < module_px; dy = dy + 1 {
          for dx = 0; dx < module_px; dx = dx + 1 {
            bm.set(quiet + rmx * module_px + dx, quiet + rmy * module_px + dy, true)
          }
        }
      }
    }
  }
  bm
}

///| 位置依存の疑似乱数ビットマトリクス。ファインダ/アライメント様パターンを
///| 意図的に含まない。
///| jsQR の 1:1:3:1:1 判定は許容誤差が広く（各ランは平均比の±100%以内で
///| 合格）、画素単位の Bernoulli(0.5) ノイズは行内反転が多すぎて単発の
///| ファインダ様ランに偶然一致しやすい。さらに列方向に複数行ぶん同一の
///| ブロックパターンを共有すると、その偶然一致がそのまま
///| `bottom.y - top.y >= 2`（Quad化条件）を満たしてしまい誤検出する
///| （実測で確認済み）。そのため列ブロック幅は保ちつつ、各行ごとに
///| 独立した疑似乱数（seed を (y, bx) から作り直す）を用い、行間の
///| パターン相関を断つ。
fn noise_bitmatrix(size : Int) -> @decode.BitMatrix {
  let block = 15
  let bm = @decode.BitMatrix::make(size, size)
  for y = 0; y < size; y = y + 1 {
    for bx = 0; bx * block < size; bx = bx + 1 {
      let mut seed = (y + 1) * 374761393 + (bx + 1) * 668265263 + 17
      seed = seed ^ (seed << 13)
      seed = seed ^ (seed >> 17)
      seed = seed ^ (seed << 5)
      let bit = (seed & 1) == 1
      for dx = 0; dx < block; dx = dx + 1 {
        let x = bx * block + dx
        if x < size {
          bm.set(x, y, bit)
        }
      }
    }
  }
  bm
}

test "locate finds LOCATOR TEST v2-M finders at expected pixel centers" {
  let matrix = match @encode.encode("LOCATOR TEST", @encode.EcLevel::M, Some(2)) {
    Some(m) => m
    None => abort("encode failed")
  }
  assert_eq(matrix.size, 25)
  let bm = expand_to_bitmatrix(matrix, 4, 16)
  let locations = @decode.locate(bm)
  assert_true(locations.length() >= 1)
  let loc = locations[0]
  assert_eq(loc.dimension, 25)
  let module_size = loc.module_size
  assert_true(Double::abs(loc.top_left.x - 30.0) <= module_size)
  assert_true(Double::abs(loc.top_left.y - 30.0) <= module_size)
  assert_true(Double::abs(loc.top_right.x - 102.0) <= module_size)
  assert_true(Double::abs(loc.top_right.y - 30.0) <= module_size)
  assert_true(Double::abs(loc.bottom_left.x - 30.0) <= module_size)
  assert_true(Double::abs(loc.bottom_left.y - 102.0) <= module_size)
}

test "locate succeeds on a 180-degree rotated image (finder geometry is symmetric)" {
  let matrix = match @encode.encode("LOCATOR TEST", @encode.EcLevel::M, Some(2)) {
    Some(m) => m
    None => abort("encode failed")
  }
  let bm = expand_to_bitmatrix_rot180(matrix, 4, 16)
  let locations = @decode.locate(bm)
  assert_true(locations.length() >= 1)
  assert_eq(locations[0].dimension, 25)
}

test "locate returns empty on noise-only matrix without crashing" {
  let bm = noise_bitmatrix(120)
  let locations = @decode.locate(bm)
  assert_eq(locations.length(), 0)
}
