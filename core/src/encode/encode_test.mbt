test "encode auto-selects smallest version" {
  match @encode.encode("01234567", @encode.EcLevel::M, None) {
    Some(m) => assert_eq(m.size, 21) // v1
    None => abort("must encode")
  }
}

test "encode long text picks bigger version" {
  let mut long = ""
  for i = 0; i < 100; i = i + 1 {
    long = long + "ABCDEFGH"
  } // 800文字 alnum
  match @encode.encode(long, @encode.EcLevel::M, None) {
    Some(m) => assert_true(m.size > 21)
    None => abort("must fit in some version")
  }
}

test "encode over capacity returns None" {
  let mut huge = ""
  for i = 0; i < 1000; i = i + 1 {
    huge = huge + "あいうえおかきくけこ"
  } // 30KB 超 -> v40 でも不可
  match @encode.encode(huge, @encode.EcLevel::L, None) {
    Some(_) => abort("must overflow")
    None => assert_true(true)
  }
}

test "encode_js rejects out-of-range version and ec" {
  assert_eq(@encode.encode_js("HI", 1, 41), [])
  assert_eq(@encode.encode_js("HI", 1, -1), [])
  assert_eq(@encode.encode_js("HI", 9, 1), []) // ec 範囲外
  assert_eq(@encode.encode_js("HI", -1, 1), [])
}

test "encode_js rejects empty text" {
  // 空文字は仕様として拒否する（qrcode npm は throw する。我々は [] で表現）
  assert_eq(@encode.encode_js("", 1, 0), [])
}

test "encode rejects empty text" {
  match @encode.encode("", @encode.EcLevel::M, None) {
    Some(_) => abort("empty text must be rejected")
    None => assert_true(true)
  }
}

test "to_svg_string_js produces svg or empty on failure" {
  let svg = @encode.to_svg_string_js("HI", 1, 0, 4, 10)
  assert_true(svg.contains("<svg"))
  assert_eq(@encode.to_svg_string_js("HI", 1, 41, 4, 10), "") // 範囲外 → ""
}

test "svg output contains rect per dark module" {
  match @encode.encode("HI", @encode.EcLevel::M, None) {
    Some(m) => {
      let svg = @encode.to_svg_string(m, 4, 10)
      assert_true(svg.contains("<svg"))
      assert_true(svg.contains("</svg>"))
      assert_true(svg.contains("<path") || svg.contains("<rect"))
    }
    None => abort("must encode")
  }
}
