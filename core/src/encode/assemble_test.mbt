test "assemble pads with ec11 pattern and interleaves" {
  // v1-M: data 16 codewords, ec 10 codewords, 1ブロック → 26個
  let w = @encode.BitWriter::new()
  @encode.write_segment(w, "01234567", @encode.Mode::Numeric, 1)
  match @encode.assemble(w, 1, @encode.EcLevel::M) {
    Some(cw) => {
      assert_eq(cw.length(), 26)
      // 先頭: 0001 0000001000 ... の詰め結果（ISO 18004 の古典例）
      assert_eq(cw[0], 0b00010000)
      assert_eq(cw[1], 0b00100000)
      // パディングは 0xEC, 0x11 交互
      assert_eq(cw[14], 0xEC)
      assert_eq(cw[15], 0x11)
    }
    None => abort("must fit in v1-M")
  }
}

test "assemble returns None when over capacity" {
  let w = @encode.BitWriter::new()
  let long = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA" // 40文字 > v1-H
  @encode.write_segment(w, long, @encode.Mode::Alphanumeric, 1)
  match @encode.assemble(w, 1, @encode.EcLevel::H) {
    Some(_) => abort("must overflow")
    None => assert_true(true)
  }
}
