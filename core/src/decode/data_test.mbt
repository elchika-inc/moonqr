///| decode_data の結合テスト。
///|
///| ①②③ ラウンドトリップ: 自前エンコーダ（BitWriter+write_segment+assemble）で
///| 独立に得たデータコードワードを decode_data に通し、元テキストへ復元できることを
///| 確認する。ここで使う版（v1-M, v2-M）はいずれも単一ブロック（tables.mbt 行1・行5が
///| [1, ...] であることを確認済み）なので、assemble() の生出力（インターリーブ済み・
///| パディング込み）の先頭 data_capacity 個がそのまま「デインターリーブ済みコードワード」
///| （read_data の契約と同じ形）として使える（Task 6 の教訓：複数ブロック版では
///| インターリーブを経由しないと一致しない）。
///|
///| ④ Kanji: 自前エンコーダはKanji未対応のため手組みのコードワードでテストする。
///| 「点茗」（SJIS 0x935F / 0xE4AA、ISO 18004 の古典例）を ISO 18004 の13bit圧縮式
///| （c' = c0 - 0x8140 または c0 - 0xC140、k = (c'>>8)*0xC0 + (c'&0xFF)）で手計算し、
///| モード1000 + CCI(v1は8bit) + k1(13bit) + k2(13bit) を詰めた
///| [0x80, 0x26, 0xCF, 0xEA, 0xA8] を使う（導出は scripts 外でPythonにより事前検証済み、
///| 本ファイルはその結果のバイト列を固定値として使うのみ）。
///| decode_kanji側のデコード式（c = (k/0xC0)<<8 | k%0xC0; c<0x1F00?+0x8140:+0xC140）で
///| 逆算すると元のSJISコードに一致することを確認済み。
///|
///| ⑤ ECI: モード0111 + designatorフラグ0 + 7bit値26（UTF-8指定、ただし本ポートは
///| 値を見ずbyteを常にUTF-8として解釈する仕様）+ Byteモードで"AB"を続けた
///| [0x71, 0xA4, 0x02, 0x41, 0x42] を使う。
///|
///| ⑥ 異常系: garbage mode indicator（未割り当てモード値0110=0x6）+ 末尾2bitが非0
///| （[0x10, 0x05, 0x5B]）→ jsQR の
///| `stream.available() === 0 || stream.readBits(...) === 0` 判定が両方falseになり
///| decode()が暗黙にundefinedを返すケースを鏡映してNoneを期待する。
///| 対照として、末尾ビットがすべて0で終端子なしに使い切る場合（[0x10, 0x00]）は
///| 「暗黙の終端子」として成功することも確認する（jsQRの同判定のtrue側）。

///| 指定版数/テキスト/ECで decode_data に渡せる「デインターリーブ済みコードワード」を
///| 独立算出する（write_segment+assemble経路）。単一ブロック版のみ対応。
fn expected_codewords(
  text : String,
  mode : @encode.Mode,
  version : Int,
  ec : @encode.EcLevel,
) -> Array[Int] {
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

test "decode_data: roundtrip numeric v1-M" {
  let text = "0123456789"
  let cw = expected_codewords(text, @encode.Mode::Numeric, 1, @encode.EcLevel::M)
  let got = match @decode.decode_data(cw, 1) {
    Some(d) => d
    None => abort("expected decode_data to succeed for numeric roundtrip")
  }
  assert_eq(got.text, text)
}

test "decode_data: roundtrip alphanumeric v2-M (full charset tail)" {
  let text = "HELLO WORLD $%*+-./:"
  let cw = expected_codewords(
    text,
    @encode.Mode::Alphanumeric,
    2,
    @encode.EcLevel::M,
  )
  let got = match @decode.decode_data(cw, 2) {
    Some(d) => d
    None => abort("expected decode_data to succeed for alphanumeric roundtrip")
  }
  assert_eq(got.text, text)
}

test "decode_data: roundtrip byte/UTF-8 v2-M (multibyte + emoji)" {
  let text = "héllo wörld 🦑"
  let cw = expected_codewords(text, @encode.Mode::Byte, 2, @encode.EcLevel::M)
  let got = match @decode.decode_data(cw, 2) {
    Some(d) => d
    None => abort("expected decode_data to succeed for byte/UTF-8 roundtrip")
  }
  assert_eq(got.text, text)
  // bytesフィールド: byteセグメントで積んだ生バイトはUTF-8オクテット列そのもの。
  assert_eq(got.bytes, @encode.utf8_encode(text))
}

test "decode_data: kanji hand-built codewords (\"点茗\", ISO 18004 example)" {
  let cw = [0x80, 0x26, 0xCF, 0xEA, 0xA8]
  let got = match @decode.decode_data(cw, 1) {
    Some(d) => d
    None => abort("expected decode_data to succeed for kanji")
  }
  assert_eq(got.text, "点茗")
}

test "decode_data: ECI(UTF-8 26) + byte segment \"AB\"" {
  let cw = [0x71, 0xA4, 0x02, 0x41, 0x42]
  let got = match @decode.decode_data(cw, 1) {
    Some(d) => d
    None => abort("expected decode_data to succeed for ECI+byte")
  }
  assert_eq(got.text, "AB")
  assert_eq(got.bytes, [0x41, 0x42])
}

test "decode_data: garbage mode indicator followed by non-zero remainder -> None" {
  // mode=0001(Numeric) cci(10bit)=1 digit(4bit)=5 -> "5" 読了後、
  // 未割り当てモード0110(4bit,読み飛ばし) -> 残り2bitが "11"(非0) で終端。
  let cw = [0x10, 0x05, 0x5B]
  match @decode.decode_data(cw, 1) {
    None => ()
    Some(_) => abort("expected None: non-zero remainder without terminator")
  }
}

test "decode_data: terminator-less exhaustion with all-zero remainder -> graceful stop" {
  // mode=0001(Numeric) cci(10bit)=0 -> 数字ゼロ個。残り2bitが "00" で終端子なしに終了。
  let cw = [0x10, 0x00]
  let got = match @decode.decode_data(cw, 1) {
    Some(d) => d
    None => abort("expected graceful stop (Some) when remainder is all-zero")
  }
  assert_eq(got.text, "")
  assert_eq(got.bytes, [])
}

test "decode_data: structured append first symbol is not an empty success" {
  // Structured Append header:
  // mode=0011 | position=0000 (first symbol) | total-1=0001 | parity=00000000 |
  // terminator=0000。未対応モードとして None を返し、空文字の成功と区別する。
  let cw = [0x30, 0x10, 0x00]
  match @decode.decode_data(cw, 1) {
    Some(_) => abort("unsupported Structured Append must not decode as empty text")
    None => assert_true(true)
  }
}

test "decode_data: FNC1 first position continues into the following data segment" {
  // FNC1 first position は追加ヘッダを持たず、直後に通常のデータセグメントが続く。
  // mode=0101 | Byte mode=0100 | CCI(v1)=2 | "AB" | Terminator を実在形として組む。
  let w = @encode.BitWriter::new()
  w.write(0b0101, 4)
  w.write(0b0100, 4)
  w.write(2, @encode.cci_bits(@encode.Mode::Byte, 1))
  w.write(0x41, 8)
  w.write(0x42, 8)
  w.write(0b0000, 4)
  let cw = w.to_codewords()
  match @decode.decode_data(cw, 1) {
    Some(d) => assert_eq(d.text, "AB")
    None => abort("FNC1 first position must continue into the Byte segment")
  }
}

test "decode_data: FNC1 second position is not an empty success" {
  // mode=1001 | application indicator=00000000 | terminator=0000。
  // 4bitだけ読み飛ばすと application indicator 冒頭の0を終端子と誤認する。
  let cw = [0x90, 0x00]
  match @decode.decode_data(cw, 1) {
    Some(_) => abort("unsupported FNC1 second position must not decode as empty text")
    None => assert_true(true)
  }
}

test "decode_data resumes after unknown mode nibble" {
  // 真に未割り当てのモード(0110)の直後に有効な Byte セグメントが続くケース。
  // 0x3 は Structured Append として定義済みなので、未知モードの例には使わない。
  // jsQR と同じく「4bitだけ読み飛ばして継続」する挙動を確認する。
  // コードワードは手計算せず @encode.BitWriter で意図したビット列そのものを組み立てる:
  //   0110(未知mode,4bit) | 0100(byteモード,4bit) | CCI(8bit,v1)=2 | 'A'(8bit) | 'B'(8bit) | 0000(終端,4bit)
  // 合計36bit -> to_codewords() で5バイトにパディングされる。
  let w = @encode.BitWriter::new()
  w.write(0b0110, 4) // 未割り当てモード: 4bitのみ消費してスキップされるはず
  w.write(0b0100, 4) // Byteモード
  w.write(2, @encode.cci_bits(@encode.Mode::Byte, 1)) // CCI: length=2
  w.write(0x41, 8) // 'A'
  w.write(0x42, 8) // 'B'
  w.write(0b0000, 4) // 終端子
  let cw = w.to_codewords()
  match @decode.decode_data(cw, 1) {
    Some(d) => assert_eq(d.text, "AB")
    None => abort("must resume after unknown mode")
  }
}

test "decode_data rejects out-of-range alphanumeric index" {
  // alnum ペア値 11bit に 45*45=2025 以上（不正）を入れる -> None
  // コードワードは手計算せず @encode.BitWriter で意図したビット列そのものを組み立てる:
  //   0010(alnumモード,4bit) | CCI(9bit,v1)=2 | 2047(11bit, >= 2025で不正)
  // decode_alphanumeric は a=2047/45=45 > 44 の時点で None を返すため、
  // 終端子や2文字目分の追加ビットは不要（値を読み切った直後に弾かれる）。
  let w = @encode.BitWriter::new()
  w.write(0b0010, 4) // Alphanumericモード
  w.write(2, @encode.cci_bits(@encode.Mode::Alphanumeric, 1)) // CCI: length=2
  w.write(2047, 11) // 不正なペア値（2025以上）
  let cw = w.to_codewords()
  match @decode.decode_data(cw, 1) {
    Some(_) => abort("invalid alnum pair must be rejected")
    None => assert_true(true)
  }
}

///| モードと文字数を明示して、エンコーダの文字変換を通さずByte入力を組む。
fn hand_built_byte_codewords(payload : Array[Int]) -> Array[Int] {
  let w = @encode.BitWriter::new()
  w.write(0x4, 4)
  w.write(payload.length(), 8)
  for byte in payload {
    w.write(byte, 8)
  }
  w.write(0, 4)
  w.to_codewords()
}

test "decode_data: 空の符号語 → 空のテキストとbytes" {
  guard @decode.decode_data([], 1) is Some(got) else { abort("成功を期待") }
  assert_eq(got.text, "")
  assert_eq(got.bytes, [])
}

test "decode_data: 終端子の直後が未対応モード → 後続を読まず成功" {
  guard @decode.decode_data([0x03], 1) is Some(got) else { abort("成功を期待") }
  assert_eq(got.text, "")
  assert_eq(got.bytes, [])
}

test "decode_data: 未割当モードの直後にByte → 指示子だけ飛ばして文字を復元" {
  for mode in [0x6, 0xA, 0xB, 0xC, 0xD, 0xE, 0xF] {
    guard @decode.decode_data([(mode << 4) | 0x4, 1, 0x41], 1) is Some(got) else {
      abort("未割当モード後の継続を期待")
    }
    assert_eq(got.text, "A")
    assert_eq(got.bytes, [0x41])
  }
}

test "decode_data: 数値グループが999・99・9 → 上限値を復元" {
  for case in [
    (3, 10, 999, "999"),
    (2, 7, 99, "99"),
    (1, 4, 9, "9"),
  ] {
    let (digits, width, value, expected) = case
    let w = @encode.BitWriter::new()
    w.write(0x1, 4)
    w.write(digits, 10)
    w.write(value, width)
    w.write(0, 4)
    guard @decode.decode_data(w.to_codewords(), 1) is Some(got) else {
      abort("数値グループ上限の成功を期待")
    }
    assert_eq(got.text, expected)
    assert_eq(got.bytes, @encode.utf8_encode(expected))
  }
}

test "decode_data: 先頭0を含む複数数値グループ → 桁数とbytesの順序を保持" {
  let w = @encode.BitWriter::new()
  w.write(0x1, 4)
  w.write(8, 10)
  w.write(7, 10)
  w.write(80, 10)
  w.write(9, 7)
  w.write(0, 4)
  guard @decode.decode_data(w.to_codewords(), 1) is Some(got) else {
    abort("数値グループの復元を期待")
  }
  assert_eq(got.text, "00708009")
  assert_eq(got.bytes, [48, 48, 55, 48, 56, 48, 48, 57])
}

test "decode_data: 3桁グループが1000 → None" {
  let w = @encode.BitWriter::new()
  w.write(0x1, 4)
  w.write(3, 10)
  w.write(1000, 10)
  assert_eq(@decode.decode_data(w.to_codewords(), 1), None)
}

test "decode_data: 2桁グループが100 → None" {
  let w = @encode.BitWriter::new()
  w.write(0x1, 4)
  w.write(2, 10)
  w.write(100, 7)
  assert_eq(@decode.decode_data(w.to_codewords(), 1), None)
}

test "decode_data: 1桁グループが10 → None" {
  let w = @encode.BitWriter::new()
  w.write(0x1, 4)
  w.write(1, 10)
  w.write(10, 4)
  assert_eq(@decode.decode_data(w.to_codewords(), 1), None)
}

test "decode_data: 数値グループのビット不足 → None" {
  // mode=1、CCI=3の後は2bitしか残らず、3桁に必要な10bitを読めない。
  assert_eq(@decode.decode_data([0x10, 0x0C], 1), None)
}

test "decode_data: 数値の文字数指示子が途中で切れる → None" {
  assert_eq(@decode.decode_data([0x10], 1), None)
}

test "decode_data: 版9・10・26・27の数値 → 版に合う文字数幅で復元" {
  for case in [(9, 10), (10, 12), (26, 12), (27, 14)] {
    let (version, count_width) = case
    let w = @encode.BitWriter::new()
    w.write(0x1, 4)
    w.write(1, count_width)
    w.write(9, 4)
    w.write(0, 4)
    guard @decode.decode_data(w.to_codewords(), version) is Some(got) else {
      abort("版ごとの文字数幅での成功を期待")
    }
    assert_eq(got.text, "9")
    assert_eq(got.bytes, [57])
  }
}

test "decode_data: UTF-8の各幅とサロゲート前後の境界 → 元の文字とbytes" {
  for case in [
    ([0x00], 0x00),
    ([0x7F], 0x7F),
    ([0xC2, 0x80], 0x80),
    ([0xDF, 0xBF], 0x7FF),
    ([0xE0, 0xA0, 0x80], 0x800),
    ([0xED, 0x9F, 0xBF], 0xD7FF),
    ([0xEE, 0x80, 0x80], 0xE000),
    ([0xEF, 0xBF, 0xBF], 0xFFFF),
    ([0xF0, 0x90, 0x80, 0x80], 0x10000),
    ([0xF4, 0x8F, 0xBF, 0xBF], 0x10FFFF),
  ] {
    let (payload, codepoint) = case
    guard @decode.decode_data(hand_built_byte_codewords(payload), 1) is Some(got) else {
      abort("Byteセグメントの成功を期待")
    }
    assert_eq(got.text, Int::unsafe_to_char(codepoint).to_string())
    assert_eq(got.bytes, payload)
  }
}

test "decode_data: 空のByteセグメント → 空のテキストとbytes" {
  guard @decode.decode_data(hand_built_byte_codewords([]), 1) is Some(got) else {
    abort("空のByteセグメントの成功を期待")
  }
  assert_eq(got.text, "")
  assert_eq(got.bytes, [])
}

test "decode_data: 過長な2バイトUTF-8 → 文字を捨てbytesを保持" {
  let payload = [0xC0, 0xAF]
  guard @decode.decode_data(hand_built_byte_codewords(payload), 1) is Some(got) else {
    abort("Byteセグメントの成功を期待")
  }
  assert_eq(got.text, "")
  assert_eq(got.bytes, payload)
}

test "decode_data: 過長な3バイトUTF-8 → 文字を捨てbytesを保持" {
  let payload = [0xE0, 0x9F, 0xBF]
  guard @decode.decode_data(hand_built_byte_codewords(payload), 1) is Some(got) else {
    abort("Byteセグメントの成功を期待")
  }
  assert_eq(got.text, "")
  assert_eq(got.bytes, payload)
}

test "decode_data: 過長な4バイトUTF-8 → 文字を捨てbytesを保持" {
  let payload = [0xF0, 0x8F, 0xBF, 0xBF]
  guard @decode.decode_data(hand_built_byte_codewords(payload), 1) is Some(got) else {
    abort("Byteセグメントの成功を期待")
  }
  assert_eq(got.text, "")
  assert_eq(got.bytes, payload)
}

test "decode_data: UTF-8がサロゲート範囲 → 文字を捨てbytesを保持" {
  for payload in [[0xED, 0xA0, 0x80], [0xED, 0xBF, 0xBF]] {
    guard @decode.decode_data(hand_built_byte_codewords(payload), 1) is Some(got) else {
      abort("Byteセグメントの成功を期待")
    }
    assert_eq(got.text, "")
    assert_eq(got.bytes, payload)
  }
}

test "decode_data: UTF-8がU+10FFFF超 → 文字を捨てbytesを保持" {
  let payload = [0xF4, 0x90, 0x80, 0x80]
  guard @decode.decode_data(hand_built_byte_codewords(payload), 1) is Some(got) else {
    abort("Byteセグメントの成功を期待")
  }
  assert_eq(got.text, "")
  assert_eq(got.bytes, payload)
}

test "decode_data: UTF-8が途中で切れる → 文字を捨てbytesを保持" {
  for payload in [[0xC2], [0xE3, 0x81], [0xF0, 0x90, 0x80]] {
    guard @decode.decode_data(hand_built_byte_codewords(payload), 1) is Some(got) else {
      abort("Byteセグメントの成功を期待")
    }
    assert_eq(got.text, "")
    assert_eq(got.bytes, payload)
  }
}

test "decode_data: UTF-8の継続位置にASCII → 文字を捨てbytesを保持" {
  for payload in [
    [0xC2, 0x41],
    [0xE3, 0x41, 0x82],
    [0xE3, 0x81, 0x41],
    [0xF0, 0x41, 0x80, 0x80],
    [0xF0, 0x90, 0x41, 0x80],
    [0xF0, 0x90, 0x80, 0x41],
  ] {
    guard @decode.decode_data(hand_built_byte_codewords(payload), 1) is Some(got) else {
      abort("Byteセグメントの成功を期待")
    }
    assert_eq(got.text, "")
    assert_eq(got.bytes, payload)
  }
}

test "decode_data: UTF-8の先頭が継続バイトまたは0xF8 → 文字を捨てbytesを保持" {
  for payload in [[0x80], [0xF8]] {
    guard @decode.decode_data(hand_built_byte_codewords(payload), 1) is Some(got) else {
      abort("Byteセグメントの成功を期待")
    }
    assert_eq(got.text, "")
    assert_eq(got.bytes, payload)
  }
}

test "decode_data: Byte内の正常文字の後に不正UTF-8 → そのセグメントの文字全体を捨てる" {
  let payload = [0x41, 0xC0, 0xAF]
  guard @decode.decode_data(hand_built_byte_codewords(payload), 1) is Some(got) else {
    abort("Byteセグメントの成功を期待")
  }
  assert_eq(got.text, "")
  assert_eq(got.bytes, payload)
}

test "decode_data: 正常Byte・不正UTF-8・正常Byte → 不正セグメントだけ文字を捨てて継続" {
  let w = @encode.BitWriter::new()
  for payload in [[0x41], [0xC0, 0xAF], [0x42]] {
    w.write(0x4, 4)
    w.write(payload.length(), 8)
    for byte in payload {
      w.write(byte, 8)
    }
  }
  w.write(0, 4)
  guard @decode.decode_data(w.to_codewords(), 1) is Some(got) else {
    abort("Byteセグメントを越える継続を期待")
  }
  assert_eq(got.text, "AB")
  assert_eq(got.bytes, [0x41, 0xC0, 0xAF, 0x42])
}
