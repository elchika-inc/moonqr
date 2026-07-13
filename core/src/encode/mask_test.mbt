test "mask conditions" {
  // mask 0: (x+y) % 2 == 0
  assert_true(@encode.mask_bit(0, 0, 0))
  assert_false(@encode.mask_bit(0, 1, 0))
  // mask 1: y % 2 == 0
  assert_true(@encode.mask_bit(1, 5, 0))
  // mask 6: ((x*y)%2 + (x*y)%3) % 2 == 0
  assert_true(@encode.mask_bit(6, 0, 0))
}

test "apply_mask twice is identity on data area" {
  let m = @encode.Matrix::new(1)
  @encode.place_function_patterns(m, 1)
  let cw : Array[Int] = []
  for i = 0; i < 26; i = i + 1 {
    cw.push(i * 7 % 256)
  }
  @encode.place_data(m, cw)
  let before : Array[Bool] = []
  for y = 0; y < 21; y = y + 1 {
    for x = 0; x < 21; x = x + 1 {
      before.push(m.get(x, y))
    }
  }
  @encode.apply_mask(m, 3)
  @encode.apply_mask(m, 3)
  for y = 0; y < 21; y = y + 1 {
    for x = 0; x < 21; x = x + 1 {
      assert_eq(m.get(x, y), before[y * 21 + x])
    }
  }
}

test "choose_mask returns valid index and leaves data area unmasked" {
  let m = @encode.Matrix::new(1)
  @encode.place_function_patterns(m, 1)
  let cw : Array[Int] = []
  for i = 0; i < 26; i = i + 1 {
    cw.push(i * 31 % 256)
  }
  @encode.place_data(m, cw)
  let before : Array[Bool] = []
  for y = 0; y < 21; y = y + 1 {
    for x = 0; x < 21; x = x + 1 {
      before.push(m.get(x, y))
    }
  }
  let best = @encode.choose_mask(m, @encode.EcLevel::M)
  assert_true(best >= 0 && best <= 7)
  // 契約: データ領域（非機能セル）は choose_mask 前と同一
  for y = 0; y < 21; y = y + 1 {
    for x = 0; x < 21; x = x + 1 {
      if !m.is_function(x, y) {
        assert_eq(m.get(x, y), before[y * 21 + x])
      }
    }
  }
}

test "penalty rule examples" {
  // 全白 21x21: N1 = 行21本×(21-5+1)…ではなく「5連続で3点+超過1点/個」
  // 全白行1本 = 3 + (21-5) = 19点。行21+列21 = 798。N2 = 20*20*3=1200。
  // N4 = 全白なので |0-50|/5 = 10 -> 100点。
  let m = @encode.Matrix::new(1) // 全白・機能パターンなし
  let p = @encode.penalty(m)
  assert_eq(p, 798 + 1200 + 100)
}
