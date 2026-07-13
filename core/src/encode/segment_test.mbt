test "mode detection" {
  assert_eq(@encode.detect_mode("0123456789"), @encode.numeric())
  assert_eq(@encode.detect_mode("HELLO WORLD $1"), @encode.alphanumeric())
  assert_eq(@encode.detect_mode("hello"), @encode.byte()) // 小文字はalnum外
  assert_eq(@encode.detect_mode("こんにちは"), @encode.byte())
}

test "cci bits per version range" {
  assert_eq(@encode.cci_bits(@encode.numeric(), 1), 10)
  assert_eq(@encode.cci_bits(@encode.numeric(), 10), 12)
  assert_eq(@encode.cci_bits(@encode.numeric(), 27), 14)
  assert_eq(@encode.cci_bits(@encode.alphanumeric(), 1), 9)
  assert_eq(@encode.cci_bits(@encode.byte(), 1), 8)
  assert_eq(@encode.cci_bits(@encode.byte(), 10), 16)
}

test "numeric segment: 01234567 -> known bit pattern" {
  // ISO 18004 の古典例: "01234567" numeric v1
  // 012=0000001100, 345=0101011001, 67=1000011
  let w = @encode.BitWriter::new()
  @encode.write_segment(w, "01234567", @encode.numeric(), 1)
  // mode(0001) + cci(0000001000=8) + data
  assert_eq(w.bit_length(), 4 + 10 + 10 + 10 + 7)
}

test "alphanumeric segment: AC-42" {
  // A=10,C=12 -> 10*45+12=462; -=41,4=4 -> 41*45+4=1849; 2=2
  let w = @encode.BitWriter::new()
  @encode.write_segment(w, "AC-42", @encode.alphanumeric(), 1)
  assert_eq(w.bit_length(), 4 + 9 + 11 + 11 + 6)
}

test "utf8 encode multibyte" {
  assert_eq(@encode.utf8_encode("A"), [0x41])
  assert_eq(@encode.utf8_encode("é"), [0xC3, 0xA9])
  assert_eq(@encode.utf8_encode("あ"), [0xE3, 0x81, 0x82])
  assert_eq(@encode.utf8_encode("🦑"), [0xF0, 0x9F, 0xA6, 0x91])
}
