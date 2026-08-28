///| O(n) 実装の差分テストに使う、変更前の全分割点探索。
fn optimal_segments_reference(text : String, version : Int) -> Array[Segment] {
  if !input_within_model2_capacity(text) {
    return []
  }
  let runs = runs_of(text)
  let n = runs.length()
  if n == 0 {
    return []
  }
  let byte_prefix : Array[Int] = [0]
  for c in text {
    let cp = c.to_int()
    let byte_len = if cp < 0x80 {
      1
    } else if cp < 0x800 {
      2
    } else if cp < 0x10000 {
      3
    } else {
      4
    }
    byte_prefix.push(byte_prefix[byte_prefix.length() - 1] + byte_len)
  }
  let non_numeric_prefix : Array[Int] = [0]
  let byte_run_prefix : Array[Int] = [0]
  for r in runs {
    non_numeric_prefix.push(
      non_numeric_prefix[non_numeric_prefix.length() - 1] +
      (if r.mode == Mode::Numeric { 0 } else { 1 }),
    )
    byte_run_prefix.push(
      byte_run_prefix[byte_run_prefix.length() - 1] +
      (if r.mode == Mode::Byte { 1 } else { 0 }),
    )
  }
  let modes = [Mode::Numeric, Mode::Alphanumeric, Mode::Byte]
  let inf = 0x7FFFFFFF
  let dp = Array::make(n + 1, inf)
  dp[0] = 0
  let from_run = Array::make(n + 1, 0)
  let from_mode = Array::make(n + 1, Mode::Byte)
  for j = 1; j <= n; j = j + 1 {
    for i = 0; i < j; i = i + 1 {
      if dp[i] == inf {
        continue
      }
      let start = runs[i].start
      let end = runs[j - 1].start + runs[j - 1].len
      let len = end - start
      let byte_len = byte_prefix[end] - byte_prefix[start]
      let required_mode = if byte_run_prefix[j] - byte_run_prefix[i] > 0 {
        Mode::Byte
      } else if non_numeric_prefix[j] - non_numeric_prefix[i] > 0 {
        Mode::Alphanumeric
      } else {
        Mode::Numeric
      }
      for m in modes {
        if !mode_can_encode(m, required_mode) {
          continue
        }
        let cost = dp[i] + segment_bits_for_lengths(len, byte_len, m, version)
        if cost < dp[j] {
          dp[j] = cost
          from_run[j] = i
          from_mode[j] = m
        }
      }
    }
  }
  let rev : Array[Segment] = []
  let mut j = n
  while j > 0 {
    let i = from_run[j]
    let start = runs[i].start
    let mut len = 0
    for k = i; k < j; k = k + 1 {
      len = len + runs[k].len
    }
    rev.push(Segment::{ mode: from_mode[j], start, len })
    j = i
  }
  let out : Array[Segment] = []
  for idx = rev.length() - 1; idx >= 0; idx = idx - 1 {
    out.push(rev[idx])
  }
  out
}

test "reference segment DP retains the pre-optimization behavior" {
  let segments = optimal_segments_reference("https://ex.com/id/1234567890", 1)
  assert_eq(segments.length(), 2)
  assert_eq(segments[0].mode, Mode::Byte)
  assert_eq(segments[1].mode, Mode::Numeric)
}

fn repeat_for_segment_test(part : String, count : Int) -> String {
  let mut out = ""
  for i = 0; i < count; i = i + 1 {
    out = out + part
  }
  out
}

fn patterned_digits_for_segment_test(count : Int) -> String {
  let mut out = ""
  let digits = ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9']
  for i = 0; i < count; i = i + 1 {
    out = out + digits[(i * 7) % 10].to_string()
  }
  out
}

test "linear segment DP exactly matches the reference corpus in every CCI band" {
  let corpus : Array[String] = [
    // packages/moonqr/test/segment-optimization.test.mjs の CASES 全件
    "https://ex.com/id/12345",
    "https://ex.com/id/1234567890",
    "https://ex.com/id/" + patterned_digits_for_segment_test(30),
    "https://ex.com/id/" + patterned_digits_for_segment_test(100),
    "注文番号は" + patterned_digits_for_segment_test(30) + "です",
    "HTTPS://EX.COM/ID/" + patterned_digits_for_segment_test(60),
    "HELLO WORLD",
    "1234567890",
    "hello",
    "ABC12DEF",
    "SKU-1234567890-ABCDEFGHIJ-9876543210",
  ]
  for count in [1, 2, 3, 5, 100, 1000] {
    corpus.push(repeat_for_segment_test("1", count))
    corpus.push(repeat_for_segment_test("A", count))
    corpus.push(repeat_for_segment_test("a", count))
  }
  for count in [1, 2, 3, 10, 100] {
    corpus.push(repeat_for_segment_test("a1", count))
    corpus.push(repeat_for_segment_test("1A", count))
    corpus.push(repeat_for_segment_test("aA1", count))
  }
  for text in [
    "🦑",
    "🦑A1",
    "a🦑漢1Z",
    "漢字123ABC🌕xyz",
    "QRコード🚀-2026",
    "😀😃😄😁",
    "Aあ1🧚B2漢c3",
    "􏿿",
    "éΩ漢😀",
    "byte😀ALNUM123漢字",
  ] {
    corpus.push(text)
  }
  let alphabet = ['0', '7', 'A', 'Z', '-', ':', 'a', 'z', '漢', '😀']
  let mut seed = 0x4D2B
  for case_index = 0; case_index < 256; case_index = case_index + 1 {
    seed = (seed * 25173 + 13849) % 65536
    let length = seed % 40 + 1
    let mut text = ""
    for char_index = 0; char_index < length; char_index = char_index + 1 {
      seed = (seed * 25173 + 13849) % 65536
      text = text + alphabet[seed % alphabet.length()].to_string()
    }
    corpus.push(text)
  }
  assert_true(corpus.length() >= 300)
  for version in [1, 10, 27] {
    for text in corpus {
      assert_eq(
        optimal_segments(text, version),
        optimal_segments_reference(text, version),
      )
    }
  }
}

test "char_mode classifies by the most restrictive mode" {
  assert_eq(char_mode('5'), Mode::Numeric)
  assert_eq(char_mode('A'), Mode::Alphanumeric)
  assert_eq(char_mode(' '), Mode::Alphanumeric)
  assert_eq(char_mode(':'), Mode::Alphanumeric)
  assert_eq(char_mode('a'), Mode::Byte)
  assert_eq(char_mode('あ'), Mode::Byte)
}

test "runs_of groups consecutive chars of the same mode" {
  let rs = runs_of("ab123XY")
  assert_eq(rs.length(), 3)
  assert_eq(rs[0].mode, Mode::Byte)
  assert_eq(rs[0].start, 0)
  assert_eq(rs[0].len, 2)
  assert_eq(rs[1].mode, Mode::Numeric)
  assert_eq(rs[1].start, 2)
  assert_eq(rs[1].len, 3)
  assert_eq(rs[2].mode, Mode::Alphanumeric)
  assert_eq(rs[2].start, 5)
  assert_eq(rs[2].len, 2)
}

test "runs_of on a single-mode string yields one run" {
  let rs = runs_of("123456")
  assert_eq(rs.length(), 1)
  assert_eq(rs[0].mode, Mode::Numeric)
  assert_eq(rs[0].len, 6)
}

test "runs_of on empty string yields no runs" {
  assert_eq(runs_of("").length(), 0)
}

test "mode_can_encode follows Numeric ⊂ Alphanumeric ⊂ Byte" {
  assert_eq(mode_can_encode(Mode::Numeric, Mode::Numeric), true)
  assert_eq(mode_can_encode(Mode::Alphanumeric, Mode::Numeric), true)
  assert_eq(mode_can_encode(Mode::Byte, Mode::Numeric), true)
  assert_eq(mode_can_encode(Mode::Numeric, Mode::Alphanumeric), false)
  assert_eq(mode_can_encode(Mode::Alphanumeric, Mode::Byte), false)
  assert_eq(mode_can_encode(Mode::Byte, Mode::Byte), true)
}

test "segment candidate tie-break matches the reference DP traversal order" {
  assert_true(
    segment_candidate_is_better(99, 9, Mode::Byte, 100, 0, Mode::Numeric),
  )
  assert_true(
    segment_candidate_is_better(100, 2, Mode::Byte, 100, 3, Mode::Numeric),
  )
  assert_true(
    segment_candidate_is_better(100, 2, Mode::Numeric, 100, 2, Mode::Alphanumeric),
  )
  assert_true(
    segment_candidate_is_better(100, 2, Mode::Alphanumeric, 100, 2, Mode::Byte),
  )
  assert_false(
    segment_candidate_is_better(100, 2, Mode::Byte, 100, 2, Mode::Byte),
  )
  assert_false(
    segment_candidate_is_better(100, 3, Mode::Numeric, 100, 2, Mode::Byte),
  )
}

test "segment_bits matches write_segment for numeric" {
  // "01234567" v1 numeric: 4 + 10 + (10+10+7) = 41
  let chars : Array[Char] = []
  for c in "01234567" {
    chars.push(c)
  }
  assert_eq(segment_bits(chars, 0, 8, Mode::Numeric, 1), 4 + 10 + 10 + 10 + 7)
}

test "segment_bits matches write_segment for alphanumeric" {
  // "AC-42" v1 alnum: 4 + 9 + (11+11+6) = 41
  let chars : Array[Char] = []
  for c in "AC-42" {
    chars.push(c)
  }
  assert_eq(segment_bits(chars, 0, 5, Mode::Alphanumeric, 1), 4 + 9 + 11 + 11 + 6)
}

test "segment_bits counts UTF-8 bytes for byte mode" {
  // "あ" は UTF-8 で 3 バイト: 4 + 8 + 24 = 36 (v1)
  let chars : Array[Char] = []
  for c in "あ" {
    chars.push(c)
  }
  assert_eq(segment_bits(chars, 0, 1, Mode::Byte, 1), 4 + 8 + 24)
}

test "segment_bits handles a sub-range" {
  // "XX123" の後半 3 文字を numeric として測る: 4 + 10 + 10 = 24 (v1)
  let chars : Array[Char] = []
  for c in "XX123" {
    chars.push(c)
  }
  assert_eq(segment_bits(chars, 2, 3, Mode::Numeric, 1), 4 + 10 + 10)
}

test "optimal_segments keeps a single-mode string as one segment" {
  let segs = optimal_segments("HELLO WORLD", 1)
  assert_eq(segs.length(), 1)
  assert_eq(segs[0].mode, Mode::Alphanumeric)
  assert_eq(segs[0].start, 0)
  assert_eq(segs[0].len, 11)
}

test "optimal_segments splits byte prefix from a long digit run" {
  // 実測の境界: 小文字を含む URL + 10桁以上の数字は分割した方が小さい
  let segs = optimal_segments("https://ex.com/id/1234567890", 1)
  assert_eq(segs.length(), 2)
  assert_eq(segs[0].mode, Mode::Byte)
  assert_eq(segs[1].mode, Mode::Numeric)
  assert_eq(segs[1].len, 10)
}

test "optimal_segments does not split a very short digit run" {
  // 単一Byte=172bit < 分割=177bit。桁数が少ないとモード切替の
  // オーバーヘッド（モード指示子4bit + 文字数指示子）が上回る
  let segs = optimal_segments("https://ex.com/id/12", 1)
  assert_eq(segs.length(), 1)
  assert_eq(segs[0].mode, Mode::Byte)
}

test "optimal_segments splits once the digit run is long enough" {
  // 単一Byte=196bit > 分割=187bit。境界は3〜4桁の間にある
  let segs = optimal_segments("https://ex.com/id/12345", 1)
  assert_eq(segs.length(), 2)
  assert_eq(segs[0].mode, Mode::Byte)
  assert_eq(segs[1].mode, Mode::Numeric)
  assert_eq(segs[1].len, 5)
}

test "optimal_segments absorbs digits into an alphanumeric span" {
  // 英字・数字・英字は 3 分割より 1 つの Alphanumeric の方が小さい
  let segs = optimal_segments("ABC12DEF", 1)
  assert_eq(segs.length(), 1)
  assert_eq(segs[0].mode, Mode::Alphanumeric)
  assert_eq(segs[0].len, 8)
}

test "optimal_segments on empty string yields no segments" {
  assert_eq(optimal_segments("", 1).length(), 0)
}

test "optimal_segments accepts the Model 2 limit and rejects one beyond it" {
  let mut text = ""
  for i = 0; i < 7089; i = i + 1 {
    text = text + "1"
  }
  assert_eq(optimal_segments(text, 40).length(), 1)
  text = text + "1"
  assert_eq(optimal_segments(text, 40).length(), 0)
}

test "optimal_segments never costs more than a single segment" {
  // どの入力でも「全体を1モードで表現」以下のビット数になること
  let cases = ["https://ex.com/id/1234567890", "ABC12DEF", "123456", "hello world 42"]
  for t in cases {
    let chars : Array[Char] = []
    for c in t {
      chars.push(c)
    }
    let single = detect_mode(t)
    let single_bits = segment_bits(chars, 0, chars.length(), single, 1)
    let segs = optimal_segments(t, 1)
    let mut total = 0
    for s in segs {
      total = total + segment_bits(chars, s.start, s.len, s.mode, 1)
    }
    assert_true(total <= single_bits)
  }
}

test "write_segments equals write_segment for a single-mode input" {
  // 分割の余地がない入力では、単一セグメントと完全に同じビット列になること
  let a = BitWriter::new()
  write_segment(a, "HELLO WORLD", Mode::Alphanumeric, 1)
  let b = BitWriter::new()
  write_segments(b, "HELLO WORLD", 1)
  assert_eq(b.bit_length(), a.bit_length())
}

test "write_segments produces fewer bits than a single segment when split helps" {
  let text = "https://ex.com/id/1234567890"
  let single = BitWriter::new()
  write_segment(single, text, Mode::Byte, 1)
  let split = BitWriter::new()
  write_segments(split, text, 1)
  assert_true(split.bit_length() < single.bit_length())
}
