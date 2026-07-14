///| 移植元: jsQR (Apache-2.0), commit 8e6a036beafa7053dd44b1b76ac578d22b1b3311
///| https://github.com/cozmo/jsQR/blob/8e6a036beafa7053dd44b1b76ac578d22b1b3311/src/extractor/index.ts
///| zxing 系 `PerspectiveTransform`（射影変換の3x3行列）で、locator が求めた
///| 3ファインダ＋アライメント中心（画像px空間の四角形）とモジュール格子
///| （0..dimension の理想正方格子）を対応付け、各モジュール中心を最近傍
///| サンプリングして dimension x dimension のモジュール行列を復元する。
///|
///| 3x3行列は FixedArray[Double] の9要素で表現する（jsQR
///| `PerspectiveTransform { a11..a33 }` 相当）。インデックス対応:
///|   0=a11 1=a12 2=a13 3=a21 4=a22 5=a23 6=a31 7=a32 8=a33
///| 行列 [x y 1] に対して x' = (a11 x + a21 y + a31) / denom,
///|                     y' = (a12 x + a22 y + a32) / denom,
///|   denom = a13 x + a23 y + a33 という規約（jsQR と同じ）。

///| 単位正方形 (p1,p2,p3,p4 を反時計/時計いずれかの順で頂点とする)
///| から四角形 p1,p2,p3,p4 への射影変換を作る（jsQR `squareToQuadrilateral`）。
fn square_to_quadrilateral(p1 : Point, p2 : Point, p3 : Point, p4 : Point) -> FixedArray[Double] {
  let dx3 = p1.x - p2.x + p3.x - p4.x
  let dy3 = p1.y - p2.y + p3.y - p4.y
  let m = FixedArray::make(9, 0.0)
  if dx3 == 0.0 && dy3 == 0.0 {
    // Affine（4点が平行四辺形をなす特殊ケース）
    m[0] = p2.x - p1.x // a11
    m[1] = p2.y - p1.y // a12
    m[2] = 0.0 // a13
    m[3] = p3.x - p2.x // a21
    m[4] = p3.y - p2.y // a22
    m[5] = 0.0 // a23
    m[6] = p1.x // a31
    m[7] = p1.y // a32
    m[8] = 1.0 // a33
  } else {
    let dx1 = p2.x - p3.x
    let dx2 = p4.x - p3.x
    let dy1 = p2.y - p3.y
    let dy2 = p4.y - p3.y
    let denominator = dx1 * dy2 - dx2 * dy1
    let a13 = (dx3 * dy2 - dx2 * dy3) / denominator
    let a23 = (dx1 * dy3 - dx3 * dy1) / denominator
    m[0] = p2.x - p1.x + a13 * p2.x // a11
    m[1] = p2.y - p1.y + a13 * p2.y // a12
    m[2] = a13
    m[3] = p4.x - p1.x + a23 * p4.x // a21
    m[4] = p4.y - p1.y + a23 * p4.y // a22
    m[5] = a23
    m[6] = p1.x // a31
    m[7] = p1.y // a32
    m[8] = 1.0 // a33
  }
  m
}

///| `square_to_quadrilateral` の逆変換（四角形 → 単位正方形）。
///| 随伴行列（adjoint）が3x3同次変換の逆行列としてそのまま使える
///| （jsQR `quadrilateralToSquare` 相当。スケール不変な同次座標のため
///| 行列式で割る正規化は不要）。
fn quadrilateral_to_square(p1 : Point, p2 : Point, p3 : Point, p4 : Point) -> FixedArray[Double] {
  let s = square_to_quadrilateral(p1, p2, p3, p4)
  let m = FixedArray::make(9, 0.0)
  m[0] = s[4] * s[8] - s[5] * s[7] // a11 = a22*a33 - a23*a32
  m[1] = s[2] * s[7] - s[1] * s[8] // a12 = a13*a32 - a12*a33
  m[2] = s[1] * s[5] - s[2] * s[4] // a13 = a12*a23 - a13*a22
  m[3] = s[5] * s[6] - s[3] * s[8] // a21 = a23*a31 - a21*a33
  m[4] = s[0] * s[8] - s[2] * s[6] // a22 = a11*a33 - a13*a31
  m[5] = s[2] * s[3] - s[0] * s[5] // a23 = a13*a21 - a11*a23
  m[6] = s[3] * s[7] - s[4] * s[6] // a31 = a21*a32 - a22*a31
  m[7] = s[1] * s[6] - s[0] * s[7] // a32 = a12*a31 - a11*a32
  m[8] = s[0] * s[4] - s[1] * s[3] // a33 = a11*a22 - a12*a21
  m
}

///| 3x3同次変換行列の積 `a * b`（jsQR `times`。合成は「先に b、次に a」）。
fn times(a : FixedArray[Double], b : FixedArray[Double]) -> FixedArray[Double] {
  let m = FixedArray::make(9, 0.0)
  m[0] = a[0] * b[0] + a[3] * b[1] + a[6] * b[2] // a11
  m[1] = a[1] * b[0] + a[4] * b[1] + a[7] * b[2] // a12
  m[2] = a[2] * b[0] + a[5] * b[1] + a[8] * b[2] // a13
  m[3] = a[0] * b[3] + a[3] * b[4] + a[6] * b[5] // a21
  m[4] = a[1] * b[3] + a[4] * b[4] + a[7] * b[5] // a22
  m[5] = a[2] * b[3] + a[5] * b[4] + a[8] * b[5] // a23
  m[6] = a[0] * b[6] + a[3] * b[7] + a[6] * b[8] // a31
  m[7] = a[1] * b[6] + a[4] * b[7] + a[7] * b[8] // a32
  m[8] = a[2] * b[6] + a[5] * b[7] + a[8] * b[8] // a33
  m
}

///| `extract` の返り値。`mapping` はモジュール座標（連続値、0..dimension）
///| を元画像のpx座標へ写す関数で、corners出力（Phase 2 Task 8以降）に使う。
pub struct ExtractResult {
  matrix : BitMatrix
  mapping : (Double, Double) -> Point
}

///| locator の検出結果からモジュール行列を切り出す（jsQR `extract` 相当）。
///| 理想モジュール格子（ファインダ中心 (3.5,3.5) など）から実画像の
///| ファインダ/アライメント中心への射影変換を求め、各モジュール中心
///| (x+0.5, y+0.5) を最近傍サンプリングする。範囲外は `BitMatrix::get`
///| が bounds-safe に false を返すため、jsQR 同様クラッシュしない。
pub fn extract(image : BitMatrix, location : QrLocation) -> ExtractResult {
  let dim = location.dimension.to_double()
  let q_to_s = quadrilateral_to_square(
    { x: 3.5, y: 3.5 },
    { x: dim - 3.5, y: 3.5 },
    { x: dim - 6.5, y: dim - 6.5 },
    { x: 3.5, y: dim - 3.5 },
  )
  let s_to_q = square_to_quadrilateral(
    location.top_left,
    location.top_right,
    location.alignment,
    location.bottom_left,
  )
  let transform = times(s_to_q, q_to_s)
  let mapping = fn(x : Double, y : Double) -> Point {
    let denominator = transform[2] * x + transform[5] * y + transform[8]
    {
      x: (transform[0] * x + transform[3] * y + transform[6]) / denominator,
      y: (transform[1] * x + transform[4] * y + transform[7]) / denominator,
    }
  }
  let matrix = BitMatrix::make(location.dimension, location.dimension)
  for y = 0; y < location.dimension; y = y + 1 {
    for x = 0; x < location.dimension; x = x + 1 {
      let source = mapping(x.to_double() + 0.5, y.to_double() + 0.5)
      matrix.set(x, y, image.get(source.x.floor().to_int(), source.y.floor().to_int()))
    }
  }
  { matrix, mapping }
}
