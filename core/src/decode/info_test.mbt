///| フォーマット/バージョン情報復号の結合・単体テスト。
///| 真値表は encode パッケージの `format_bits`/`version_bits`（qrcode npm と
///| 一致実証済み）をそのまま使う。jsQR の有効コード表は移植しない。

///| bit `i` を反転する。
fn flip_bit(bits : Int, i : Int) -> Int {
  bits ^ (1 << i)
}

// ---- ① 全32組 (ec 4 x mask 8) ラウンドトリップ ----

test "decode_format recovers all 32 (ec, mask) combos" {
  let ecs = [
    @encode.EcLevel::L,
    @encode.EcLevel::M,
    @encode.EcLevel::Q,
    @encode.EcLevel::H,
  ]
  for ei = 0; ei < ecs.length(); ei = ei + 1 {
    for mask = 0; mask < 8; mask = mask + 1 {
      let ec = ecs[ei]
      let bits = @encode.format_bits(ec, mask)
      let info = @decode.decode_format(bits, bits)
      match info {
        Some(fi) => {
          assert_eq(fi.ec, ec)
          assert_eq(fi.mask, mask)
        }
        None => abort("expected Some for ec=\{ec} mask=\{mask}")
      }
    }
  }
}

// ---- ② ビット破壊 ----

test "decode_format survives 1..3 bit corruption" {
  let combos : Array[(@encode.EcLevel, Int)] = [
    (@encode.EcLevel::L, 0),
    (@encode.EcLevel::M, 5),
    (@encode.EcLevel::Q, 3),
    (@encode.EcLevel::H, 7),
  ]
  for ci = 0; ci < combos.length(); ci = ci + 1 {
    let (ec, mask) = combos[ci]
    let original = @encode.format_bits(ec, mask)
    // 1bit
    let c1 = flip_bit(original, 0)
    match @decode.decode_format(c1, c1) {
      Some(fi) => {
        assert_eq(fi.ec, ec)
        assert_eq(fi.mask, mask)
      }
      None => abort("expected recovery at 1bit corruption")
    }
    // 2bit
    let c2 = flip_bit(flip_bit(original, 0), 4)
    match @decode.decode_format(c2, c2) {
      Some(fi) => {
        assert_eq(fi.ec, ec)
        assert_eq(fi.mask, mask)
      }
      None => abort("expected recovery at 2bit corruption")
    }
    // 3bit
    let c3 = flip_bit(flip_bit(flip_bit(original, 0), 4), 9)
    match @decode.decode_format(c3, c3) {
      Some(fi) => {
        assert_eq(fi.ec, ec)
        assert_eq(fi.mask, mask)
      }
      None => abort("expected recovery at 3bit corruption")
    }
  }
}

///| BCH(15,5) の最小距離は7なので、3bit以下の誤りは常に一意訂正可能
///| （最近傍の正しい符号語との距離 <= 3 は、他のどの符号語との距離よりも
///| 必ず小さい: 三角不等式より、別の符号語との距離は >= 7 - 3 = 4 > 3）。
///| 4bit破壊はこの保証の外なので、結果は「None（距離>3で棄却）」または
///| 「別の妥当な符号語」のいずれかであり得るが、破壊されたビット列は
///| 元の符号語からハミング距離4の点にあるため、元の符号語自身に一致する
///| ことは絶対にない（距離0はあり得ない）。この「exact-original には
///| 一致しない」という一点だけを健全な不変条件として検証する。
test "decode_format with 4bit corruption never silently returns original" {
  let ec = @encode.EcLevel::M
  let mask = 5
  let original = @encode.format_bits(ec, mask)
  let corrupted = flip_bit(
    flip_bit(flip_bit(flip_bit(original, 0), 4), 9, ), 14,
  )
  match @decode.decode_format(corrupted, corrupted) {
    None => () // 距離>3で棄却: OK
    Some(fi) =>
      // 妥当な別符号語に着地した場合、少なくとも元の (ec, mask) とは
      // 異なっていなければならない（距離0はあり得ないため）
      assert_false(fi.ec == ec && fi.mask == mask)
  }
}

test "decode_format rejects when both copies are far from every codeword" {
  // 全32符号語から意図的に離れた値（15bit中 8bit 反転）を用意し、
  // 少なくとも1つの符号語との距離が3以下にならないことを事前確認した
  // 固定値で「両系統とも遠い→None」を確認する。
  let ec = @encode.EcLevel::L
  let mask = 0
  let original = @encode.format_bits(ec, mask)
  // 8bit 反転（0..7）: 最小距離7の符号に対し、最近傍との距離が3を
  // 超えることを想定した破壊。
  let mut corrupted = original
  for i = 0; i < 8; i = i + 1 {
    corrupted = flip_bit(corrupted, i)
  }
  // 事前検証: corrupted の全32符号語への最小距離が3を超えることを
  // このテスト自身で確認してから None を要求する（テーブル非依存）。
  let ecs = [
    @encode.EcLevel::L,
    @encode.EcLevel::M,
    @encode.EcLevel::Q,
    @encode.EcLevel::H,
  ]
  let mut min_dist = 15
  for ei = 0; ei < ecs.length(); ei = ei + 1 {
    for m = 0; m < 8; m = m + 1 {
      let cw = @encode.format_bits(ecs[ei], m)
      let mut d = 0
      let mut x = cw ^ corrupted
      while x != 0 {
        d = d + (x & 1)
        x = x >> 1
      }
      if d < min_dist {
        min_dist = d
      }
    }
  }
  if min_dist > 3 {
    match @decode.decode_format(corrupted, corrupted) {
      None => ()
      Some(_) => abort("expected None when min distance to every codeword > 3")
    }
  } else {
    // 8bit破壊がたまたま別の符号語の近傍に落ちた場合はこのケースの
    // 前提が崩れるため、テストとしては何もしない（矛盾した主張をしない）
    ()
  }
}

// ---- ③ decode_version ----

test "decode_version roundtrips for all v in 7..40" {
  for v = 7; v <= 40; v = v + 1 {
    let bits = @encode.version_bits(v)
    match @decode.decode_version(bits, bits) {
      Some(dv) => assert_eq(dv, v)
      None => abort("expected Some for v=\{v}")
    }
  }
}

test "decode_version survives 1..3 bit corruption" {
  let versions = [7, 15, 22, 30, 40]
  for vi = 0; vi < versions.length(); vi = vi + 1 {
    let v = versions[vi]
    let original = @encode.version_bits(v)
    let c3 = flip_bit(flip_bit(flip_bit(original, 0), 6), 13)
    match @decode.decode_version(c3, c3) {
      Some(dv) => assert_eq(dv, v)
      None => abort("expected recovery at 3bit corruption for v=\{v}")
    }
  }
}

test "decode_version rejects far corruption" {
  // BCH(18,6) 最小距離は7。全34符号語(v7..40)から意図的に離れた値
  // （18bit中 9bit 反転）を用意し、事前に全符号語への最小距離が3超
  // であることを確認してから None を要求する。
  let v = 7
  let original = @encode.version_bits(v)
  let mut corrupted = original
  for i = 0; i < 9; i = i + 1 {
    corrupted = flip_bit(corrupted, i)
  }
  let mut min_dist = 18
  for cand = 7; cand <= 40; cand = cand + 1 {
    let cw = @encode.version_bits(cand)
    let mut d = 0
    let mut x = cw ^ corrupted
    while x != 0 {
      d = d + (x & 1)
      x = x >> 1
    }
    if d < min_dist {
      min_dist = d
    }
  }
  if min_dist > 3 {
    match @decode.decode_version(corrupted, corrupted) {
      None => ()
      Some(_) => abort("expected None when min distance to every codeword > 3")
    }
  } else {
    ()
  }
}

// ---- ④ 結合: encode -> BitMatrix -> read_*_bits -> decode ----

///| @encode.Matrix（モジュール単位、true=黒）をそのまま同座標系で
///| BitMatrix へコピーする（extract 等のスケーリングを経由しない）。
fn matrix_to_bitmatrix(m : @encode.Matrix) -> @decode.BitMatrix {
  let bm = @decode.BitMatrix::make(m.size, m.size)
  for y = 0; y < m.size; y = y + 1 {
    for x = 0; x < m.size; x = x + 1 {
      bm.set(x, y, m.get(x, y))
    }
  }
  bm
}

test "integration: encode INFO Q v7 -> read_*_bits -> decode matches" {
  let matrix = match @encode.encode("INFO", @encode.EcLevel::Q, Some(7)) {
    Some(m) => m
    None => abort("encode should succeed for v7/Q/INFO")
  }
  let bm = matrix_to_bitmatrix(matrix)
  let (f1, f2) = @decode.read_format_bits(bm)
  let fi = match @decode.decode_format(f1, f2) {
    Some(fi) => fi
    None => abort("expected format info to decode")
  }
  assert_eq(fi.ec, @encode.EcLevel::Q)
  assert_true(fi.mask >= 0 && fi.mask < 8)
  let (v1, v2) = @decode.read_version_bits(bm)
  let version = match @decode.decode_version(v1, v2) {
    Some(v) => v
    None => abort("expected version info to decode")
  }
  assert_eq(version, 7)
}
