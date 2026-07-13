test "bitwriter packs msb first" {
  let w = @encode.BitWriter::new()
  w.write(0b0100, 4)  // byte mode indicator
  w.write(3, 8)       // 長さ3
  assert_eq(w.bit_length(), 12)
  let cw = w.to_codewords() // 8bit境界までは0詰めせず、to_codewordsで末尾0詰め
  assert_eq(cw, [0b01000000, 0b00110000])
}
