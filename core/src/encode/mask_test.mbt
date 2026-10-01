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

fn penalty_checkerboard() -> @encode.Matrix {
  let m = @encode.Matrix::new(1)
  for y = 0; y < 21; y = y + 1 {
    for x = 0; x < 21; x = x + 1 {
      m.set(x, y, (x + y) % 2 == 0)
    }
  }
  m
}

fn penalty_with_dark_modules(dark_modules : Int) -> @encode.Matrix {
  let m = @encode.Matrix::new(1)
  // 行の左から順に黒を置くので、境目以外は全黒行か全白行になる。
  for y = 0; y < 21; y = y + 1 {
    for x = 0; x < 21; x = x + 1 {
      m.set(x, y, y * 21 + x < dark_modules)
    }
  }
  m
}

test "同色の連続が4マス → ペナルティ0点" {
  let m = penalty_checkerboard()
  for x = 0; x < 4; x = x + 1 {
    m.set(x, 0, true)
  }
  m.set(4, 0, false)
  // N1=0（最大4連続）、N2=0、N3=0、N4=0（黒222/441、50%）。
  assert_eq(@encode.penalty(m), 0)
}

test "同色の連続が5マス → ペナルティ3点" {
  let m = penalty_checkerboard()
  for x = 0; x < 5; x = x + 1 {
    m.set(x, 0, true)
  }
  m.set(5, 0, false)
  // N1=3（5連続が1本）、N2=0、N3=0、N4=0（黒223/441、50%）。
  assert_eq(@encode.penalty(m), 3)
}

test "同色の連続が6マス → ペナルティ4点" {
  let m = penalty_checkerboard()
  for x = 0; x < 6; x = x + 1 {
    m.set(x, 0, true)
  }
  m.set(6, 0, false)
  // N1=3+1=4（6連続が1本）、N2=0、N3=0、N4=0（黒223/441、50%）。
  assert_eq(@encode.penalty(m), 4)
}

test "同色2x2が右下の角にある → ペナルティ3点" {
  let m = penalty_checkerboard()
  m.set(19, 20, true)
  m.set(20, 19, true)
  // N1=0（最大3連続）、N2=1個*3=3、N3=0、N4=0（黒223/441、50%）。
  assert_eq(@encode.penalty(m), 3)
}

test "後ろに0000を持つ行パターンが最終列で終わる → ペナルティ40点" {
  let m = penalty_checkerboard()
  let pattern = [true, false, true, true, true, false, true, false, false, false, false]
  m.set(9, 0, true)
  for x = 0; x < 11; x = x + 1 {
    m.set(10 + x, 0, pattern[x])
  }
  // N1=0（最大4連続）、N2=0、N3=1個*40=40、N4=0（黒221/441、50%）。
  assert_eq(@encode.penalty(m), 40)
}

test "前に0000を持つ行パターンが最終列で終わる → ペナルティ40点" {
  let m = penalty_checkerboard()
  let pattern = [false, false, false, false, true, false, true, true, true, false, true]
  m.set(9, 0, true) // 直前を黒にし、先頭0000が5連続になるのを防ぐ。
  for x = 0; x < 11; x = x + 1 {
    m.set(10 + x, 0, pattern[x])
  }
  // N1=0（最大4連続）、N2=0、N3=1個*40=40、N4=0（黒221/441、50%）。
  assert_eq(@encode.penalty(m), 40)
}

test "後ろに0000を持つ列パターンが最終行で終わる → ペナルティ40点" {
  let m = penalty_checkerboard()
  let pattern = [true, false, true, true, true, false, true, false, false, false, false]
  m.set(0, 9, true)
  for y = 0; y < 11; y = y + 1 {
    m.set(0, 10 + y, pattern[y])
  }
  // N1=0（最大4連続）、N2=0、N3=1個*40=40、N4=0（黒221/441、50%）。
  assert_eq(@encode.penalty(m), 40)
}

test "前に0000を持つ列パターンが最終行で終わる → ペナルティ40点" {
  let m = penalty_checkerboard()
  let pattern = [false, false, false, false, true, false, true, true, true, false, true]
  m.set(0, 9, true) // 直前を黒にし、先頭0000が5連続になるのを防ぐ。
  for y = 0; y < 11; y = y + 1 {
    m.set(0, 10 + y, pattern[y])
  }
  // N1=0（最大4連続）、N2=0、N3=1個*40=40、N4=0（黒221/441、50%）。
  assert_eq(@encode.penalty(m), 40)
}

test "黒198/441で45%の直前 → ペナルティ1901点" {
  let m = penalty_with_dark_modules(198)
  // N1=20*19+17+21*17=754、N2=(18*20+19)*3=1137、N3=0。
  // N4: 19800/441=44%、偏差6 → 10点。部分行は黒9・白12。
  assert_eq(@encode.penalty(m), 754 + 1137 + 0 + 10)
}

test "黒199/441で45%の直後 → ペナルティ1901点" {
  let m = penalty_with_dark_modules(199)
  // N1=20*19+17+21*17=754、N2=(18*20+19)*3=1137、N3=0。
  // N4: 19900/441=45%、偏差5 → 10点。部分行は黒10・白11。
  assert_eq(@encode.penalty(m), 754 + 1137 + 0 + 10)
}

test "黒201/441で50%未満の丸めを含む → ペナルティ1901点" {
  let m = penalty_with_dark_modules(201)
  // N1=20*19+17+21*17=754、N2=(18*20+19)*3=1137、N3=0。
  // N4: 20100/441=45%、偏差5 → 10点。部分行は黒12・白9。
  assert_eq(@encode.penalty(m), 754 + 1137 + 0 + 10)
}

test "黒202/441で46%の直前 → ペナルティ1901点" {
  let m = penalty_with_dark_modules(202)
  // N1=20*19+17+21*17=754、N2=(18*20+19)*3=1137、N3=0。
  // N4: 20200/441=45%、偏差5 → 10点。部分行は黒13・白8。
  assert_eq(@encode.penalty(m), 754 + 1137 + 0 + 10)
}

test "黒203/441で46%の直後 → ペナルティ1891点" {
  let m = penalty_with_dark_modules(203)
  // N1=20*19+17+21*17=754、N2=(18*20+19)*3=1137、N3=0。
  // N4: 20300/441=46%、偏差4 → 0点。部分行は黒14・白7。
  assert_eq(@encode.penalty(m), 754 + 1137 + 0 + 0)
}

test "黒240/441で50%超の丸めを含む → ペナルティ1891点" {
  let m = penalty_with_dark_modules(240)
  // N1=20*19+17+21*17=754、N2=(18*20+19)*3=1137、N3=0。
  // N4: 24000/441=54%、偏差4 → 0点。部分行は黒9・白12。
  assert_eq(@encode.penalty(m), 754 + 1137 + 0 + 0)
}

test "黒242/441で55%の直前 → ペナルティ1891点" {
  let m = penalty_with_dark_modules(242)
  // N1=20*19+17+21*17=754、N2=(18*20+19)*3=1137、N3=0。
  // N4: 24200/441=54%、偏差4 → 0点。部分行は黒11・白10。
  assert_eq(@encode.penalty(m), 754 + 1137 + 0 + 0)
}

test "黒243/441で55%の直後 → ペナルティ1901点" {
  let m = penalty_with_dark_modules(243)
  // N1=20*19+17+21*17=754、N2=(18*20+19)*3=1137、N3=0。
  // N4: 24300/441=55%、偏差5 → 10点。部分行は黒12・白9。
  assert_eq(@encode.penalty(m), 754 + 1137 + 0 + 10)
}

test "全黒21x21 → ペナルティ2098点" {
  let m = penalty_with_dark_modules(441)
  // N1=42*(3+16)=798、N2=20*20*3=1200、N3=0、N4=50/5*10=100。
  assert_eq(@encode.penalty(m), 798 + 1200 + 0 + 100)
}

test "市松模様21x21 → ペナルティ0点" {
  let m = penalty_checkerboard()
  // N1=0（連続なし）、N2=0、N3=0、N4=0（黒221/441、50%）。
  assert_eq(@encode.penalty(m), 0)
}
