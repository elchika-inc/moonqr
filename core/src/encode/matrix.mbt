pub struct Matrix {
  size : Int
  modules : FixedArray[Bool]
  function : FixedArray[Bool] // 機能パターン領域（データ配置対象外）
}

pub fn Matrix::new(version : Int) -> Matrix {
  let size = version * 4 + 17
  {
    size,
    modules: FixedArray::make(size * size, false),
    function: FixedArray::make(size * size, false),
  }
}

pub fn get(self : Matrix, x : Int, y : Int) -> Bool {
  self.modules[y * self.size + x]
}

pub fn set(self : Matrix, x : Int, y : Int, v : Bool) -> Unit {
  self.modules[y * self.size + x] = v
}

pub fn is_function(self : Matrix, x : Int, y : Int) -> Bool {
  self.function[y * self.size + x]
}

fn set_function(self : Matrix, x : Int, y : Int, v : Bool) -> Unit {
  self.set(x, y, v)
  self.function[y * self.size + x] = true
}

///| 7x7 ファインダ＋白セパレータを (ox, oy) 起点で描く
fn place_finder(m : Matrix, ox : Int, oy : Int) -> Unit {
  for dy = -1; dy <= 7; dy = dy + 1 {
    for dx = -1; dx <= 7; dx = dx + 1 {
      let x = ox + dx
      let y = oy + dy
      if x >= 0 && x < m.size && y >= 0 && y < m.size {
        let in7 = dx >= 0 && dx <= 6 && dy >= 0 && dy <= 6
        let dark = in7 &&
          (dx == 0 || dx == 6 || dy == 0 || dy == 6 ||
          (dx >= 2 && dx <= 4 && dy >= 2 && dy <= 4))
        m.set_function(x, y, dark)
      }
    }
  }
}

pub fn place_function_patterns(m : Matrix, version : Int) -> Unit {
  place_finder(m, 0, 0)
  place_finder(m, m.size - 7, 0)
  place_finder(m, 0, m.size - 7)
  // タイミングパターン（row/col 6、偶数座標が黒）
  for i = 8; i < m.size - 8; i = i + 1 {
    let dark = i % 2 == 0
    if !m.is_function(i, 6) {
      m.set_function(i, 6, dark)
    }
    if !m.is_function(6, i) {
      m.set_function(6, i, dark)
    }
  }
  // アライメントパターン（ファインダと重なる位置は除外）
  let pos = alignment_positions(version)
  for a = 0; a < pos.length(); a = a + 1 {
    for b = 0; b < pos.length(); b = b + 1 {
      let cx = pos[a]
      let cy = pos[b]
      // 3つのファインダ位置と重なるものはスキップ
      let overlaps = (cx <= 8 && cy <= 8) ||
        (cx >= m.size - 9 && cy <= 8) || (cx <= 8 && cy >= m.size - 9)
      if !overlaps {
        for dy = -2; dy <= 2; dy = dy + 1 {
          for dx = -2; dx <= 2; dx = dx + 1 {
            let dark = dx == -2 || dx == 2 || dy == -2 || dy == 2 ||
              (dx == 0 && dy == 0)
            m.set_function(cx + dx, cy + dy, dark)
          }
        }
      }
    }
  }
  // ダークモジュール
  m.set_function(8, version * 4 + 9, true)
  // フォーマット情報領域の予約（値は Task 10 で書く）
  for i = 0; i <= 8; i = i + 1 {
    if !m.is_function(i, 8) {
      m.set_function(i, 8, false)
    }
    if !m.is_function(8, i) {
      m.set_function(8, i, false)
    }
  }
  for i = 0; i < 8; i = i + 1 {
    if !m.is_function(m.size - 1 - i, 8) {
      m.set_function(m.size - 1 - i, 8, false)
    }
    if !m.is_function(8, m.size - 1 - i) {
      m.set_function(8, m.size - 1 - i, false)
    }
  }
  // バージョン情報領域（v7+、6x3 を2箇所）予約
  if version >= 7 {
    for i = 0; i < 6; i = i + 1 {
      for j = 0; j < 3; j = j + 1 {
        m.set_function(i, m.size - 11 + j, false)
        m.set_function(m.size - 11 + j, i, false)
      }
    }
  }
}

///| データビットを右下から2列単位のジグザグで配置（col 6 スキップ）
pub fn place_data(m : Matrix, codewords : Array[Int]) -> Unit {
  let mut bit_index = 0
  let total_bits = codewords.length() * 8
  let mut col = m.size - 1
  let mut upward = true
  while col > 0 {
    if col == 6 {
      col = col - 1 // タイミング列をスキップ
    }
    for step = 0; step < m.size; step = step + 1 {
      let y = if upward { m.size - 1 - step } else { step }
      for dx = 0; dx < 2; dx = dx + 1 {
        let x = col - dx
        if !m.is_function(x, y) && bit_index < total_bits {
          let cw = codewords[bit_index / 8]
          let bit = ((cw >> (7 - bit_index % 8)) & 1) == 1
          m.set(x, y, bit)
          bit_index = bit_index + 1
        }
      }
    }
    upward = !upward
    col = col - 2
  }
}
