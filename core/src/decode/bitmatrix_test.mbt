test "make initializes all cells to false" {
  let m = @decode.BitMatrix::make(5, 3)
  for y = 0; y < 3; y = y + 1 {
    for x = 0; x < 5; x = x + 1 {
      assert_false(m.get(x, y))
    }
  }
}

test "set then get roundtrips" {
  let m = @decode.BitMatrix::make(4, 4)
  m.set(1, 2, true)
  assert_true(m.get(1, 2))
  assert_false(m.get(0, 2))
  assert_false(m.get(1, 1))
  m.set(1, 2, false)
  assert_false(m.get(1, 2))
}

test "get out of range returns false without crashing" {
  let m = @decode.BitMatrix::make(3, 3)
  assert_false(m.get(-1, 0))
  assert_false(m.get(0, -1))
  assert_false(m.get(3, 0))
  assert_false(m.get(0, 3))
  assert_false(m.get(100, 100))
  assert_false(m.get(-100, -100))
}
