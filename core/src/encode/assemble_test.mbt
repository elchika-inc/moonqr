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

test "assemble interleaves multi-block versions correctly (v5-H)" {
  // 46 = data_capacity(5, H)。BitWriter に直接46バイト書き込み、
  // 終端子・パディングなしの既知データで多ブロックインターリーブを検証する。
  // ブロック構成 2x(33,11) + 2x(34,12)、データオフセット 0/11/22/34。
  let w = @encode.BitWriter::new()
  for i = 0; i < 46; i = i + 1 {
    w.write(i * 7 % 256, 8)
  }
  match @encode.assemble(w, 5, @encode.EcLevel::H) {
    None => abort("must fit exactly")
    Some(cw) => {
      // v5 総コードワード = 134 (46 data + 88 ec)
      assert_eq(cw.length(), 134)
      // データインターリーブ先頭: 各ブロックの0番目
      assert_eq(cw[0], 0) // block0 data[0]  = 0*7
      assert_eq(cw[1], 77) // block1 data[11] = 11*7
      assert_eq(cw[2], 154) // block2 data[22] = 22*7
      assert_eq(cw[3], 238) // block3 data[34] = 34*7
      // index 11 は長ブロック(2,3)のみ持つ: 4*11=44 から2要素
      assert_eq(cw[44], 231) // block2 data[33] = 33*7 % 256
      assert_eq(cw[45], 59) // block3 data[45] = 45*7 % 256
      // EC 先頭はブロック0の rs_encode(…, 22) の先頭と一致
      let block0 : Array[Int] = []
      for i = 0; i < 11; i = i + 1 {
        block0.push(i * 7 % 256)
      }
      let ec0 = @gf256.rs_encode(block0, 22)
      assert_eq(cw[46], ec0[0])
    }
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

test "assemble: 空の入力 → 引数に4bitの終端子だけを追記する" {
  let w = @encode.BitWriter::new()
  guard @encode.assemble(w, 1, @encode.EcLevel::M) is Some(_) else {
    fail("空の入力は容量内")
  }
  assert_eq(w.bit_length(), 4)
  assert_eq(w.to_codewords(), [0])
}

test "assemble: 5bitの入力 → 引数の元データを保って4bitのゼロを追記する" {
  let w = @encode.BitWriter::new()
  w.write(0b10101, 5)
  guard @encode.assemble(w, 1, @encode.EcLevel::M) is Some(_) else {
    fail("5bitの入力は容量内")
  }
  assert_eq(w.bit_length(), 9)
  assert_eq(w.to_codewords(), [0b10101000, 0])
}

test "assemble: 残容量1bit → 引数に1bitのゼロを追記する" {
  let w = @encode.BitWriter::new()
  for i = 0; i < 15; i = i + 1 {
    w.write(i, 8)
  }
  w.write(0b1111111, 7)
  guard @encode.assemble(w, 1, @encode.EcLevel::M) is Some(_) else {
    fail("127bitの入力は容量内")
  }
  assert_eq(w.bit_length(), 128)
  assert_eq(w.to_codewords()[15], 0b11111110)
}

test "assemble: 残容量2bit → 引数に2bitのゼロを追記する" {
  let w = @encode.BitWriter::new()
  for i = 0; i < 15; i = i + 1 {
    w.write(i, 8)
  }
  w.write(0b111111, 6)
  guard @encode.assemble(w, 1, @encode.EcLevel::M) is Some(_) else {
    fail("126bitの入力は容量内")
  }
  assert_eq(w.bit_length(), 128)
  assert_eq(w.to_codewords()[15], 0b11111100)
}

test "assemble: 残容量3bit → 引数に3bitのゼロを追記する" {
  let w = @encode.BitWriter::new()
  for i = 0; i < 15; i = i + 1 {
    w.write(i, 8)
  }
  w.write(0b11111, 5)
  guard @encode.assemble(w, 1, @encode.EcLevel::M) is Some(_) else {
    fail("125bitの入力は容量内")
  }
  assert_eq(w.bit_length(), 128)
  assert_eq(w.to_codewords()[15], 0b11111000)
}

test "assemble: 容量と一致する入力 → 組立てに成功し引数を変更しない" {
  let w = @encode.BitWriter::new()
  for i = 0; i < 16; i = i + 1 {
    w.write(i, 8)
  }
  let before = w.to_codewords()
  guard @encode.assemble(w, 1, @encode.EcLevel::M) is Some(_) else {
    fail("128bitの入力は容量と一致")
  }
  assert_eq(w.bit_length(), 128)
  assert_eq(w.to_codewords(), before)
}

test "assemble: 容量を1bit超える入力 → Noneを返し引数を変更しない" {
  let w = @encode.BitWriter::new()
  for i = 0; i < 16; i = i + 1 {
    w.write(i, 8)
  }
  w.write(1, 1)
  let before = w.to_codewords()
  assert_eq(@encode.assemble(w, 1, @encode.EcLevel::M), None)
  assert_eq(w.bit_length(), 129)
  assert_eq(w.to_codewords(), before)
}

test "assemble: 同じ5bitの入力に2回呼ぶ → 終端子を合計8bit追記する" {
  let w = @encode.BitWriter::new()
  w.write(0b10101, 5)
  guard @encode.assemble(w, 1, @encode.EcLevel::M) is Some(_) else {
    fail("初回は容量内")
  }
  guard @encode.assemble(w, 1, @encode.EcLevel::M) is Some(_) else {
    fail("2回目も容量内")
  }
  assert_eq(w.bit_length(), 13)
  assert_eq(w.to_codewords(), [0b10101000, 0])
}
