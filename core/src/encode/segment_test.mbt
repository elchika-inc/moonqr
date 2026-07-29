test "mode detection" {
  assert_eq(@encode.detect_mode("0123456789"), @encode.Mode::Numeric)
  assert_eq(@encode.detect_mode("HELLO WORLD $1"), @encode.Mode::Alphanumeric)
  assert_eq(@encode.detect_mode("hello"), @encode.Mode::Byte) // 小文字はalnum外
  assert_eq(@encode.detect_mode("こんにちは"), @encode.Mode::Byte)
}

test "cci bits per version range" {
  assert_eq(@encode.cci_bits(@encode.Mode::Numeric, 1), 10)
  assert_eq(@encode.cci_bits(@encode.Mode::Numeric, 10), 12)
  assert_eq(@encode.cci_bits(@encode.Mode::Numeric, 27), 14)
  assert_eq(@encode.cci_bits(@encode.Mode::Alphanumeric, 1), 9)
  assert_eq(@encode.cci_bits(@encode.Mode::Byte, 1), 8)
  assert_eq(@encode.cci_bits(@encode.Mode::Byte, 10), 16)
}

test "numeric segment: 01234567 -> known bit pattern" {
  // ISO 18004 の古典例: "01234567" numeric v1
  // 012=0000001100, 345=0101011001, 67=1000011
  let w = @encode.BitWriter::new()
  @encode.write_segment(w, "01234567", @encode.Mode::Numeric, 1)
  // mode(0001) + cci(0000001000=8) + data
  assert_eq(w.bit_length(), 4 + 10 + 10 + 10 + 7)
}

test "alphanumeric segment: AC-42" {
  // A=10,C=12 -> 10*45+12=462; -=41,4=4 -> 41*45+4=1849; 2=2
  let w = @encode.BitWriter::new()
  @encode.write_segment(w, "AC-42", @encode.Mode::Alphanumeric, 1)
  assert_eq(w.bit_length(), 4 + 9 + 11 + 11 + 6)
}

test "utf8 encode multibyte" {
  assert_eq(@encode.utf8_encode("A"), [0x41])
  assert_eq(@encode.utf8_encode("é"), [0xC3, 0xA9])
  assert_eq(@encode.utf8_encode("あ"), [0xE3, 0x81, 0x82])
  assert_eq(@encode.utf8_encode("🦑"), [0xF0, 0x9F, 0xA6, 0x91])
}

test "char_mode classifies by the most restrictive mode" {
  assert_eq(@encode.char_mode('5'), @encode.Mode::Numeric)
  assert_eq(@encode.char_mode('A'), @encode.Mode::Alphanumeric)
  assert_eq(@encode.char_mode(' '), @encode.Mode::Alphanumeric)
  assert_eq(@encode.char_mode(':'), @encode.Mode::Alphanumeric)
  assert_eq(@encode.char_mode('a'), @encode.Mode::Byte)
  assert_eq(@encode.char_mode('あ'), @encode.Mode::Byte)
}

test "runs_of groups consecutive chars of the same mode" {
  let rs = @encode.runs_of("ab123XY")
  assert_eq(rs.length(), 3)
  assert_eq(rs[0].mode, @encode.Mode::Byte)
  assert_eq(rs[0].start, 0)
  assert_eq(rs[0].len, 2)
  assert_eq(rs[1].mode, @encode.Mode::Numeric)
  assert_eq(rs[1].start, 2)
  assert_eq(rs[1].len, 3)
  assert_eq(rs[2].mode, @encode.Mode::Alphanumeric)
  assert_eq(rs[2].start, 5)
  assert_eq(rs[2].len, 2)
}

test "runs_of on a single-mode string yields one run" {
  let rs = @encode.runs_of("123456")
  assert_eq(rs.length(), 1)
  assert_eq(rs[0].mode, @encode.Mode::Numeric)
  assert_eq(rs[0].len, 6)
}

test "runs_of on empty string yields no runs" {
  assert_eq(@encode.runs_of("").length(), 0)
}
