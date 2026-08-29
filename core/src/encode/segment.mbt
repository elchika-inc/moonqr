pub(all) enum Mode {
  Numeric
  Alphanumeric
  Byte
} derive(Eq, Debug)

///| QR Model 2 の絶対最大容量（version 40-L Numeric の 7,089文字）を、
///| String::length() が返すUTF-16コードユニット数で保守的に判定する。
///| 非BMP文字は2コードユニットとして数えるため、そのような入力では
///| 実際の容量上限より早く弾かれることがある。
fn input_within_model2_capacity(text : String) -> Bool {
  text.length() <= 7089
}

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
fn char_mode(c : Char) -> Mode {
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
struct Run {
  mode : Mode
  start : Int
  len : Int
} derive(Eq, Debug)

///| 連続する同じ char_mode の文字をまとめる。
fn runs_of(text : String) -> Array[Run] {
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

///| 最適分割の1区間。start / len は文字単位。
struct Segment {
  mode : Mode
  start : Int
  len : Int
} derive(Eq, Debug)

///| 旧 DP の探索順（開始 run 昇順、Numeric → Alphanumeric → Byte）を
///| コストが同じ候補同士の優先順位として表す。
fn segment_candidate_is_better(
  cost : Int,
  from_run : Int,
  mode : Mode,
  best_cost : Int,
  best_from_run : Int,
  best_mode : Mode,
) -> Bool {
  if cost != best_cost {
    cost < best_cost
  } else if from_run != best_from_run {
    from_run < best_from_run
  } else {
    let priority = match mode {
      Mode::Numeric => 0
      Mode::Alphanumeric => 1
      Mode::Byte => 2
    }
    let best_priority = match best_mode {
      Mode::Numeric => 0
      Mode::Alphanumeric => 1
      Mode::Byte => 2
    }
    priority < best_priority
  }
}

///| 最小ビット数になる分割を返す。
///| ラン単位の DP。最適な分割境界は文字種が変わる位置にしか来ないため、
///| ランへ圧縮してから探索する（数字列の途中で切って両側とも Numeric に
///| するのは切替コストが増えるだけで常に損）。
fn optimal_segments(text : String, version : Int) -> Array[Segment]? {
  if !input_within_model2_capacity(text) {
    return None
  }
  let runs = runs_of(text)
  let n = runs.length()
  if n == 0 {
    return None
  }
  let byte_prefix : Array[Int] = [0]
  for c in text {
    let cp = c.to_int()
    let byte_len = if cp < 0x80 {
      1
    } else if cp < 0x800 {
      2
    } else if cp < 0x10000 {
      3
    } else {
      4
    }
    byte_prefix.push(byte_prefix[byte_prefix.length() - 1] + byte_len)
  }
  let charpos : Array[Int] = []
  let bytepos : Array[Int] = []
  for r in runs {
    charpos.push(r.start)
    bytepos.push(byte_prefix[r.start])
  }
  let text_len = runs[n - 1].start + runs[n - 1].len
  charpos.push(text_len)
  bytepos.push(byte_prefix[text_len])
  // dp6[j] = 先頭から j 個のランを符号化する最小ビット数の6倍（dp6[0] = 0）
  let inf = 0x7FFFFFFF
  let dp6 = Array::make(n + 1, inf)
  dp6[0] = 0
  // from_run[j] / from_mode[j] = dp6[j] を達成する直前の状態
  let from_run = Array::make(n + 1, 0)
  let from_mode = Array::make(n + 1, Mode::Byte)
  // Byte は任意の run 区間を覆えるため、開始点 i の変換済みコストの最小値を持つ。
  let mut best_byte = inf
  let mut best_byte_i = 0
  // Alphanumeric は Byte run を跨げず、データ部の端数は開始文字位置の偶奇で決まる。
  let best_alnum = Array::make(2, inf)
  let best_alnum_i = Array::make(2, 0)
  for j = 1; j <= n; j = j + 1 {
    let i = j - 1
    if dp6[i] != inf {
      let byte_cand = dp6[i] - 48 * bytepos[i]
      if byte_cand < best_byte {
        best_byte = byte_cand
        best_byte_i = i
      }
      if runs[i].mode == Mode::Byte {
        best_alnum[0] = inf
        best_alnum[1] = inf
      } else {
        let parity = charpos[i] % 2
        let alnum_cand = dp6[i] - 33 * charpos[i]
        if alnum_cand < best_alnum[parity] {
          best_alnum[parity] = alnum_cand
          best_alnum_i[parity] = i
        }
      }
    }

    if best_byte != inf {
      let cost = 6 * (4 + cci_bits(Mode::Byte, version)) +
        48 * bytepos[j] + best_byte
      if segment_candidate_is_better(
        cost,
        best_byte_i,
        Mode::Byte,
        dp6[j],
        from_run[j],
        from_mode[j],
      ) {
        dp6[j] = cost
        from_run[j] = best_byte_i
        from_mode[j] = Mode::Byte
      }
    }

    for parity = 0; parity < 2; parity = parity + 1 {
      if best_alnum[parity] != inf {
        let remainder = (charpos[j] - parity) % 2
        let cost = 6 * (4 + cci_bits(Mode::Alphanumeric, version)) +
          33 * charpos[j] + 3 * remainder + best_alnum[parity]
        if segment_candidate_is_better(
          cost,
          best_alnum_i[parity],
          Mode::Alphanumeric,
          dp6[j],
          from_run[j],
          from_mode[j],
        ) {
          dp6[j] = cost
          from_run[j] = best_alnum_i[parity]
          from_mode[j] = Mode::Alphanumeric
        }
      }
    }

    if runs[i].mode == Mode::Numeric && dp6[i] != inf {
      let len = runs[i].len
      let remainder = len % 3
      let c3 = if remainder == 1 { 2 } else if remainder == 2 { 1 } else { 0 }
      let cost = dp6[i] + 6 * (4 + cci_bits(Mode::Numeric, version)) +
        20 * len + 2 * c3
      if segment_candidate_is_better(
        cost,
        i,
        Mode::Numeric,
        dp6[j],
        from_run[j],
        from_mode[j],
      ) {
        dp6[j] = cost
        from_run[j] = i
        from_mode[j] = Mode::Numeric
      }
    }
  }
  // 復元
  let rev : Array[Segment] = []
  let mut j = n
  while j > 0 {
    let i = from_run[j]
    rev.push(
      Segment::{ mode: from_mode[j], start: charpos[i], len: charpos[j] - charpos[i] },
    )
    j = i
  }
  let out : Array[Segment] = []
  for idx = rev.length() - 1; idx >= 0; idx = idx - 1 {
    out.push(rev[idx])
  }
  Some(out)
}

///| 最適分割に基づいて複数セグメントを書く。
///| デコーダ側は Phase 2 で複数セグメントの読み取りに対応済み。
fn write_segment_list(
  w : BitWriter,
  text : String,
  version : Int,
  segments : Array[Segment],
) -> Unit {
  let chars : Array[Char] = []
  for c in text {
    chars.push(c)
  }
  for s in segments {
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
