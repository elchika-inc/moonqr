///| extractor の結合テスト。Task 3 (`locator_test.mbt`) の
///| `expand_to_bitmatrix` ヘルパー（同一テストパッケージ内で共有）で
///| エンコード結果を理想画像へ展開し、locate → extract を通して
///| 得られたモジュール行列が元のエンコード行列と全セル一致することを
///| 確認する（①恒等系）。②透視系では、テスト内で独立実装した簡易射影
///| （extractor.mbt の内部実装は再利用しない）で画像を軽く歪ませてから
///| 同じ結合をかけ、extract() の射影サンプリング経路を運動させる。

///| テスト専用の3x3同次変換ヘルパー（extractor.mbt の
///| square_to_quadrilateral 等とは独立実装。インデックス規約は同じ:
///| 0=a11 1=a12 2=a13 3=a21 4=a22 5=a23 6=a31 7=a32 8=a33）。
fn synth_square_to_quad(
  p1 : @decode.Point,
  p2 : @decode.Point,
  p3 : @decode.Point,
  p4 : @decode.Point,
) -> FixedArray[Double] {
  let dx3 = p1.x - p2.x + p3.x - p4.x
  let dy3 = p1.y - p2.y + p3.y - p4.y
  let m = FixedArray::make(9, 0.0)
  if dx3 == 0.0 && dy3 == 0.0 {
    m[0] = p2.x - p1.x
    m[1] = p2.y - p1.y
    m[2] = 0.0
    m[3] = p3.x - p2.x
    m[4] = p3.y - p2.y
    m[5] = 0.0
    m[6] = p1.x
    m[7] = p1.y
    m[8] = 1.0
  } else {
    let dx1 = p2.x - p3.x
    let dx2 = p4.x - p3.x
    let dy1 = p2.y - p3.y
    let dy2 = p4.y - p3.y
    let denominator = dx1 * dy2 - dx2 * dy1
    let a13 = (dx3 * dy2 - dx2 * dy3) / denominator
    let a23 = (dx1 * dy3 - dx3 * dy1) / denominator
    m[0] = p2.x - p1.x + a13 * p2.x
    m[1] = p2.y - p1.y + a13 * p2.y
    m[2] = a13
    m[3] = p4.x - p1.x + a23 * p4.x
    m[4] = p4.y - p1.y + a23 * p4.y
    m[5] = a23
    m[6] = p1.x
    m[7] = p1.y
    m[8] = 1.0
  }
  m
}

fn synth_quad_to_square(
  p1 : @decode.Point,
  p2 : @decode.Point,
  p3 : @decode.Point,
  p4 : @decode.Point,
) -> FixedArray[Double] {
  let s = synth_square_to_quad(p1, p2, p3, p4)
  let m = FixedArray::make(9, 0.0)
  m[0] = s[4] * s[8] - s[5] * s[7]
  m[1] = s[2] * s[7] - s[1] * s[8]
  m[2] = s[1] * s[5] - s[2] * s[4]
  m[3] = s[5] * s[6] - s[3] * s[8]
  m[4] = s[0] * s[8] - s[2] * s[6]
  m[5] = s[2] * s[3] - s[0] * s[5]
  m[6] = s[3] * s[7] - s[4] * s[6]
  m[7] = s[1] * s[6] - s[0] * s[7]
  m[8] = s[0] * s[4] - s[1] * s[3]
  m
}

fn synth_times(a : FixedArray[Double], b : FixedArray[Double]) -> FixedArray[Double] {
  let m = FixedArray::make(9, 0.0)
  m[0] = a[0] * b[0] + a[3] * b[1] + a[6] * b[2]
  m[1] = a[1] * b[0] + a[4] * b[1] + a[7] * b[2]
  m[2] = a[2] * b[0] + a[5] * b[1] + a[8] * b[2]
  m[3] = a[0] * b[3] + a[3] * b[4] + a[6] * b[5]
  m[4] = a[1] * b[3] + a[4] * b[4] + a[7] * b[5]
  m[5] = a[2] * b[3] + a[5] * b[4] + a[8] * b[5]
  m[6] = a[0] * b[6] + a[3] * b[7] + a[6] * b[8]
  m[7] = a[1] * b[6] + a[4] * b[7] + a[7] * b[8]
  m[8] = a[2] * b[6] + a[5] * b[7] + a[8] * b[8]
  m
}

///| `src`（矩形 [0,src_w) x [0,src_h)）を 4隅 `dst1..dst4`（この順で
///| 元の (0,0),(src_w,0),(src_w,src_h),(0,src_h) に対応）へ写した
///| dst_w x dst_h の画像を作る。各出力画素の中心を逆写像で元画像へ戻し
///| 最近傍（floor）サンプリングする。dst 側で元画像の外へ写った画素は
///| `BitMatrix::get` の bounds-safe 挙動によりそのまま白（false）になる。
fn warp_bitmatrix(
  src : @decode.BitMatrix,
  src_w : Int,
  src_h : Int,
  dst_w : Int,
  dst_h : Int,
  dst1 : @decode.Point,
  dst2 : @decode.Point,
  dst3 : @decode.Point,
  dst4 : @decode.Point,
) -> @decode.BitMatrix {
  let src_w_d = src_w.to_double()
  let src_h_d = src_h.to_double()
  let src1 : @decode.Point = { x: 0.0, y: 0.0 }
  let src2 : @decode.Point = { x: src_w_d, y: 0.0 }
  let src3 : @decode.Point = { x: src_w_d, y: src_h_d }
  let src4 : @decode.Point = { x: 0.0, y: src_h_d }
  // dst -> src の写像（extractor.mbt の quadrilateralToQuadrilateral(dst,src)
  // 相当の合成順序: times(squareToQuad(src...), quadToSquare(dst...))）。
  let q_to_s = synth_quad_to_square(dst1, dst2, dst3, dst4)
  let s_to_q = synth_square_to_quad(src1, src2, src3, src4)
  let transform = synth_times(s_to_q, q_to_s)
  let out = @decode.BitMatrix::make(dst_w, dst_h)
  for y = 0; y < dst_h; y = y + 1 {
    for x = 0; x < dst_w; x = x + 1 {
      let xv = x.to_double() + 0.5
      let yv = y.to_double() + 0.5
      let denominator = transform[2] * xv + transform[5] * yv + transform[8]
      let sx = (transform[0] * xv + transform[3] * yv + transform[6]) / denominator
      let sy = (transform[1] * xv + transform[4] * yv + transform[7]) / denominator
      out.set(x, y, src.get(sx.floor().to_int(), sy.floor().to_int()))
    }
  }
  out
}

///| encode.Matrix と extract 済み BitMatrix が全セル一致するか確認する。
fn assert_matrix_matches(expected : @encode.Matrix, actual : @decode.BitMatrix) -> Unit raise {
  assert_eq(actual.width, expected.size)
  assert_eq(actual.height, expected.size)
  for my = 0; my < expected.size; my = my + 1 {
    for mx = 0; mx < expected.size; mx = mx + 1 {
      assert_eq(actual.get(mx, my), expected.get(mx, my))
    }
  }
}

test "extract reconstructs the original module matrix from an identity image" {
  let matrix = match @encode.encode("EXTRACT", @encode.EcLevel::M, Some(2)) {
    Some(m) => m
    None => abort("encode failed")
  }
  assert_eq(matrix.size, 25)
  let bm = expand_to_bitmatrix(matrix, 4, 16)
  let locations = @decode.locate(bm)
  assert_true(locations.length() >= 1)
  let loc = locations[0]
  assert_eq(loc.dimension, 25)
  let result = @decode.extract(bm, loc)
  assert_matrix_matches(matrix, result.matrix)
}

test "extract reconstructs the original module matrix through a mild perspective warp" {
  let matrix = match @encode.encode("EXTRACT", @encode.EcLevel::M, Some(2)) {
    Some(m) => m
    None => abort("encode failed")
  }
  assert_eq(matrix.size, 25)
  let src = expand_to_bitmatrix(matrix, 4, 16)
  let src_dim = 25 * 4 + 2 * 16 // 132
  let margin = 20
  let dst_dim = src_dim + 2 * margin // 172, 十分な余白
  let dim_d = src_dim.to_double()

  // 各隅のオフセットは dim_d の 10% 以内（±13.2px 未満）に収める。
  let dst1 : @decode.Point = { x: margin.to_double() - 8.0, y: margin.to_double() - 6.0 }
  let dst2 : @decode.Point = {
    x: margin.to_double() + dim_d + 7.0,
    y: margin.to_double() - 9.0,
  }
  let dst3 : @decode.Point = {
    x: margin.to_double() + dim_d - 5.0,
    y: margin.to_double() + dim_d + 8.0,
  }
  let dst4 : @decode.Point = {
    x: margin.to_double() + 6.0,
    y: margin.to_double() + dim_d + 5.0,
  }
  let warped = warp_bitmatrix(src, src_dim, src_dim, dst_dim, dst_dim, dst1, dst2, dst3, dst4)
  let locations = @decode.locate(warped)
  assert_true(locations.length() >= 1)
  let loc = locations[0]
  assert_eq(loc.dimension, 25)
  let result = @decode.extract(warped, loc)
  assert_matrix_matches(matrix, result.matrix)
}

test "extract mapping recovers the top-left finder center pixel on an identity image" {
  let matrix = match @encode.encode("EXTRACT", @encode.EcLevel::M, Some(2)) {
    Some(m) => m
    None => abort("encode failed")
  }
  let bm = expand_to_bitmatrix(matrix, 4, 16)
  let locations = @decode.locate(bm)
  assert_true(locations.length() >= 1)
  let loc = locations[0]
  let result = @decode.extract(bm, loc)
  let px = (result.mapping)(3.5, 3.5)
  assert_true(Double::abs(px.x - 30.0) <= 1.0)
  assert_true(Double::abs(px.y - 30.0) <= 1.0)
}
