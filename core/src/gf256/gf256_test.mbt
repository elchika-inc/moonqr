test "gf add is xor" {
  assert_eq(@gf256.add(0x53, 0xCA), 0x99)
}
