///| 決定的擬似乱数（テスト再現性のため seed 固定）
fn next_rand(state : Int) -> Int {
  (state * 1103515245 + 12345) & 0x7FFFFFFF
}

test "decode clean codeword unchanged" {
  let data = [10, 20, 30, 40, 50, 60, 70, 80]
  let ec = @gf256.rs_encode(data, 8)
  let msg = data.copy()
  for i = 0; i < ec.length(); i = i + 1 {
    msg.push(ec[i])
  }
  match @gf256.rs_decode(msg, 8) {
    Some(fixed) => assert_eq(fixed, msg)
    None => abort("clean codeword must decode")
  }
}

test "property: encode -> corrupt t bytes -> decode recovers (t <= n_ec/2)" {
  let mut seed = 12345
  for round = 0; round < 50; round = round + 1 {
    let n_data = 16
    let n_ec = 10 // 訂正能力 5
    let data : Array[Int] = []
    for i = 0; i < n_data; i = i + 1 {
      seed = next_rand(seed)
      data.push(seed % 256)
    }
    let ec = @gf256.rs_encode(data, n_ec)
    let original = data.copy()
    for i = 0; i < ec.length(); i = i + 1 {
      original.push(ec[i])
    }
    let corrupted = original.copy()
    seed = next_rand(seed)
    let n_errors = 1 + seed % 5 // 1..5 個
    // 相異なる位置を n_errors 個選んで値を必ず変える
    let used : Array[Int] = []
    let mut placed = 0
    while placed < n_errors {
      seed = next_rand(seed)
      let pos = seed % corrupted.length()
      if used.contains(pos) {
        continue
      }
      used.push(pos)
      seed = next_rand(seed)
      corrupted[pos] = corrupted[pos] ^ (1 + seed % 255)
      placed = placed + 1
    }
    match @gf256.rs_decode(corrupted, n_ec) {
      Some(fixed) => assert_eq(fixed, original)
      None => abort("must correct \{n_errors} errors")
    }
  }
}

test "too many errors returns None or wrong-detect" {
  // 訂正能力超過（6個 > 5）: None を返すか、少なくとも成功と偽らない実装で
  // あることを確認する（RSは超過時に誤訂正しうるが、シンドローム再検査で弾く）
  let data = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16]
  let ec = @gf256.rs_encode(data, 10)
  let msg = data.copy()
  for i = 0; i < ec.length(); i = i + 1 {
    msg.push(ec[i])
  }
  let corrupted = msg.copy()
  for i = 0; i < 6; i = i + 1 {
    corrupted[i * 2] = corrupted[i * 2] ^ 0xA5
  }
  match @gf256.rs_decode(corrupted, 10) {
    Some(fixed) => {
      // 誤訂正が返るならシンドロームは0のはず＝有効な符号語。
      // ただし元データと一致しないことは許容（RS理論上の限界）。
      // ここでは「クラッシュせず Option が返る」ことだけを確認。
      assert_true(fixed.length() == msg.length())
    }
    None => assert_true(true)
  }
}

fn make_codeword(data : Array[Int], n_ec : Int) -> Array[Int] {
  let msg = data.copy()
  let ec = @gf256.rs_encode(data, n_ec)
  for i = 0; i < ec.length(); i = i + 1 {
    msg.push(ec[i])
  }
  msg
}

test "誤りが1個 → 元の符号語に訂正できる" {
  let original = make_codeword([10, 20, 30, 40, 50, 60, 70, 80], 10)
  let corrupted = original.copy()
  corrupted[3] = corrupted[3] ^ 0x55
  match @gf256.rs_decode(corrupted, 10) {
    Some(fixed) => assert_eq(fixed, original)
    None => abort("誤り1個は訂正できる")
  }
}

test "誤りが訂正能力ちょうどの5個 → 元の符号語に訂正できる" {
  let original = make_codeword([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16], 10)
  let corrupted = original.copy()
  // データ部とEC部、先頭と末尾を含む相異なる5位置。
  corrupted[0] = corrupted[0] ^ 0x01
  corrupted[5] = corrupted[5] ^ 0x23
  corrupted[15] = corrupted[15] ^ 0x45
  corrupted[16] = corrupted[16] ^ 0x67
  corrupted[25] = corrupted[25] ^ 0x89
  match @gf256.rs_decode(corrupted, 10) {
    Some(fixed) => assert_eq(fixed, original)
    None => abort("誤り5個は訂正できる")
  }
}

test "誤りが0個 → 入力と同じ配列を返す" {
  let msg = make_codeword([10, 20, 30, 40, 50, 60, 70, 80], 10)
  match @gf256.rs_decode(msg, 10) {
    Some(fixed) => assert_true(physical_equal(fixed, msg))
    None => abort("誤りがない符号語は復号できる")
  }
}

test "誤りを訂正した場合 → 入力と別の配列を返す" {
  let corrupted = make_codeword([10, 20, 30, 40, 50, 60, 70, 80], 10)
  corrupted[3] = corrupted[3] ^ 0x55
  match @gf256.rs_decode(corrupted, 10) {
    Some(fixed) => assert_false(physical_equal(fixed, corrupted))
    None => abort("誤り1個は訂正できる")
  }
}

test "誤りを訂正した場合 → 入力配列の中身を変えない" {
  let corrupted = make_codeword([10, 20, 30, 40, 50, 60, 70, 80], 10)
  corrupted[3] = corrupted[3] ^ 0x55
  let before = corrupted.copy()
  match @gf256.rs_decode(corrupted, 10) {
    Some(_) => assert_eq(corrupted, before)
    None => abort("誤り1個は訂正できる")
  }
}

test "誤りが訂正能力を1個超えロケータを求められない → Noneを返す" {
  let corrupted = make_codeword([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16], 10)
  for i = 0; i < 6; i = i + 1 {
    corrupted[i * 2] = corrupted[i * 2] ^ 0xA5
  }
  // 経路(a): find_error_locatorがNone。6誤りの境界超過もこの入力で固定する。
  assert_true(@gf256.rs_decode(corrupted, 10) is None)
}

test "ロケータに対応する誤り位置を求められない → Noneを返す" {
  // 経路(b): find_error_positionsがNone。16データ+10ECの符号語に9誤り。
  let corrupted = [216, 22, 60, 197, 26, 75, 228, 128, 198, 155, 212, 125, 114, 195, 140, 121, 54, 184, 99, 179, 208, 22, 171, 177, 147, 37]
  assert_true(@gf256.rs_decode(corrupted, 10) is None)
}
