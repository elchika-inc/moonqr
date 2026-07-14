///| read_data の結合テスト。
///| `matrix_to_bitmatrix` は info_test.mbt で定義済み（同一テストパッケージ内で共有）。
///|
///| ①②③ ラウンドトリップ: @encode.encode の行列 -> BitMatrix -> read_format_bits/
///| decode_format(/decode_version) -> read_data が、
///| 「BitWriter+write_segment+assemble」で独立に得たデータコードワード（パディング込み・
///| マスク非依存）の先頭 data_capacity 個と一致することを確認する。
///| 注意: assemble() の出力はワイヤ形式（ブロック横断インターリーブ済み）だが、
///| read_data の契約は「デインターリーブ済み」（ブロック順に連結、Task 7 のセグメント復号が
///| 連続バイト列として消費できる形）を返すことなので、比較は got を `interleave_data` で
///| 再インターリーブしてから assemble() の生出力と突き合わせる（単一ブロックの v1-M では
///| インターリーブが恒等写像になるため元々一致するが、v5-H/v7-L の複数ブロックでは
///| インターリーブを経由しないと一致しない）。
///| ④ 誤り訂正: データ領域モジュールを4箇所（≤4バイト相当、EC容量5バイト以内）反転しても
///| 元のデータコードワードに一致する。
///| ⑤ 訂正能力超過: 半数のモジュールを反転（26バイト中ほぼ全バイト破壊）すると None になる。

///| 指定バージョン/文字列/ECで「期待データコードワード（ワイヤ形式・インターリーブ済み）」を
///| 独立算出する（write_segment+assemble経路。マスクを経由しないため decode 側の
///| mask 選択と独立）。
fn expected_data_codewords(
  text : String,
  version : Int,
  ec : @encode.EcLevel,
) -> Array[Int] {
  let mode = @encode.detect_mode(text)
  let w = @encode.BitWriter::new()
  @encode.write_segment(w, text, mode, version)
  let all = match @encode.assemble(w, version, ec) {
    Some(cw) => cw
    None => abort("assemble should succeed (capacity/version mismatch?)")
  }
  let cap = @encode.data_capacity(version, ec)
  let out : Array[Int] = []
  for i = 0; i < cap; i = i + 1 {
    out.push(all[i])
  }
  out
}

///| read_data の「デインターリーブ済み（ブロック順連結）」出力を、assemble() と同じ
///| ワイヤ形式（各ブロックのi番目を順に）へ再インターリーブする。read_data 自身の
///| 実装とは独立に（rs_blocks のみを使い）ここで再実装しており、read_data の
///| デインターリーブにバグがあれば往復不一致として検出できる。
fn interleave_data(
  flat : Array[Int],
  version : Int,
  ec : @encode.EcLevel,
) -> Array[Int] {
  let blocks = @encode.rs_blocks(version, ec)
  let per_block : Array[Array[Int]] = []
  let mut offset = 0
  let mut max_d = 0
  for i = 0; i < blocks.length(); i = i + 1 {
    let (_total, dcount) = blocks[i]
    let seg : Array[Int] = []
    for j = 0; j < dcount; j = j + 1 {
      seg.push(flat[offset + j])
    }
    offset = offset + dcount
    per_block.push(seg)
    if dcount > max_d {
      max_d = dcount
    }
  }
  let out : Array[Int] = []
  for i = 0; i < max_d; i = i + 1 {
    for b = 0; b < per_block.length(); b = b + 1 {
      if i < per_block[b].length() {
        out.push(per_block[b][i])
      }
    }
  }
  out
}

///| 機能領域マップ（brief指定どおり @encode.Matrix::new + place_function_patterns +
///| place_version で構築）を経由してデータ領域セル座標を列挙する。
fn data_area_coords(version : Int) -> Array[(Int, Int)] {
  let fm = @encode.Matrix::new(version)
  @encode.place_function_patterns(fm, version)
  @encode.place_version(fm, version)
  let coords : Array[(Int, Int)] = []
  for y = 0; y < fm.size; y = y + 1 {
    for x = 0; x < fm.size; x = x + 1 {
      if !fm.is_function(x, y) {
        coords.push((x, y))
      }
    }
  }
  coords
}

test "read_data: roundtrip v1-M numeric" {
  let text = "01234567"
  let version = 1
  let ec = @encode.EcLevel::M
  let expected = expected_data_codewords(text, version, ec)
  let matrix = match @encode.encode(text, ec, Some(version)) {
    Some(m) => m
    None => abort("encode should succeed for v1-M numeric")
  }
  let bm = matrix_to_bitmatrix(matrix)
  let (f1, f2) = @decode.read_format_bits(bm)
  let fmt = match @decode.decode_format(f1, f2) {
    Some(fi) => fi
    None => abort("expected format info to decode")
  }
  assert_eq(fmt.ec, ec)
  let got = match @decode.read_data(bm, version, fmt) {
    Some(d) => d
    None => abort("expected read_data to succeed")
  }
  assert_eq(interleave_data(got, version, ec), expected)
}

test "read_data: roundtrip v5-H alphanumeric (multi-block interleave)" {
  let text = "MULTIBLOCK ROUNDTRIP TEST"
  let version = 5
  let ec = @encode.EcLevel::H
  let expected = expected_data_codewords(text, version, ec)
  let matrix = match @encode.encode(text, ec, Some(version)) {
    Some(m) => m
    None => abort("encode should succeed for v5-H")
  }
  let bm = matrix_to_bitmatrix(matrix)
  let (f1, f2) = @decode.read_format_bits(bm)
  let fmt = match @decode.decode_format(f1, f2) {
    Some(fi) => fi
    None => abort("expected format info to decode")
  }
  assert_eq(fmt.ec, ec)
  let got = match @decode.read_data(bm, version, fmt) {
    Some(d) => d
    None => abort("expected read_data to succeed")
  }
  assert_eq(interleave_data(got, version, ec), expected)
}

test "read_data: roundtrip v7-L (version info path)" {
  let text = "VERSION7"
  let version = 7
  let ec = @encode.EcLevel::L
  let expected = expected_data_codewords(text, version, ec)
  let matrix = match @encode.encode(text, ec, Some(version)) {
    Some(m) => m
    None => abort("encode should succeed for v7-L")
  }
  let bm = matrix_to_bitmatrix(matrix)
  let (f1, f2) = @decode.read_format_bits(bm)
  let fmt = match @decode.decode_format(f1, f2) {
    Some(fi) => fi
    None => abort("expected format info to decode")
  }
  let (v1, v2) = @decode.read_version_bits(bm)
  let decoded_version = match @decode.decode_version(v1, v2) {
    Some(v) => v
    None => abort("expected version info to decode")
  }
  assert_eq(decoded_version, version)
  let got = match @decode.read_data(bm, decoded_version, fmt) {
    Some(d) => d
    None => abort("expected read_data to succeed")
  }
  assert_eq(interleave_data(got, decoded_version, ec), expected)
}

test "read_data: corrects bit-level corruption within EC capacity" {
  let text = "01234567"
  let version = 1
  let ec = @encode.EcLevel::M
  let expected = expected_data_codewords(text, version, ec)
  let matrix = match @encode.encode(text, ec, Some(version)) {
    Some(m) => m
    None => abort("encode should succeed for v1-M numeric")
  }
  let bm = matrix_to_bitmatrix(matrix)
  let (f1, f2) = @decode.read_format_bits(bm)
  let fmt = match @decode.decode_format(f1, f2) {
    Some(fi) => fi
    None => abort("expected format info to decode")
  }
  // v1 はremainder bitsが0（26コードワード=208bit=全非機能セル数）なので、
  // どの非機能セルを反転しても必ずどれかのコードワードの実ビットが壊れる。
  // 4セルの反転は高々4バイトの破損であり、v1-MのEC容量(10 ⇒ 5バイト訂正可)以内。
  let coords = data_area_coords(version)
  let flip_idx = [3, 60, 130, 200]
  for i = 0; i < flip_idx.length(); i = i + 1 {
    let (x, y) = coords[flip_idx[i]]
    bm.set(x, y, !bm.get(x, y))
  }
  let got = match @decode.read_data(bm, version, fmt) {
    Some(d) => d
    None => abort("expected read_data to correct the corruption")
  }
  assert_eq(interleave_data(got, version, ec), expected)
}

test "read_data: returns None when corruption exceeds correction capacity" {
  let text = "01234567"
  let version = 1
  let ec = @encode.EcLevel::M
  let matrix = match @encode.encode(text, ec, Some(version)) {
    Some(m) => m
    None => abort("encode should succeed for v1-M numeric")
  }
  let bm = matrix_to_bitmatrix(matrix)
  let (f1, f2) = @decode.read_format_bits(bm)
  let fmt = match @decode.decode_format(f1, f2) {
    Some(fi) => fi
    None => abort("expected format info to decode")
  }
  // データ領域セル(208個)の半数を反転。26バイト中ほぼ全バイトが破壊され、
  // v1-MのEC訂正能力（5バイト）を大きく超えるため、決定論的にNoneとなる。
  let coords = data_area_coords(version)
  let mut i = 0
  while i < coords.length() {
    let (x, y) = coords[i]
    bm.set(x, y, !bm.get(x, y))
    i = i + 2
  }
  match @decode.read_data(bm, version, fmt) {
    None => ()
    Some(_) => abort("expected None when corruption exceeds RS correction capacity")
  }
}
