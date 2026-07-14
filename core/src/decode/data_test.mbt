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
///| ⑥ 異常系: garbage mode indicator（未定義モード値0011=0x3）+ 末尾2bitが非0
///| （[0x10, 0x05, 0x4F]）→ jsQR の
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
  // 未定義モード0011(4bit,読み飛ばし) -> 残り2bitが "11"(非0) で終端。
  let cw = [0x10, 0x05, 0x4F]
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
