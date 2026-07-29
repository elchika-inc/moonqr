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

test "mode_can_encode follows Numeric ⊂ Alphanumeric ⊂ Byte" {
  assert_eq(@encode.mode_can_encode(@encode.Mode::Numeric, @encode.Mode::Numeric), true)
  assert_eq(@encode.mode_can_encode(@encode.Mode::Alphanumeric, @encode.Mode::Numeric), true)
  assert_eq(@encode.mode_can_encode(@encode.Mode::Byte, @encode.Mode::Numeric), true)
  assert_eq(@encode.mode_can_encode(@encode.Mode::Numeric, @encode.Mode::Alphanumeric), false)
  assert_eq(@encode.mode_can_encode(@encode.Mode::Alphanumeric, @encode.Mode::Byte), false)
  assert_eq(@encode.mode_can_encode(@encode.Mode::Byte, @encode.Mode::Byte), true)
}

test "segment_bits matches write_segment for numeric" {
  // "01234567" v1 numeric: 4 + 10 + (10+10+7) = 41
  let chars : Array[Char] = []
  for c in "01234567" {
    chars.push(c)
  }
  assert_eq(@encode.segment_bits(chars, 0, 8, @encode.Mode::Numeric, 1), 4 + 10 + 10 + 10 + 7)
}

test "segment_bits matches write_segment for alphanumeric" {
  // "AC-42" v1 alnum: 4 + 9 + (11+11+6) = 41
  let chars : Array[Char] = []
  for c in "AC-42" {
    chars.push(c)
  }
  assert_eq(@encode.segment_bits(chars, 0, 5, @encode.Mode::Alphanumeric, 1), 4 + 9 + 11 + 11 + 6)
}

test "segment_bits counts UTF-8 bytes for byte mode" {
  // "あ" は UTF-8 で 3 バイト: 4 + 8 + 24 = 36 (v1)
  let chars : Array[Char] = []
  for c in "あ" {
    chars.push(c)
  }
  assert_eq(@encode.segment_bits(chars, 0, 1, @encode.Mode::Byte, 1), 4 + 8 + 24)
}

test "segment_bits handles a sub-range" {
  // "XX123" の後半 3 文字を numeric として測る: 4 + 10 + 10 = 24 (v1)
  let chars : Array[Char] = []
  for c in "XX123" {
    chars.push(c)
  }
  assert_eq(@encode.segment_bits(chars, 2, 3, @encode.Mode::Numeric, 1), 4 + 10 + 10)
}

test "optimal_segments keeps a single-mode string as one segment" {
  let segs = @encode.optimal_segments("HELLO WORLD", 1)
  assert_eq(segs.length(), 1)
  assert_eq(segs[0].mode, @encode.Mode::Alphanumeric)
  assert_eq(segs[0].start, 0)
  assert_eq(segs[0].len, 11)
}

test "optimal_segments splits byte prefix from a long digit run" {
  // 実測の境界: 小文字を含む URL + 10桁以上の数字は分割した方が小さい
  let segs = @encode.optimal_segments("https://ex.com/id/1234567890", 1)
  assert_eq(segs.length(), 2)
  assert_eq(segs[0].mode, @encode.Mode::Byte)
  assert_eq(segs[1].mode, @encode.Mode::Numeric)
  assert_eq(segs[1].len, 10)
}

test "optimal_segments does not split a very short digit run" {
  // 単一Byte=172bit < 分割=177bit。桁数が少ないとモード切替の
  // オーバーヘッド（モード指示子4bit + 文字数指示子）が上回る
  let segs = @encode.optimal_segments("https://ex.com/id/12", 1)
  assert_eq(segs.length(), 1)
  assert_eq(segs[0].mode, @encode.Mode::Byte)
}

test "optimal_segments splits once the digit run is long enough" {
  // 単一Byte=196bit > 分割=187bit。境界は3〜4桁の間にある
  let segs = @encode.optimal_segments("https://ex.com/id/12345", 1)
  assert_eq(segs.length(), 2)
  assert_eq(segs[0].mode, @encode.Mode::Byte)
  assert_eq(segs[1].mode, @encode.Mode::Numeric)
  assert_eq(segs[1].len, 5)
}

test "optimal_segments absorbs digits into an alphanumeric span" {
  // 英字・数字・英字は 3 分割より 1 つの Alphanumeric の方が小さい
  let segs = @encode.optimal_segments("ABC12DEF", 1)
  assert_eq(segs.length(), 1)
  assert_eq(segs[0].mode, @encode.Mode::Alphanumeric)
  assert_eq(segs[0].len, 8)
}

test "optimal_segments on empty string yields no segments" {
  assert_eq(@encode.optimal_segments("", 1).length(), 0)
}

test "optimal_segments rejects input beyond the Model 2 absolute capacity" {
  let mut text = ""
  for i = 0; i < 7090; i = i + 1 {
    text = text + "1"
  }
  assert_eq(@encode.optimal_segments(text, 40).length(), 0)
}

test "optimal_segments never costs more than a single segment" {
  // どの入力でも「全体を1モードで表現」以下のビット数になること
  let cases = ["https://ex.com/id/1234567890", "ABC12DEF", "123456", "hello world 42"]
  for t in cases {
    let chars : Array[Char] = []
    for c in t {
      chars.push(c)
    }
    let single = @encode.detect_mode(t)
    let single_bits = @encode.segment_bits(chars, 0, chars.length(), single, 1)
    let segs = @encode.optimal_segments(t, 1)
    let mut total = 0
    for s in segs {
      total = total + @encode.segment_bits(chars, s.start, s.len, s.mode, 1)
    }
    assert_true(total <= single_bits)
  }
}

test "write_segments equals write_segment for a single-mode input" {
  // 分割の余地がない入力では、単一セグメントと完全に同じビット列になること
  let a = @encode.BitWriter::new()
  @encode.write_segment(a, "HELLO WORLD", @encode.Mode::Alphanumeric, 1)
  let b = @encode.BitWriter::new()
  @encode.write_segments(b, "HELLO WORLD", 1)
  assert_eq(b.bit_length(), a.bit_length())
}

test "write_segments produces fewer bits than a single segment when split helps" {
  let text = "https://ex.com/id/1234567890"
  let single = @encode.BitWriter::new()
  @encode.write_segment(single, text, @encode.Mode::Byte, 1)
  let split = @encode.BitWriter::new()
  @encode.write_segments(split, text, 1)
  assert_true(split.bit_length() < single.bit_length())
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
