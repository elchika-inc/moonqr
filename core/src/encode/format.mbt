///| BCH(15,5): 5bit情報 + 10bit誤り訂正、生成多項式 0x537、マスク 0x5412
pub fn format_bits(ec : EcLevel, mask : Int) -> Int {
  let ec_bits = match ec {
    EcLevel::L => 0b01
    EcLevel::M => 0b00
    EcLevel::Q => 0b11
    EcLevel::H => 0b10
  }
  let data = (ec_bits << 3) | mask
  let mut rem = data
  for i = 0; i < 10; i = i + 1 {
    rem = (rem << 1) ^ (if (rem >> 9) != 0 { 0x537 } else { 0 })
  }
  ((data << 10) | (rem & 0x3FF)) ^ 0x5412
}

///| BCH(18,6): 生成多項式 0x1F25
pub fn version_bits(version : Int) -> Int {
  let mut rem = version
  for i = 0; i < 12; i = i + 1 {
    rem = (rem << 1) ^ (if (rem >> 11) != 0 { 0x1F25 } else { 0 })
  }
  (version << 12) | (rem & 0xFFF)
}

///| フォーマット情報15bitを2系統の位置に書き込む（bit14 が先頭）
pub fn place_format(m : Matrix, ec : EcLevel, mask : Int) -> Unit {
  let bits = format_bits(ec, mask)
  let get_bit = fn(i : Int) -> Bool { ((bits >> i) & 1) == 1 }
  // 第1系統: 左上（タイミング行列 (6) を飛ばす標準配置）
  // bit 0..5 -> (8, 0..5), bit 6 -> (8,7), bit 7 -> (8,8), bit 8 -> (7,8),
  // bit 9..14 -> (5..0, 8)
  for i = 0; i <= 5; i = i + 1 {
    m.set_function(8, i, get_bit(i))
  }
  m.set_function(8, 7, get_bit(6))
  m.set_function(8, 8, get_bit(7))
  m.set_function(7, 8, get_bit(8))
  for i = 9; i <= 14; i = i + 1 {
    m.set_function(14 - i, 8, get_bit(i))
  }
  // 第2系統: bit 0..7 -> (size-1..size-8, 8), bit 8..14 -> (8, size-7..size-1)
  for i = 0; i <= 7; i = i + 1 {
    m.set_function(m.size - 1 - i, 8, get_bit(i))
  }
  for i = 8; i <= 14; i = i + 1 {
    m.set_function(8, m.size - 15 + i, get_bit(i))
  }
}

///| バージョン情報18bit（v7+）: 左下 3x6 と右上 6x3
pub fn place_version(m : Matrix, version : Int) -> Unit {
  if version < 7 {
    return
  }
  let bits = version_bits(version)
  for i = 0; i < 18; i = i + 1 {
    let bit = ((bits >> i) & 1) == 1
    let a = i / 3
    let b = i % 3
    m.set_function(a, m.size - 11 + b, bit) // 左下
    m.set_function(m.size - 11 + b, a, bit) // 右上
  }
}
