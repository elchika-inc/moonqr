///| 2次元座標（Double）。ジオメトリ・輝度計算全般で使用する（later tasks: locator 等）。
pub(all) struct Point {
  x : Double
  y : Double
}

///| 二値画像行列。0/1 を Int で保持する（jsQR `BitMatrix` 相当）。
pub struct BitMatrix {
  width : Int
  height : Int
  data : FixedArray[Int]
}

///| 全要素 false（0）で初期化した width×height 行列を作る。
pub fn BitMatrix::make(width : Int, height : Int) -> BitMatrix {
  { width, height, data: FixedArray::make(width * height, 0) }
}

///| (x, y) の値を返す。範囲外は false（jsQR 同様クラッシュしない）。
pub fn BitMatrix::get(self : BitMatrix, x : Int, y : Int) -> Bool {
  if x < 0 || x >= self.width || y < 0 || y >= self.height {
    false
  } else {
    self.data[y * self.width + x] != 0
  }
}

///| (x, y) に値を書き込む。
pub fn BitMatrix::set(self : BitMatrix, x : Int, y : Int, v : Bool) -> Unit {
  self.data[y * self.width + x] = if v { 1 } else { 0 }
}
