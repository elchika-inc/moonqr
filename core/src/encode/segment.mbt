pub(all) enum Mode {
  Numeric
  Alphanumeric
  Byte
} derive(Eq, Show)

///| 英数字モードの文字集合における index。非対応は -1
fn alnum_index(c : Char) -> Int {
  let code = c.to_int()
  if code >= 48 && code <= 57 {
    code - 48 // 0-9
  } else if code >= 65 && code <= 90 {
    code - 65 + 10 // A-Z
  } else {
    match c {
      ' ' => 36
      '$' => 37
      '%' => 38
      '*' => 39
      '+' => 40
      '-' => 41
      '.' => 42
      '/' => 43
      ':' => 44
      _ => -1
    }
  }
}

pub fn detect_mode(text : String) -> Mode {
  let mut numeric = true
  let mut alnum = true
  for c in text {
    let code = c.to_int()
    if code < 48 || code > 57 {
      numeric = false
    }
    if alnum_index(c) < 0 {
      alnum = false
    }
  }
  if numeric {
    Mode::Numeric
  } else if alnum {
    Mode::Alphanumeric
  } else {
    Mode::Byte
  }
}

///| 文字数指示子のビット数（ISO 18004 Table 3）
pub fn cci_bits(mode : Mode, version : Int) -> Int {
  if version <= 9 {
    match mode {
      Mode::Numeric => 10
      Mode::Alphanumeric => 9
      Mode::Byte => 8
    }
  } else if version <= 26 {
    match mode {
      Mode::Numeric => 12
      Mode::Alphanumeric => 11
      Mode::Byte => 16
    }
  } else {
    match mode {
      Mode::Numeric => 14
      Mode::Alphanumeric => 13
      Mode::Byte => 16
    }
  }
}

pub fn utf8_encode(text : String) -> Array[Int] {
  let out : Array[Int] = []
  for c in text {
    let cp = c.to_int()
    if cp < 0x80 {
      out.push(cp)
    } else if cp < 0x800 {
      out.push(0xC0 | (cp >> 6))
      out.push(0x80 | (cp & 0x3F))
    } else if cp < 0x10000 {
      out.push(0xE0 | (cp >> 12))
      out.push(0x80 | ((cp >> 6) & 0x3F))
      out.push(0x80 | (cp & 0x3F))
    } else {
      out.push(0xF0 | (cp >> 18))
      out.push(0x80 | ((cp >> 12) & 0x3F))
      out.push(0x80 | ((cp >> 6) & 0x3F))
      out.push(0x80 | (cp & 0x3F))
    }
  }
  out
}

///| モード指示子＋文字数指示子＋データビットを書く
pub fn write_segment(
  w : BitWriter,
  text : String,
  mode : Mode,
  version : Int,
) -> Unit {
  match mode {
    Mode::Numeric => {
      w.write(0b0001, 4)
      let chars : Array[Char] = []
      for c in text {
        chars.push(c)
      }
      w.write(chars.length(), cci_bits(mode, version))
      let mut i = 0
      while i + 3 <= chars.length() {
        let v = (chars[i].to_int() - 48) * 100 +
          (chars[i + 1].to_int() - 48) * 10 + (chars[i + 2].to_int() - 48)
        w.write(v, 10)
        i = i + 3
      }
      let rest = chars.length() - i
      if rest == 2 {
        w.write((chars[i].to_int() - 48) * 10 + (chars[i + 1].to_int() - 48), 7)
      } else if rest == 1 {
        w.write(chars[i].to_int() - 48, 4)
      }
    }
    Mode::Alphanumeric => {
      w.write(0b0010, 4)
      let idx : Array[Int] = []
      for c in text {
        idx.push(alnum_index(c))
      }
      w.write(idx.length(), cci_bits(mode, version))
      let mut i = 0
      while i + 2 <= idx.length() {
        w.write(idx[i] * 45 + idx[i + 1], 11)
        i = i + 2
      }
      if i < idx.length() {
        w.write(idx[i], 6)
      }
    }
    Mode::Byte => {
      w.write(0b0100, 4)
      let bytes = utf8_encode(text)
      w.write(bytes.length(), cci_bits(mode, version))
      for i = 0; i < bytes.length(); i = i + 1 {
        w.write(bytes[i], 8)
      }
    }
  }
}
