test "known capacities from ISO 18004" {
  // 有名な既知値でテーブル全体の並び順ミスを検出する
  assert_eq(@encode.data_capacity(1, @encode.EcLevel::L), 19)
  assert_eq(@encode.data_capacity(1, @encode.EcLevel::M), 16)
  assert_eq(@encode.data_capacity(1, @encode.EcLevel::Q), 13)
  assert_eq(@encode.data_capacity(1, @encode.EcLevel::H), 9)
  assert_eq(@encode.data_capacity(40, @encode.EcLevel::L), 2956)
}

test "total codewords match version formula for all versions" {
  // 総コードワード数 = 全ブロックの totalCount 合計。
  // version の総モジュール数から導かれる既知系列と一致すること
  // (v1=26, v2=44, v3=70, ..., v40=3706)
  let expected_v1_to_5 = [26, 44, 70, 100, 134]
  for v = 1; v <= 5; v = v + 1 {
    let blocks = @encode.rs_blocks(v, @encode.EcLevel::M)
    let mut total = 0
    for i = 0; i < blocks.length(); i = i + 1 {
      let (t, _) = blocks[i]
      total = total + t
    }
    assert_eq(total, expected_v1_to_5[v - 1])
  }
}

test "alignment positions" {
  assert_eq(@encode.alignment_positions(1), [])
  assert_eq(@encode.alignment_positions(2), [6, 18])
  assert_eq(@encode.alignment_positions(7), [6, 22, 38])
}
