///| extractor.mbt の private 変換関数を独立計算ベクタでピン留めする
///| whitebox テスト。extractor_test.mbt の透視系オラクルは jsQR と同じ
///| 閉形式を再転記しているため、両者が同じ誤読をすると往復で相殺して
///| 検出できない。ここでは jsQR の閉形式を一切使わず、標準的な 8x8 DLT
///| 線形系（Gaussian elimination）と数値逆行列で独立に計算した期待値
///| （導出スクリプトは task-4-report.md 参照）に対して 9 成分を照合する。
///|
///| 期待値の規約: 単位正方形 (0,0),(1,0),(1,1),(0,1) → p1,p2,p3,p4。
///| jsQR レイアウト m[0..8] = a11,a12,a13,a21,a22,a23,a31,a32,a33 で
///| x' = (a11 x + a21 y + a31) / (a13 x + a23 y + a33)。
///| square_to_quadrilateral は a33=1 に正規化して返すため直接比較できる。
///| quadrilateral_to_square は随伴行列（スケール不定）なので、両辺を
///| m[8]=1 に正規化（ratio 比較）してから照合する。

fn assert_close(actual : Double, expected : Double, tol : Double) -> Unit raise {
  assert_true(Double::abs(actual - expected) <= tol)
}

fn assert_matrix9(
  actual : FixedArray[Double],
  expected : FixedArray[Double],
  tol : Double,
) -> Unit raise {
  for i = 0; i < 9; i = i + 1 {
    assert_close(actual[i], expected[i], tol)
  }
}

///| m[8]=1 になるようスケール正規化した複製を返す（同次変換はスケール同値）。
fn normalize9(m : FixedArray[Double]) -> FixedArray[Double] {
  let out = FixedArray::make(9, 0.0)
  for i = 0; i < 9; i = i + 1 {
    out[i] = m[i] / m[8]
  }
  out
}

test "square_to_quadrilateral projective branch matches DLT-derived homography" {
  // (0,0),(4,1),(6,7),(1,5): dx3 = 0-4+6-1 = 1 ≠ 0 → 射影ブランチ。
  // レビュー提案の (0,0),(4,1),(5,6),(1,5) は p1-p2+p3-p4 = (0,0) の
  // 平行四辺形でアフィンブランチに落ちるため、射影ブランチ用には
  // p3 を (6,7) に変えた四角形を使う（アフィンブランチは下の別テスト）。
  let m = square_to_quadrilateral(
    { x: 0.0, y: 0.0 },
    { x: 4.0, y: 1.0 },
    { x: 6.0, y: 7.0 },
    { x: 1.0, y: 5.0 },
  )
  // 期待値: 8x8 DLT を Gaussian elimination で解いた h（h22=1）を
  // jsQR レイアウトへ転置したもの（homography-oracle.mjs の出力）。
  let expected : FixedArray[Double] = [
    3.5384615384615388, // a11 = h00
    0.88461538461538469, // a12 = h10
    -0.11538461538461538, // a13 = h20
    0.84615384615384615, // a21 = h01
    4.2307692307692308, // a22 = h11
    -0.15384615384615388, // a23 = h21
    0.0, // a31 = h02
    0.0, // a32 = h12
    1.0, // a33 = h22
  ]
  assert_matrix9(m, expected, 1.0e-9)
}

test "quadrilateral_to_square projective branch matches numerically inverted homography" {
  let m = quadrilateral_to_square(
    { x: 0.0, y: 0.0 },
    { x: 4.0, y: 1.0 },
    { x: 6.0, y: 7.0 },
    { x: 1.0, y: 5.0 },
  )
  // 期待値: 上の H を Gaussian elimination で数値的に逆行列化し
  // m8=1 に正規化したもの。quadrilateral_to_square は随伴行列
  // （逆行列の det 倍）を返すため、実測側も正規化してから比較する。
  let expected : FixedArray[Double] = [
    0.29748283752860405, // a11
    -0.062200956937799042, // a12
    0.024755564801331380, // a13
    -0.059496567505720813, // a21
    0.24880382775119617, // a22
    0.031412523403370099, // a23
    0.0, // a31
    0.0, // a32
    1.0, // a33
  ]
  assert_matrix9(normalize9(m), expected, 1.0e-9)
}

test "square_to_quadrilateral affine branch matches DLT-derived homography" {
  // (0,0),(4,1),(5,6),(1,5): p1-p2+p3-p4 = (0,0) の平行四辺形
  // → アフィンブランチ（a13 = a23 = 0）を通る。
  let m = square_to_quadrilateral(
    { x: 0.0, y: 0.0 },
    { x: 4.0, y: 1.0 },
    { x: 5.0, y: 6.0 },
    { x: 1.0, y: 5.0 },
  )
  let expected : FixedArray[Double] = [
    4.0, 1.0, 0.0, // a11 a12 a13
    1.0, 5.0, 0.0, // a21 a22 a23
    0.0, 0.0, 1.0, // a31 a32 a33
  ]
  assert_matrix9(m, expected, 1.0e-9)
}

test "quadrilateral_to_square affine branch matches numerically inverted homography" {
  let m = quadrilateral_to_square(
    { x: 0.0, y: 0.0 },
    { x: 4.0, y: 1.0 },
    { x: 5.0, y: 6.0 },
    { x: 1.0, y: 5.0 },
  )
  let expected : FixedArray[Double] = [
    0.26315789473684209, // a11 = 5/19
    -0.052631578947368418, // a12 = -1/19
    0.0, // a13
    -0.052631578947368418, // a21 = -1/19
    0.21052631578947367, // a22 = 4/19
    0.0, // a23
    0.0, // a31
    0.0, // a32
    1.0, // a33
  ]
  assert_matrix9(normalize9(m), expected, 1.0e-9)
}

test "times matches independently computed conventional matrix product" {
  // A, B は jsQR レイアウトの手選び行列。期待値は慣用の row-major 3x3 へ
  // 変換（H[r][c] = m[c*3+r]）してから通常の行列積 H_A * H_B を計算し、
  // jsQR レイアウトへ戻したもの（homography-oracle.mjs の出力）。
  // times(a,b) は「b を先に適用し、次に a」の合成 = H_a * H_b に対応する。
  let a : FixedArray[Double] = [2.0, 0.5, 0.1, -1.0, 3.0, 0.2, 4.0, -2.0, 1.0]
  let b : FixedArray[Double] = [1.0, -0.5, 0.3, 2.0, 1.5, -0.1, -3.0, 0.7, 2.0]
  let m = times(a, b)
  let expected : FixedArray[Double] = [
    3.7000000000000002, // a11
    -1.6000000000000001, // a12
    0.29999999999999999, // a13
    2.1000000000000001, // a21
    5.7000000000000002, // a22
    0.40000000000000002, // a23
    1.2999999999999998, // a31
    -3.4000000000000004, // a32
    1.8399999999999999, // a33
  ]
  assert_matrix9(m, expected, 1.0e-9)
}
