///| mirror_matrix / try_decode_matrix の直接テスト（Task 10: 対角ミラー
///| 再試行のwhiteboxピン。jsQR コーパスパリティ測定で bike-1 ケースが
///| locator の top-right/bottom-left 取り違え起因で1件のみ差分を出し、
///| jsQR `decoder.ts` の対角ミラー再試行を移植して解消した。この
///| whitebox テストは実写真フィクスチャ（fixtures/、gitignore・要ネット
///| ワーク）に頼らず、mirror_matrix 自体の正しさを直接ピン留めする）。
///|
///| `@encode.encode` で得た最終マスク済み行列をそのまま BitMatrix へ変換し、
///| binarizer/locator/extractor を経由せず `try_decode_matrix` を直接叩く。
///| mirror_matrix は対角線(TL-BR)転置で involution（2回適用すると元に戻る）
///| でなければならない。転置後の行列は（対称な特殊ケースでない限り）
///| データコードワードの読み順が崩れて decode に失敗するはずなので、
///| 「転置→失敗」「再転置→成功」の往復をアサートすることで、
///| mirror_matrix が no-op や誤った変換に壊れた場合を検出できる。

fn matrix_to_bitmatrix(m : @encode.Matrix) -> BitMatrix {
  let bm = BitMatrix::make(m.size, m.size)
  for y = 0; y < m.size; y = y + 1 {
    for x = 0; x < m.size; x = x + 1 {
      bm.set(x, y, m.get(x, y))
    }
  }
  bm
}

test "mirror_matrix: transpose breaks decode, second transpose restores it (involution)" {
  let em = match @encode.encode("MIRROR TEST", @encode.EcLevel::M, None) {
    Some(m) => m
    None => fail("encode failed")
  }
  let bm = matrix_to_bitmatrix(em)
  let dim = em.size

  // 元の行列は try_decode_matrix 単体で成功する（locator/extractorを介さず）。
  match try_decode_matrix(bm, dim) {
    Some((_, _, dd)) => assert_eq(dd.text, "MIRROR TEST")
    None => fail("expected clean matrix to decode via try_decode_matrix")
  }

  // 転置すると、このテキスト/バージョンの行列は対角対称ではないため
  // データコードワードの読み順が崩れて失敗する。
  mirror_matrix(bm)
  assert_true(try_decode_matrix(bm, dim) is None)

  // 再度転置すると元の行列に戻り（involution）、再び成功する。
  mirror_matrix(bm)
  match try_decode_matrix(bm, dim) {
    Some((_, _, dd)) => assert_eq(dd.text, "MIRROR TEST")
    None =>
      fail(
        "expected mirror_matrix to be an involution restoring decodability",
      )
  }
}

///| `scan()` レベルの結合確認: 対角転置した完全なQR画像（binarize/locate/
///| extract を実際に通す）が invert無しの decode() で成功することを見る。
///| locator は正立画像でも通常「top_left/top_right/bottom_left」を正しい
///| 幾何で見つけるため、抽出行列自体は転置されない。ここでは
///| matrix_to_bitmatrix ではなく画像そのものを転置することで、抽出後の
///| 行列が転置された状態を模擬する（bike-1 の実際の失敗要因＝locator の
///| ファインダ取り違えとは異なる転置経路だが、scan() のミラー再試行が
///| 「抽出行列が転置されているケース全般」を救うことを確認する）。
test "decode: transposed clean QR image recovers via scan's mirror retry" {
  let em = match @encode.encode("TRANSPOSED IMG", @encode.EcLevel::M, None) {
    Some(m) => m
    None => fail("encode failed")
  }
  let dim = em.size
  let module_px = 4
  let margin_px = 16
  let side = margin_px * 2 + dim * module_px
  let buf = FixedArray::make(side * side * 4, b'\x00')
  for y = 0; y < side; y = y + 1 {
    for x = 0; x < side; x = x + 1 {
      // (x,y) と (y,x) を入れ替えて描画 = 画像全体を転置する
      let mx = (y - margin_px) / module_px
      let my = (x - margin_px) / module_px
      let in_matrix = x >= margin_px &&
        y >= margin_px &&
        mx < dim &&
        my < dim
      let black = in_matrix && em.get(mx, my)
      let v = if black { 30 } else { 220 }
      let i = (y * side + x) * 4
      buf[i] = v.to_byte()
      buf[i + 1] = v.to_byte()
      buf[i + 2] = v.to_byte()
      buf[i + 3] = b'\xFF'
    }
  }
  let data = Bytes::from_array(buf[:])
  let r = match decode(data, side, side, false) {
    Some(r) => r
    None => fail("expected mirror retry to recover the transposed image")
  }
  assert_eq(r.text, "TRANSPOSED IMG")
}
