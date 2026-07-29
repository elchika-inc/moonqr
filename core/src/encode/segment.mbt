pub(all) enum Mode {
  Numeric
  Alphanumeric
  Byte
} derive(Eq, Debug)

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

///| その文字を表現できる最も制限的なモード。
///| 表現力の包含関係は Numeric ⊂ Alphanumeric ⊂ Byte。
pub fn char_mode(c : Char) -> Mode {
  let code = c.to_int()
  if code >= 48 && code <= 57 {
    Mode::Numeric
  } else if alnum_index(c) >= 0 {
    Mode::Alphanumeric
  } else {
    Mode::Byte
  }
}

///| 文字種のラン。start は文字単位のインデックス（UTF-8 バイト位置ではない）。
pub(all) struct Run {
  mode : Mode
  start : Int
  len : Int
} derive(Eq, Debug)

///| 連続する同じ char_mode の文字をまとめる。
pub fn runs_of(text : String) -> Array[Run] {
  let out : Array[Run] = []
  let mut idx = 0
  for c in text {
    let m = char_mode(c)
    if out.length() > 0 && out[out.length() - 1].mode == m {
      let last = out[out.length() - 1]
      out[out.length() - 1] = Run::{ mode: m, start: last.start, len: last.len + 1 }
    } else {
      out.push(Run::{ mode: m, start: idx, len: 1 })
    }
    idx = idx + 1
  }
  out
}

///| run_mode の文字を mode で表現できるか（Numeric ⊂ Alphanumeric ⊂ Byte）。
pub fn mode_can_encode(mode : Mode, run_mode : Mode) -> Bool {
  match mode {
    Mode::Byte => true
    Mode::Alphanumeric =>
      match run_mode {
        Mode::Byte => false
        _ => true
      }
    Mode::Numeric =>
      match run_mode {
        Mode::Numeric => true
        _ => false
      }
  }
}

///| chars[from..from+len) を mode で符号化したときの総ビット数。
///| モード指示子 4bit + 文字数指示子 + データ部。
///| 端数の扱いがモードごとに異なるため、1文字あたりへ均さずに計算する。
pub fn segment_bits(
  chars : Array[Char],
  from : Int,
  len : Int,
  mode : Mode,
  version : Int,
) -> Int {
  let header = 4 + cci_bits(mode, version)
  match mode {
    Mode::Numeric => {
      let full = len / 3
      let rest = len % 3
      let data = full * 10 + (if rest == 2 { 7 } else if rest == 1 { 4 } else { 0 })
      header + data
    }
    Mode::Alphanumeric => {
      let pairs = len / 2
      let rest = len % 2
      header + pairs * 11 + (if rest == 1 { 6 } else { 0 })
    }
    Mode::Byte => {
      // 文字数ではなく UTF-8 バイト数で数える
      let mut bytes = 0
      for i = from; i < from + len; i = i + 1 {
        let cp = chars[i].to_int()
        bytes = bytes +
          (if cp < 0x80 {
            1
          } else if cp < 0x800 {
            2
          } else if cp < 0x10000 {
            3
          } else {
            4
          })
      }
      header + bytes * 8
    }
  }
}

///| 最適分割の1区間。start / len は文字単位。
pub(all) struct Segment {
  mode : Mode
  start : Int
  len : Int
} derive(Eq, Debug)

///| 最小ビット数になる分割を返す。
///| ラン単位の DP。最適な分割境界は文字種が変わる位置にしか来ないため、
///| ランへ圧縮してから探索する（数字列の途中で切って両側とも Numeric に
///| するのは切替コストが増えるだけで常に損）。
pub fn optimal_segments(text : String, version : Int) -> Array[Segment] {
  let runs = runs_of(text)
  let n = runs.length()
  if n == 0 {
    return []
  }
  let chars : Array[Char] = []
  for c in text {
    chars.push(c)
  }
  let modes = [Mode::Numeric, Mode::Alphanumeric, Mode::Byte]
  // dp[j] = 先頭から j 個のランを符号化する最小ビット数（dp[0] = 0）
  let inf = 0x7FFFFFFF
  let dp = Array::make(n + 1, inf)
  dp[0] = 0
  // from_run[j] / from_mode[j] = dp[j] を達成する直前の状態
  let from_run = Array::make(n + 1, 0)
  let from_mode = Array::make(n + 1, Mode::Byte)
  for j = 1; j <= n; j = j + 1 {
    for i = 0; i < j; i = i + 1 {
      if dp[i] == inf {
        continue
      }
      // ラン i..j-1 をまとめて1セグメントにする
      let start = runs[i].start
      let mut len = 0
      for k = i; k < j; k = k + 1 {
        len = len + runs[k].len
      }
      for m in modes {
        // 区間内の全ランを表現できるモードだけが候補
        let mut ok = true
        for k = i; k < j; k = k + 1 {
          if !mode_can_encode(m, runs[k].mode) {
            ok = false
          }
        }
        if !ok {
          continue
        }
        let cost = dp[i] + segment_bits(chars, start, len, m, version)
        if cost < dp[j] {
          dp[j] = cost
          from_run[j] = i
          from_mode[j] = m
        }
      }
    }
  }
  // 復元
  let rev : Array[Segment] = []
  let mut j = n
  while j > 0 {
    let i = from_run[j]
    let start = runs[i].start
    let mut len = 0
    for k = i; k < j; k = k + 1 {
      len = len + runs[k].len
    }
    rev.push(Segment::{ mode: from_mode[j], start, len })
    j = i
  }
  let out : Array[Segment] = []
  for idx = rev.length() - 1; idx >= 0; idx = idx - 1 {
    out.push(rev[idx])
  }
  out
}

///| 最適分割に基づいて複数セグメントを書く。
///| デコーダ側は Phase 2 で複数セグメントの読み取りに対応済み。
pub fn write_segments(w : BitWriter, text : String, version : Int) -> Unit {
  let chars : Array[Char] = []
  for c in text {
    chars.push(c)
  }
  for s in optimal_segments(text, version) {
    // このコードベースは StringBuilder を使わず、文字列連結と補間で組み立てる
    // （svg.mbt の to_svg_string と同じ書き方）
    let mut part = ""
    for i = s.start; i < s.start + s.len; i = i + 1 {
      part = part + chars[i].to_string()
    }
    write_segment(w, part, s.mode, version)
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

///| モード指示子＋文字数指示子＋データビットを書く。
///| 契約: mode=Alphanumeric で呼ぶ場合、text の全文字が英数字モード文字集合
///| （0-9, A-Z, および space $ % * + - . / :）に属すること。呼び出し側は
///| detect_mode() 経由でこの前提を満たすこと。違反（範囲外文字）は abort。
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
        let i = alnum_index(c)
        // 契約: Alphanumeric モードで write_segment を呼ぶのは detect_mode が
        // 全文字を英数字と判定した場合のみ（内部呼び出しは常にこの前提を満たす）。
        // alnum_index が -1 を返す文字が来るのは呼び出し側の契約違反であり、
        // 誤ったビット列を無言で書き込むよりも早期に abort して検知する。
        if i < 0 {
          abort("write_segment: non-alphanumeric char in Alphanumeric mode (caller contract violation)")
        }
        idx.push(i)
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
