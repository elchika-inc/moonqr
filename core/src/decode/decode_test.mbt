///| decode()/decode_js() の結合テスト（Task 8）。
///|
///| `@encode.encode` で得た `Matrix` を実画像相当のRGBA `Bytes` に展開
///| （1module=4px、余白16px、黒=30/白=220のグレースケール値をR=G=Bへ複製、
///| A=255）してから `@decode.decode`/`decode_js` に通し、パイプライン全段
///| （binarize→locate→extract→format/version→read_data→decode_data）が
///| 結合して動くことを確認する。

///| Matrix → RGBA Bytes。返り値は (bytes, width, height)。
fn matrix_to_rgba(
  m : @encode.Matrix,
  module_px : Int,
  margin_px : Int,
  black : Int,
  white : Int,
) -> (Bytes, Int, Int) {
  let dim = margin_px * 2 + m.size * module_px
  let buf = FixedArray::make(dim * dim * 4, b'\x00')
  for y = 0; y < dim; y = y + 1 {
    for x = 0; x < dim; x = x + 1 {
      let mx = (x - margin_px) / module_px
      let my = (y - margin_px) / module_px
      let in_matrix = x >= margin_px &&
        y >= margin_px &&
        mx < m.size &&
        my < m.size
      let v = if in_matrix && m.get(mx, my) { black } else { white }
      let i = (y * dim + x) * 4
      buf[i] = v.to_byte()
      buf[i + 1] = v.to_byte()
      buf[i + 2] = v.to_byte()
      buf[i + 3] = b'\xFF'
    }
  }
  (Bytes::from_fixedarray(buf), dim, dim)
}

///| 白黒を入れ替えたRGBA Bytesを作る（invert往復テスト用）。
fn invert_rgba(data : Bytes, width : Int, height : Int) -> Bytes {
  let buf = FixedArray::make(width * height * 4, b'\x00')
  for i = 0; i < width * height; i = i + 1 {
    let o = i * 4
    let v = 255 - data[o].to_int()
    buf[o] = v.to_byte()
    buf[o + 1] = v.to_byte()
    buf[o + 2] = v.to_byte()
    buf[o + 3] = b'\xFF'
  }
  Bytes::from_fixedarray(buf)
}

test "decode: full pipeline round-trip for ASCII text" {
  let m = match @encode.encode("FULL PIPELINE", @encode.EcLevel::M, None) {
    Some(m) => m
    None => fail("encode failed")
  }
  let (data, w, h) = matrix_to_rgba(m, 4, 16, 30, 220)
  let r = match @decode.decode(data, w, h, false) {
    Some(r) => r
    None => fail("decode failed")
  }
  assert_eq(r.text, "FULL PIPELINE")
  assert_eq(r.version, (m.size - 17) / 4)
  assert_eq(r.ec, @encode.EcLevel::M)
  assert_eq(r.corners.length(), 4)
  // TL は余白(16,16)近傍、BR は余白+モジュール格子分の対角近傍
  let tl = r.corners[0]
  let br = r.corners[2]
  assert_true(Double::abs(tl.x - 16.0) <= 8.0)
  assert_true(Double::abs(tl.y - 16.0) <= 8.0)
  let expect_br = (16 + m.size * 4).to_double()
  assert_true(Double::abs(br.x - expect_br) <= 8.0)
  assert_true(Double::abs(br.y - expect_br) <= 8.0)
}

test "decode: inverted image only decodes with invert=true" {
  let m = match @encode.encode("INVERT ME", @encode.EcLevel::M, None) {
    Some(m) => m
    None => fail("encode failed")
  }
  let (data, w, h) = matrix_to_rgba(m, 4, 16, 30, 220)
  let inverted = invert_rgba(data, w, h)
  assert_true(@decode.decode(inverted, w, h, false) is None)
  let r = match @decode.decode(inverted, w, h, true) {
    Some(r) => r
    None => fail("decode with invert=true should succeed")
  }
  assert_eq(r.text, "INVERT ME")
}

test "decode_js: wrong data length returns empty string" {
  let m = match @encode.encode("X", @encode.EcLevel::M, None) {
    Some(m) => m
    None => fail("encode failed")
  }
  let (data, w, h) = matrix_to_rgba(m, 4, 16, 30, 220)
  let truncated = data[0:data.length() - 4].to_bytes()
  assert_eq(@decode.decode_js(truncated, w, h, false), "")
}

test "decode_js: noise-only image returns empty string" {
  let w = 64
  let h = 64
  let buf = FixedArray::make(w * h * 4, b'\x00')
  for y = 0; y < h; y = y + 1 {
    for x = 0; x < w; x = x + 1 {
      let v = (x * 37 + y * 91) % 256
      let i = (y * w + x) * 4
      buf[i] = v.to_byte()
      buf[i + 1] = v.to_byte()
      buf[i + 2] = v.to_byte()
      buf[i + 3] = b'\xFF'
    }
  }
  let data = Bytes::from_fixedarray(buf)
  assert_true(@decode.decode(data, w, h, true) is None)
  assert_eq(@decode.decode_js(data, w, h, true), "")
}

test "decode_js: valid image produces parseable JSON containing text" {
  let m = match @encode.encode("JSON OK", @encode.EcLevel::M, None) {
    Some(m) => m
    None => fail("encode failed")
  }
  let (data, w, h) = matrix_to_rgba(m, 4, 16, 30, 220)
  let out = @decode.decode_js(data, w, h, false)
  assert_true(out.contains("\"text\":\"JSON OK\""))
  // 実際にJSONとしてパース可能であることも確認（Task 9側の詳細検証への橋渡し）
  let parsed = @json.parse(out)
  match parsed {
    Object(obj) =>
      match obj.get("text") {
        Some(String(t)) => assert_eq(t, "JSON OK")
        _ => fail("text field missing or wrong type")
      }
    _ => fail("decode_js output is not a JSON object")
  }
}

test "decode: Kanji/UTF-8 text round-trip" {
  let text = "こんにちは🦑"
  let m = match @encode.encode(text, @encode.EcLevel::M, None) {
    Some(m) => m
    None => fail("encode failed")
  }
  let (data, w, h) = matrix_to_rgba(m, 4, 16, 30, 220)
  let r = match @decode.decode(data, w, h, false) {
    Some(r) => r
    None => fail("decode failed")
  }
  assert_eq(r.text, text)
  assert_eq(r.bytes, @encode.utf8_encode(text))
}

test "decode_js: JSON escaping for quotes and backslashes" {
  let text = "A\"B\\C"
  let m = match @encode.encode(text, @encode.EcLevel::M, None) {
    Some(m) => m
    None => fail("encode failed")
  }
  let (data, w, h) = matrix_to_rgba(m, 4, 16, 30, 220)
  let out = @decode.decode_js(data, w, h, false)
  let parsed = @json.parse(out)
  match parsed {
    Object(obj) =>
      match obj.get("text") {
        Some(String(t)) => assert_eq(t, text)
        _ => fail("text field missing or wrong type")
      }
    _ => fail("decode_js output is not a JSON object")
  }
}

test "decode_js: guard branches return empty string without panicking" {
  let tiny = Bytes::from_fixedarray(FixedArray::make(4, b'\x00'))
  // width=0 / height=0 / 負値
  assert_eq(@decode.decode_js(tiny, 0, 10, false), "")
  assert_eq(@decode.decode_js(tiny, 10, 0, false), "")
  assert_eq(@decode.decode_js(tiny, 10, -1, false), "")
  assert_eq(@decode.decode_js(tiny, -1, 10, false), "")
  // Int32 オーバーフロー: 65536*65536 は Int の積だと 0 にラップして
  // 旧ガードをすり抜けていた（レビュー指摘の再現ケース）。
  // Int64 積で 4.29e9 > 16M と判定され "" になること（パニックしないこと）。
  assert_eq(@decode.decode_js(tiny, 65536, 65536, false), "")
  // 空データ + 65536x65536 が真の致命ケース: 旧ガードは 0 == 0*4 で
  // 両方すり抜け、binarize が範囲外パニックしていた（mutation checkで
  // 旧ロジックに戻すとこの行だけがパニックすることを確認済み）。
  let empty = Bytes::from_fixedarray(FixedArray::make(0, b'\x00'))
  assert_eq(@decode.decode_js(empty, 65536, 65536, false), "")
  // 65535*65535 ≈ 4.29e9 も Int32 max 超（正のオーバーフロー域）
  assert_eq(@decode.decode_js(tiny, 65535, 65535, false), "")
  // 16M 画素超（5000*4000=20M、オーバーフローなし域）: 画素数ガードが
  // データ長ガード・データアクセスより先に発火し "" を返す
  assert_eq(@decode.decode_js(tiny, 5000, 4000, false), "")
}
