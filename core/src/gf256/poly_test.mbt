test "rs generator degree and leading coeff" {
  // 生成多項式 g(x) = Π_{i=0}^{n-1} (x - α^i)。次数 n、モニック。
  let g = @gf256.rs_generator(10)
  assert_eq(g.length(), 11)
  assert_eq(g[0], 1)
}

test "rs_encode length and determinism" {
  let data = [32, 91, 11, 120, 209, 114, 220, 77, 67, 64, 236, 17, 236, 17, 236, 17]
  let ec = @gf256.rs_encode(data, 10)
  assert_eq(ec.length(), 10)
  assert_eq(ec, @gf256.rs_encode(data, 10))
}

test "rs_encode makes codeword divisible by generator" {
  // 符号語 = data || ec は g(x) で割り切れる（RS符号の定義）
  let data = [64, 86, 22, 198, 87, 38, 23, 50, 6, 54, 246, 118, 66]
  let n_ec = 13
  let ec = @gf256.rs_encode(data, n_ec)
  let codeword = data.copy()
  for i = 0; i < n_ec; i = i + 1 {
    codeword.push(ec[i])
  }
  // g(α^i) = 0 (i=0..n_ec-1) なので符号語も α^i で評価して 0 になる
  for i = 0; i < n_ec; i = i + 1 {
    let x = @gf256.exp(i)
    let mut acc = 0
    for j = 0; j < codeword.length(); j = j + 1 {
      acc = @gf256.add(@gf256.mul(acc, x), codeword[j])
    }
    assert_eq(acc, 0)
  }
}
