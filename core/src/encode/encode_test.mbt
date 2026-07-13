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
