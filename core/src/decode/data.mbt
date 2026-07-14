///| 移植元: jsQR (Apache-2.0), commit 8e6a036beafa7053dd44b1b76ac578d22b1b3311
///| https://github.com/cozmo/jsQR/blob/8e6a036beafa7053dd44b1b76ac578d22b1b3311/src/decoder/decodeData/index.ts
///| （ビット読取部は同ディレクトリの BitStream.ts を private BitReader として鏡映移植）
///|
///| jsQR の `decode()` は「モード指示子を読む→対応するセグメントを読む」をストリーム終端
///| （4bit未満）まで繰り返し、終端子(0000)で即終了、ループを抜けたときは残りビットが
///| 0個または全0であれば成功、そうでなければ失敗（jsQR は暗黙 undefined を返す＝本ポートでは
///| None）という構造。未定義のモード値（0x3, 0x5, 0x6, 0x9-0xF。StructuredAppendの0x3も
///| jsQR 側に分岐が無いため含む）は jsQR に対応する分岐が無く、4bit消費のみでペイロードを
///| 一切読まずループへ戻る——本ポートもこれをそのまま鏡映する（=独自の解釈を足さない）。
///|
///| ECI逸脱: jsQR は1/2/3バイト designator を正しくパースして assignmentNumber を
///| chunks に記録するが、本ポートは「UTF-8(26)のみ対応、他のECI指定もbyteをUTF-8として
///| 解釈する」という自スペック上の割り切りにより、assignmentNumber の値を一切見ない
///| （ビット位置がズレないよう designator 構造のパースのみ行い、値は破棄する）。
///| これは仕様上のポリシーであり jsQR からの逸脱として意図的。
///|
///| bytes フィールドの意味論: jsQR の `result.bytes` は Byte/Kanji セグメントだけでなく
///| Numeric（ASCII数字）・Alphanumeric（ASCII文字）のバイト表現も `bytes.push(...)` して
///| おり、「全セグメント横断で蓄積される」。ECI はバイトを生成しない。本ポートもこれを
///| 忠実に鏡映する（brief に「ALL decoded bytes across byte segments」とあったが、実際の
///| jsQR ソースは byte 型セグメントに限らず全モードで bytes を積んでおり、本ポートは
///| ソース確認済みの後者の挙動を正とする）。

///| データコードワード列から復号したテキストと、全セグメント横断で蓄積された生バイト列。
pub struct DecodedData {
  text : String
  bytes : Array[Int]
} derive(Eq, Debug)

///| BitStream.ts の鏡映。MSB-firstでビット列を読む。バイト境界最適化はせず、
///| 1bitずつ読み進める単純実装（正しさを優先。BitWriter.write の逆操作に相当）。
priv struct BitReader {
  codewords : Array[Int]
  mut bit_pos : Int
}

fn BitReader::new(codewords : Array[Int]) -> BitReader {
  { codewords, bit_pos: 0 }
}

fn BitReader::available(self : BitReader) -> Int {
  self.codewords.length() * 8 - self.bit_pos
}

///| n bits を MSB-first で読む。残りビット数が足りなければ None
///| （jsQR の `readBits` が例外を投げるケースに相当。本ポートでは Option で表現）。
fn BitReader::read_bits(self : BitReader, n : Int) -> Int? {
  if n > self.available() {
    return None
  }
  let mut result = 0
  for i = 0; i < n; i = i + 1 {
    let byte_idx = self.bit_pos / 8
    let bit_idx = self.bit_pos % 8 // 0 = そのバイトのMSB
    let bit = (self.codewords[byte_idx] >> (7 - bit_idx)) & 1
    result = (result << 1) | bit
    self.bit_pos = self.bit_pos + 1
  }
  Some(result)
}

///| Array[Char] を String へ（StringBuilder 経由。1文字ずつの文字列連結より効率的）。
fn chars_to_string(chars : Array[Char]) -> String {
  let sb = StringBuilder(size_hint=chars.length())
  sb.write_iter(chars.iter())
  sb.to_string()
}

///| 英数字モードの index → 文字（encode 側 alnum_index の逆写像）。
///| 範囲外（0-44 以外）は呼び出し元で弾く。
fn alnum_char(idx : Int) -> Char {
  if idx < 10 {
    Int::unsafe_to_char(48 + idx) // '0'-'9'
  } else if idx < 36 {
    Int::unsafe_to_char(65 + idx - 10) // 'A'-'Z'
  } else {
    match idx {
      36 => ' '
      37 => '$'
      38 => '%'
      39 => '*'
      40 => '+'
      41 => '-'
      42 => '.'
      43 => '/'
      _ => ':' // idx == 44 のみ到達する想定（呼び出し元で 0-44 範囲チェック済み）
    }
  }
}

///| UTF-8 バイト列 → Unicodeコードポイント列。不正なバイト列は None
///| （jsQR の decodeURIComponent 失敗＝try/catchでtext破棄に相当する判定を、
///| 標準的なUTF-8構造検証として明示的に実装）。
fn utf8_decode(bytes : Array[Int]) -> Array[Int]? {
  let cps : Array[Int] = []
  let mut i = 0
  let n = bytes.length()
  fn is_cont(b : Int) -> Bool {
    (b & 0xC0) == 0x80
  }

  while i < n {
    let b0 = bytes[i]
    if b0 < 0x80 {
      cps.push(b0)
      i = i + 1
    } else if (b0 & 0xE0) == 0xC0 {
      if i + 1 >= n || !is_cont(bytes[i + 1]) {
        return None
      }
      let cp = ((b0 & 0x1F) << 6) | (bytes[i + 1] & 0x3F)
      if cp < 0x80 {
        return None // overlong
      }
      cps.push(cp)
      i = i + 2
    } else if (b0 & 0xF0) == 0xE0 {
      if i + 2 >= n || !is_cont(bytes[i + 1]) || !is_cont(bytes[i + 2]) {
        return None
      }
      let b2 = bytes[i + 2]
      let cp = ((b0 & 0x0F) << 12) | ((bytes[i + 1] & 0x3F) << 6) | (b2 & 0x3F)
      if cp < 0x800 || (cp >= 0xD800 && cp <= 0xDFFF) {
        return None // overlong または UTF-16 サロゲート範囲
      }
      cps.push(cp)
      i = i + 3
    } else if (b0 & 0xF8) == 0xF0 {
      if i + 3 >= n ||
        !is_cont(bytes[i + 1]) ||
        !is_cont(bytes[i + 2]) ||
        !is_cont(bytes[i + 3]) {
        return None
      }
      let cp = ((b0 & 0x07) << 18) |
        ((bytes[i + 1] & 0x3F) << 12) |
        ((bytes[i + 2] & 0x3F) << 6) |
        (bytes[i + 3] & 0x3F)
      if cp < 0x10000 || cp > 0x10FFFF {
        return None
      }
      cps.push(cp)
      i = i + 4
    } else {
      return None
    }
  }
  Some(cps)
}

///| Kanjiモードの文字数指示子ビット幅（ISO 18004 Table 3。jsQR decodeKanji の
///| `[8, 10, 12][size]` と同じ版数境界）。encode 側 Mode enum に Kanji が無いため
///| （自前エンコーダはKanji未対応）ここだけ独自に保持する。
fn kanji_cci_bits(version : Int) -> Int {
  if version <= 9 {
    8
  } else if version <= 26 {
    10
  } else {
    12
  }
}

///| decodeNumeric の移植。3桁→10bit、2桁→7bit、1桁→4bit のグループを読む。
///| 各グループの上限超過（999/99/9超）は不正構造として None。
fn decode_numeric(
  r : BitReader,
  version : Int,
  chars : Array[Char],
  bytes : Array[Int],
) -> Unit? {
  let width = @encode.cci_bits(@encode.Mode::Numeric, version)
  let mut length = match r.read_bits(width) {
    Some(v) => v
    None => return None
  }
  while length >= 3 {
    let num = match r.read_bits(10) {
      Some(v) => v
      None => return None
    }
    if num >= 1000 {
      return None
    }
    let a = num / 100
    let b = num / 10 % 10
    let c = num % 10
    bytes.push(48 + a)
    bytes.push(48 + b)
    bytes.push(48 + c)
    chars.push(Int::unsafe_to_char(48 + a))
    chars.push(Int::unsafe_to_char(48 + b))
    chars.push(Int::unsafe_to_char(48 + c))
    length = length - 3
  }
  if length == 2 {
    let num = match r.read_bits(7) {
      Some(v) => v
      None => return None
    }
    if num >= 100 {
      return None
    }
    let a = num / 10
    let b = num % 10
    bytes.push(48 + a)
    bytes.push(48 + b)
    chars.push(Int::unsafe_to_char(48 + a))
    chars.push(Int::unsafe_to_char(48 + b))
  } else if length == 1 {
    let num = match r.read_bits(4) {
      Some(v) => v
      None => return None
    }
    if num >= 10 {
      return None
    }
    bytes.push(48 + num)
    chars.push(Int::unsafe_to_char(48 + num))
  }
  Some(())
}

///| decodeAlphanumeric の移植。2文字ペア→11bit（45進数対）、末尾1文字→6bit。
fn decode_alphanumeric(
  r : BitReader,
  version : Int,
  chars : Array[Char],
  bytes : Array[Int],
) -> Unit? {
  let width = @encode.cci_bits(@encode.Mode::Alphanumeric, version)
  let mut length = match r.read_bits(width) {
    Some(v) => v
    None => return None
  }
  while length >= 2 {
    let v = match r.read_bits(11) {
      Some(v) => v
      None => return None
    }
    let a = v / 45
    let b = v % 45
    if a > 44 || b > 44 {
      return None // jsQR は配列外アクセスで例外（本ポートではNoneとして扱う）
    }
    bytes.push(alnum_char(a).to_int())
    bytes.push(alnum_char(b).to_int())
    chars.push(alnum_char(a))
    chars.push(alnum_char(b))
    length = length - 2
  }
  if length == 1 {
    let a = match r.read_bits(6) {
      Some(v) => v
      None => return None
    }
    if a > 44 {
      return None
    }
    bytes.push(alnum_char(a).to_int())
    chars.push(alnum_char(a))
  }
  Some(())
}

///| decodeByte の移植。8bit×length を生バイトとして読み、UTF-8として復号したテキストを
///| 連結する。UTF-8として不正な場合はjsQRのtry/catch同様、バイトは記録するがテキストへの
///| 寄与はゼロ（このセグメント分は何も追加しない。エラーにはしない）。
fn decode_byte(
  r : BitReader,
  version : Int,
  chars : Array[Char],
  bytes : Array[Int],
) -> Unit? {
  let width = @encode.cci_bits(@encode.Mode::Byte, version)
  let length = match r.read_bits(width) {
    Some(v) => v
    None => return None
  }
  let seg_bytes : Array[Int] = []
  for i = 0; i < length; i = i + 1 {
    let b = match r.read_bits(8) {
      Some(v) => v
      None => return None
    }
    seg_bytes.push(b)
    bytes.push(b)
  }
  match utf8_decode(seg_bytes) {
    Some(cps) =>
      for i = 0; i < cps.length(); i = i + 1 {
        chars.push(Int::unsafe_to_char(cps[i]))
      }
    None => () // 不正UTF-8: jsQRのcatchと同じくテキスト寄与なしで継続
  }
  Some(())
}

///| decodeKanji の移植。13bit値からSJIS 2バイトコードを再構成し、sjis_to_unicode で
///| Unicodeへ変換する。テーブルに存在しないコード（破損データ由来）は jsQR
///| （`String.fromCharCode(shiftJISTable[c])` で `shiftJISTable[c]` が undefined のとき
///| `String.fromCharCode(undefined)` は NUL文字 " " を返す）を忠実に鏡映し、
///| U+0000 を1文字として追加する（デコード自体は失敗させない）。
fn decode_kanji(
  r : BitReader,
  version : Int,
  chars : Array[Char],
  bytes : Array[Int],
) -> Unit? {
  let width = kanji_cci_bits(version)
  let length = match r.read_bits(width) {
    Some(v) => v
    None => return None
  }
  for i = 0; i < length; i = i + 1 {
    let k = match r.read_bits(13) {
      Some(v) => v
      None => return None
    }
    let mut c = ((k / 0xC0) << 8) | (k % 0xC0)
    c = if c < 0x1F00 { c + 0x8140 } else { c + 0xC140 }
    bytes.push(c >> 8)
    bytes.push(c & 0xFF)
    match sjis_to_unicode(c) {
      Some(cp) => chars.push(Int::unsafe_to_char(cp))
      None => chars.push(Int::unsafe_to_char(0))
    }
  }
  Some(())
}

///| ECI指示子の移植。1/2/3バイトdesignatorのビット構造だけをパースし、
///| assignmentNumberの値そのものは使わない（ファイル冒頭コメントの「ECI逸脱」参照）。
///| 破損designator（3個の継続フラグが全て1）はjsQRでも「corrupted」として
///| エラーにはならない＝この関数もSome(())を返す。
fn decode_eci(r : BitReader) -> Unit? {
  match r.read_bits(1) {
    None => None
    Some(0) =>
      match r.read_bits(7) {
        Some(_) => Some(())
        None => None
      }
    Some(_) =>
      match r.read_bits(1) {
        None => None
        Some(0) =>
          match r.read_bits(14) {
            Some(_) => Some(())
            None => None
          }
        Some(_) =>
          match r.read_bits(1) {
            None => None
            Some(0) =>
              match r.read_bits(21) {
                Some(_) => Some(())
                None => None
              }
            Some(_) => Some(()) // 破損designator。jsQRもエラーにはしない
          }
      }
  }
}

///| データコードワード列 → テキスト。ECI は UTF-8(26) のみ対応（他の ECI 指定は
///| 現れても byte を UTF-8 として解釈）。不正構造は None
pub fn decode_data(codewords : Array[Int], version : Int) -> DecodedData? {
  let r = BitReader::new(codewords)
  let chars : Array[Char] = []
  let bytes : Array[Int] = []
  while r.available() >= 4 {
    let mode = match r.read_bits(4) {
      Some(v) => v
      None => abort("unreachable: available() >= 4 guarantees 4 bits")
    }
    if mode == 0x0 {
      // Terminator
      return Some({ text: chars_to_string(chars), bytes })
    } else if mode == 0x7 {
      // ECI
      match decode_eci(r) {
        Some(_) => ()
        None => return None
      }
    } else if mode == 0x1 {
      // Numeric
      match decode_numeric(r, version, chars, bytes) {
        Some(_) => ()
        None => return None
      }
    } else if mode == 0x2 {
      // Alphanumeric
      match decode_alphanumeric(r, version, chars, bytes) {
        Some(_) => ()
        None => return None
      }
    } else if mode == 0x4 {
      // Byte
      match decode_byte(r, version, chars, bytes) {
        Some(_) => ()
        None => return None
      }
    } else if mode == 0x8 {
      // Kanji
      match decode_kanji(r, version, chars, bytes) {
        Some(_) => ()
        None => return None
      }
    }
    // それ以外（0x3, 0x5, 0x6, 0x9-0xF。StructuredAppendの0x3含む）は
    // jsQRに対応分岐が無いため、モード4bitの消費のみでペイロードを読まず継続する。
  }
  // ループを available() < 4 で抜けた（終端子に到達しないまま消費し切った）場合。
  // 残りが0bit、または残り全ビットが0なら暗黙の終端子とみなして成功（jsQRの
  // `stream.available() === 0 || stream.readBits(stream.available()) === 0` と同じ）。
  if r.available() == 0 {
    Some({ text: chars_to_string(chars), bytes })
  } else {
    match r.read_bits(r.available()) {
      Some(0) => Some({ text: chars_to_string(chars), bytes })
      _ => None
    }
  }
}
