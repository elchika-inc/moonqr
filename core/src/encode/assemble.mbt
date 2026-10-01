///| 終端子(最大4bit)→8bit境界0詰め→0xEC/0x11交互パディング→
///| ブロック分割→RS→インターリーブ
pub fn assemble(bits : BitWriter, version : Int, ec : EcLevel) -> Array[Int]? {
  let n_data = data_capacity(version, ec)
  if bits.bit_length() > n_data * 8 {
    return None
  }
  let data = pad_data_codewords(bits, n_data)
  let (data_blocks, ec_blocks) = build_codeword_blocks(data, version, ec)
  let out : Array[Int] = []
  append_interleaved_codewords(data_blocks, out)
  append_interleaved_codewords(ec_blocks, out)
  Some(out)
}

fn pad_data_codewords(bits : BitWriter, n_data : Int) -> Array[Int] {
  let cap_bits = n_data * 8
  // 終端子: 残り容量と4bitの小さい方
  let term = if cap_bits - bits.bit_length() < 4 {
    cap_bits - bits.bit_length()
  } else {
    4
  }
  bits.write(0, term)
  let data = bits.to_codewords()
  let mut pad_toggle = true
  while data.length() < n_data {
    data.push(if pad_toggle { 0xEC } else { 0x11 })
    pad_toggle = !pad_toggle
  }
  data
}

fn build_codeword_blocks(
  data : Array[Int],
  version : Int,
  ec : EcLevel,
) -> (Array[Array[Int]], Array[Array[Int]]) {
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
  (data_blocks, ec_blocks)
}

fn append_interleaved_codewords(
  blocks : Array[Array[Int]],
  out : Array[Int],
) -> Unit {
  let mut max_length = 0
  for i = 0; i < blocks.length(); i = i + 1 {
    if blocks[i].length() > max_length {
      max_length = blocks[i].length()
    }
  }
  for i = 0; i < max_length; i = i + 1 {
    for b = 0; b < blocks.length(); b = b + 1 {
      if i < blocks[b].length() {
        out.push(blocks[b][i])
      }
    }
  }
}
