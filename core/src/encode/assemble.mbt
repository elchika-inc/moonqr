///| 終端子(最大4bit)→8bit境界0詰め→0xEC/0x11交互パディング→
///| ブロック分割→RS→インターリーブ
pub fn assemble(bits : BitWriter, version : Int, ec : EcLevel) -> Array[Int]? {
  let cap_bits = data_capacity(version, ec) * 8
  if bits.bit_length() > cap_bits {
    return None
  }
  // 終端子: 残り容量と4bitの小さい方
  let term = if cap_bits - bits.bit_length() < 4 {
    cap_bits - bits.bit_length()
  } else {
    4
  }
  bits.write(0, term)
  let data = bits.to_codewords()
  let n_data = data_capacity(version, ec)
  let mut pad_toggle = true
  while data.length() < n_data {
    data.push(if pad_toggle { 0xEC } else { 0x11 })
    pad_toggle = !pad_toggle
  }
  // ブロック分割 + RS
  let blocks = rs_blocks(version, ec)
  let data_blocks : Array[Array[Int]] = []
  let ec_blocks : Array[Array[Int]] = []
  let mut offset = 0
  for i = 0; i < blocks.length(); i = i + 1 {
    let (total, dcount) = blocks[i]
    let d : Array[Int] = []
    for j = 0; j < dcount; j = j + 1 {
      d.push(data[offset + j])
    }
    offset = offset + dcount
    data_blocks.push(d)
    ec_blocks.push(@gf256.rs_encode(d, total - dcount))
  }
  // インターリーブ: 各ブロックの i 番目を順に
  let out : Array[Int] = []
  let mut max_d = 0
  for i = 0; i < data_blocks.length(); i = i + 1 {
    if data_blocks[i].length() > max_d {
      max_d = data_blocks[i].length()
    }
  }
  for i = 0; i < max_d; i = i + 1 {
    for b = 0; b < data_blocks.length(); b = b + 1 {
      if i < data_blocks[b].length() {
        out.push(data_blocks[b][i])
      }
    }
  }
  let mut max_e = 0
  for i = 0; i < ec_blocks.length(); i = i + 1 {
    if ec_blocks[i].length() > max_e {
      max_e = ec_blocks[i].length()
    }
  }
  for i = 0; i < max_e; i = i + 1 {
    for b = 0; b < ec_blocks.length(); b = b + 1 {
      if i < ec_blocks[b].length() {
        out.push(ec_blocks[b][i])
      }
    }
  }
  Some(out)
}
