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

test "encode still works and shrinks the version when splitting helps" {
  // 単一モードなら v4、最適分割なら v3 に収まる（実測値）
  let text = "https://ex.com/id/123456789012345678901234567890"
  let m = @encode.encode(text, @encode.EcLevel::M, None)
  match m {
    Some(matrix) => assert_eq(matrix.size, 29) // v3 = 29x29
    None => abort("encode returned None")
  }
}

test "Numericで01234567を書く → 3桁単位と余りのコードワードになる" {
  let w = @encode.BitWriter::new()
  @encode.write_segment(w, "01234567", @encode.Mode::Numeric, 1)
  assert_eq(w.bit_length(), 41)
  assert_eq(w.to_codewords(), [16, 32, 12, 86, 97, 128])
}

test "Numericで1桁の7を書く → データ部が4bitになる" {
  let w = @encode.BitWriter::new()
  @encode.write_segment(w, "7", @encode.Mode::Numeric, 1)
  assert_eq(w.bit_length(), 18)
  assert_eq(w.to_codewords(), [16, 5, 192])
}

test "Numericで2桁の67を書く → データ部が7bitになる" {
  let w = @encode.BitWriter::new()
  @encode.write_segment(w, "67", @encode.Mode::Numeric, 1)
  assert_eq(w.bit_length(), 21)
  assert_eq(w.to_codewords(), [16, 10, 24])
}

test "AlphanumericでAC-42を書く → 文字対と余りのコードワードになる" {
  let w = @encode.BitWriter::new()
  @encode.write_segment(w, "AC-42", @encode.Mode::Alphanumeric, 1)
  assert_eq(w.bit_length(), 41)
  assert_eq(w.to_codewords(), [32, 41, 206, 231, 33, 0])
}

test "ByteでAéあ🦑を書く → UTF-8の10バイトを文字数指示子とデータに使う" {
  let w = @encode.BitWriter::new()
  @encode.write_segment(w, "Aéあ🦑", @encode.Mode::Byte, 1)
  assert_eq(w.bit_length(), 92)
  assert_eq(w.to_codewords(), [64, 164, 28, 58, 158, 56, 24, 47, 9, 250, 105, 16])
}

test "Numericで空文字を書く → モードと文字数0の14bitだけを書く" {
  let w = @encode.BitWriter::new()
  @encode.write_segment(w, "", @encode.Mode::Numeric, 1)
  assert_eq(w.bit_length(), 14)
  assert_eq(w.to_codewords(), [16, 0])
}

test "Alphanumericで空文字を書く → モードと文字数0の13bitだけを書く" {
  let w = @encode.BitWriter::new()
  @encode.write_segment(w, "", @encode.Mode::Alphanumeric, 1)
  assert_eq(w.bit_length(), 13)
  assert_eq(w.to_codewords(), [32, 0])
}

test "Byteで空文字を書く → モードと文字数0の12bitだけを書く" {
  let w = @encode.BitWriter::new()
  @encode.write_segment(w, "", @encode.Mode::Byte, 1)
  assert_eq(w.bit_length(), 12)
  assert_eq(w.to_codewords(), [64, 0])
}

test "panic Alphanumericで範囲外のaを書く → abortする" {
  let w = @encode.BitWriter::new()
  @encode.write_segment(w, "a", @encode.Mode::Alphanumeric, 1)
}
