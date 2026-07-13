test "add is xor" {
  assert_eq(@gf256.add(0x53, 0xCA), 0x99)
}

test "mul basic identities" {
  assert_eq(@gf256.mul(0, 123), 0)
  assert_eq(@gf256.mul(123, 0), 0)
  assert_eq(@gf256.mul(1, 123), 123)
  assert_eq(@gf256.mul(2, 3), 6)        // 縮約なし
  assert_eq(@gf256.mul(128, 2), 29)     // 0x100 ^ 0x11D = 0x1D
}

test "mul is commutative (spot)" {
  for a = 1; a < 256; a = a + 17 {
    for b = 1; b < 256; b = b + 13 {
      assert_eq(@gf256.mul(a, b), @gf256.mul(b, a))
    }
  }
}

test "div inverts mul for all nonzero pairs" {
  for a = 1; a < 256; a = a + 1 {
    for b = 1; b < 256; b = b + 1 {
      assert_eq(@gf256.div(@gf256.mul(a, b), b), a)
    }
  }
}

test "exp log roundtrip" {
  for a = 1; a < 256; a = a + 1 {
    assert_eq(@gf256.exp(@gf256.log(a)), a)
  }
}
