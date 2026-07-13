test "format bits known vector" {
  // Thonky.com verification: L/mask0 and M/mask5
  assert_eq(@encode.format_bits(@encode.EcLevel::L, 0), 0b111011111000100)
  assert_eq(@encode.format_bits(@encode.EcLevel::M, 5), 0b100000011001110)
}

test "version bits known vector" {
  // Thonky.com verification: v7
  assert_eq(@encode.version_bits(7), 0b000111110010010100)
}
