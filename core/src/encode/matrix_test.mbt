test "v1 matrix is 21x21 with finder patterns" {
  let m = @encode.Matrix::new(1)
  assert_eq(m.size, 21)
  @encode.place_function_patterns(m, 1)
  // ファインダ外周は黒
  assert_true(m.get(0, 0))
  assert_true(m.get(6, 0))
  assert_true(m.get(0, 6))
  // ファインダ内白リング
  assert_false(m.get(1, 1))
  // 中心3x3は黒
  assert_true(m.get(3, 3))
  // 右上ファインダ
  assert_true(m.get(20, 0))
  // タイミングパターン（交互）
  assert_true(m.get(8, 6))   // x=8 は黒（偶数=黒: (6,8)側で確認）
  assert_false(m.get(9, 6))
  // ダークモジュール (8, 4*1+9=13)
  assert_true(m.get(8, 13))
}

test "function area is reserved" {
  let m = @encode.Matrix::new(1)
  @encode.place_function_patterns(m, 1)
  assert_true(m.is_function(0, 0))    // ファインダ
  assert_true(m.is_function(8, 0))    // フォーマット領域
  assert_true(m.is_function(6, 10))   // タイミング
  assert_false(m.is_function(10, 10)) // データ領域
}

test "v2 has alignment pattern at (18,18)" {
  let m = @encode.Matrix::new(2)
  @encode.place_function_patterns(m, 2)
  assert_true(m.get(18, 18))          // 中心黒
  assert_false(m.get(17, 18))         // 白リング
  assert_true(m.get(16, 16))          // 外周黒
}

test "place_data fills all non-function modules" {
  let m = @encode.Matrix::new(1)
  @encode.place_function_patterns(m, 1)
  // v1 のデータモジュール数 = 26 codewords * 8 = 208
  let cw : Array[Int] = []
  for i = 0; i < 26; i = i + 1 {
    cw.push(0xFF) // 全1で埋めれば全データ位置が黒になる
  }
  @encode.place_data(m, cw)
  let mut dark_data = 0
  for y = 0; y < 21; y = y + 1 {
    for x = 0; x < 21; x = x + 1 {
      if !m.is_function(x, y) && m.get(x, y) {
        dark_data = dark_data + 1
      }
    }
  }
  assert_eq(dark_data, 208)
}

test "v1のフォーマット領域の交点 → (8,8)を白で予約する" {
  let m = @encode.Matrix::new(1)
  @encode.place_function_patterns(m, 1)
  assert_true(m.is_function(8, 8))
  assert_false(m.get(8, 8))
}

test "v6のバージョン情報候補位置 → データ領域のまま残す" {
  let m = @encode.Matrix::new(6)
  @encode.place_function_patterns(m, 6)
  assert_false(m.is_function(0, 30))
  assert_false(m.is_function(5, 32))
  assert_false(m.is_function(30, 0))
  assert_false(m.is_function(32, 5))
}

test "v7のバージョン情報領域 → 対称な2領域を白で予約する" {
  let m = @encode.Matrix::new(7)
  @encode.place_function_patterns(m, 7)
  assert_true(m.is_function(0, 34))
  assert_true(m.is_function(5, 36))
  assert_true(m.is_function(34, 0))
  assert_true(m.is_function(36, 5))
  assert_false(m.get(0, 34))
  assert_false(m.get(5, 36))
  assert_false(m.get(34, 0))
  assert_false(m.get(36, 5))
}
