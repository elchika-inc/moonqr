///| 移植元: jsQR (Apache-2.0), commit 8e6a036beafa7053dd44b1b76ac578d22b1b3311
///| https://github.com/cozmo/jsQR/blob/8e6a036beafa7053dd44b1b76ac578d22b1b3311/src/decoder/decoder.ts
///| `readFormatInformation`/`readVersion` のアルゴリズム（各候補 C に対し
///| min(dist(bits1, C), dist(bits2, C)) を単一ループで追跡し、全体最小が
///| <=3 のときだけ採用する両系統同時最小距離方式）を移植する。
///| 両系統が「別々の」符号語の近傍にある非対称な破損でも、客観的に
///| 距離が近い方が勝つ（2コピー冗長の存在意義そのもの）。
///| ただし jsQR の「有効コード表（FORMAT_INFO_TABLE 等）」は移植せず、
///| encode パッケージの `format_bits(ec, mask)` / `version_bits(v)`
///| （qrcode npm と一致実証済み・真値表）を候補列挙に使う。

///| フォーマット情報の復号結果（誤り訂正済みEC水準とマスクパターン）。
pub struct FormatInfo {
  ec : @encode.EcLevel
  mask : Int
} derive(Eq, Show)

///| 全EC水準の列挙（インデックス順に依存しない固定順）。
fn all_ec_levels() -> Array[@encode.EcLevel] {
  [@encode.EcLevel::L, @encode.EcLevel::M, @encode.EcLevel::Q, @encode.EcLevel::H]
}

///| ハミング距離（XOR + popcount ループ）。
fn hamming_distance(a : Int, b : Int) -> Int {
  let mut x = a ^ b
  let mut d = 0
  while x != 0 {
    d = d + (x & 1)
    x = x >> 1
  }
  d
}

///| 15bit 生読取値（2系統それぞれ）から最尤フォーマットを返す。
///| jsQR readFormatInformation と同じく、全32候補 (ec x mask) を単一ループで
///| 走査し、各候補 C に対し min(dist(bits1, C), dist(bits2, C)) を評価して
///| 全体最小の候補を追跡する。最小距離が <=3 のときだけ採用、それ以外は None。
pub fn decode_format(bits1 : Int, bits2 : Int) -> FormatInfo? {
  let ecs = all_ec_levels()
  let mut best_dist = 16 // 15bitの最大距離(15)より大きい番兵
  let mut best = FormatInfo::{ ec: @encode.EcLevel::L, mask: 0 }
  for ei = 0; ei < ecs.length(); ei = ei + 1 {
    for mask = 0; mask < 8; mask = mask + 1 {
      let ec = ecs[ei]
      let candidate = @encode.format_bits(ec, mask)
      let d1 = hamming_distance(bits1, candidate)
      let d2 = hamming_distance(bits2, candidate)
      let d = if d1 < d2 { d1 } else { d2 }
      if d < best_dist {
        best_dist = d
        best = FormatInfo::{ ec, mask }
      }
    }
  }
  if best_dist <= 3 {
    Some(best)
  } else {
    None
  }
}

///| 18bit 生読取値から最尤バージョン(7..40)を返す。
///| jsQR readVersion と同じく、v7..40 の全34候補を単一ループで走査し、
///| 各候補 C に対し min(dist(bits1, C), dist(bits2, C)) を評価して全体最小の
///| 候補を追跡する。最小距離が <=3 のときだけ採用、それ以外は None。
pub fn decode_version(bits1 : Int, bits2 : Int) -> Int? {
  let mut best_dist = 19 // 18bitの最大距離(18)より大きい番兵
  let mut best_version = 7
  for v = 7; v <= 40; v = v + 1 {
    let candidate = @encode.version_bits(v)
    let d1 = hamming_distance(bits1, candidate)
    let d2 = hamming_distance(bits2, candidate)
    let d = if d1 < d2 { d1 } else { d2 }
    if d < best_dist {
      best_dist = d
      best_version = v
    }
  }
  if best_dist <= 3 {
    Some(best_version)
  } else {
    None
  }
}

///| フォーマット情報15bitを行列から読み出す（座標は encode `place_format`
///| と鏡映。get_bit(0) が LSB で先頭セル (8,0) に対応）。
///| copy1: 左上系統（第1系統）、copy2: 右上/左下系統（第2系統）。
pub fn read_format_bits(m : BitMatrix) -> (Int, Int) {
  let size = m.width
  let bit = fn(v : Bool) -> Int { if v { 1 } else { 0 } }
  // 系統1: bit 0..5 -> (8, 0..5), bit 6 -> (8,7), bit 7 -> (8,8),
  // bit 8 -> (7,8), bit 9..14 -> (14-i, 8)
  let mut copy1 = 0
  for i = 0; i <= 5; i = i + 1 {
    copy1 = copy1 | (bit(m.get(8, i)) << i)
  }
  copy1 = copy1 | (bit(m.get(8, 7)) << 6)
  copy1 = copy1 | (bit(m.get(8, 8)) << 7)
  copy1 = copy1 | (bit(m.get(7, 8)) << 8)
  for i = 9; i <= 14; i = i + 1 {
    copy1 = copy1 | (bit(m.get(14 - i, 8)) << i)
  }
  // 系統2: bit 0..7 -> (size-1-i, 8), bit 8..14 -> (8, size-15+i)
  let mut copy2 = 0
  for i = 0; i <= 7; i = i + 1 {
    copy2 = copy2 | (bit(m.get(size - 1 - i, 8)) << i)
  }
  for i = 8; i <= 14; i = i + 1 {
    copy2 = copy2 | (bit(m.get(8, size - 15 + i)) << i)
  }
  (copy1, copy2)
}

///| バージョン情報18bitを行列から読み出す（座標は encode `place_version`
///| と鏡映）。bit i -> (i/3, size-11+i%3)（左下）と (size-11+i%3, i/3)（右上）。
pub fn read_version_bits(m : BitMatrix) -> (Int, Int) {
  let size = m.width
  let bit = fn(v : Bool) -> Int { if v { 1 } else { 0 } }
  let mut bottom_left = 0
  let mut top_right = 0
  for i = 0; i < 18; i = i + 1 {
    let a = i / 3
    let b = i % 3
    bottom_left = bottom_left | (bit(m.get(a, size - 11 + b)) << i)
    top_right = top_right | (bit(m.get(size - 11 + b, a)) << i)
  }
  (bottom_left, top_right)
}
