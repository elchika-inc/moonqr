///| 終端子(最大4bit)→8bit境界0詰め→0xEC/0x11交互パディング→
///| ブロック分割→RS→インターリーブ
pub fn assemble(bits : BitWriter, version : Int, ec : EcLevel) -> Array[Int]? {
  let data_codeword_count = data_capacity(version, ec)
  if bits.bit_length() > data_codeword_count * 8 {
    return None
  }
  let data_codewords = pad_data_codewords(bits, data_codeword_count)
  let (data_blocks, ec_blocks) = build_codeword_blocks(data_codewords, version, ec)
  let codewords : Array[Int] = []
  append_interleaved_codewords(data_blocks, codewords)
  append_interleaved_codewords(ec_blocks, codewords)
  Some(codewords)
}

fn pad_data_codewords(bits : BitWriter, data_codeword_count : Int) -> Array[Int] {
  let capacity_bits = data_codeword_count * 8
  // 終端子: 残り容量と4bitの小さい方
  let terminator_bits = if capacity_bits - bits.bit_length() < 4 {
    capacity_bits - bits.bit_length()
  } else {
    4
  }
  bits.write(0, terminator_bits)
  let data_codewords = bits.to_codewords()
  let mut use_ec_pad = true
  while data_codewords.length() < data_codeword_count {
    data_codewords.push(if use_ec_pad { 0xEC } else { 0x11 })
    use_ec_pad = !use_ec_pad
  }
  data_codewords
}

fn build_codeword_blocks(
  data_codewords : Array[Int],
  version : Int,
  ec : EcLevel,
) -> (Array[Array[Int]], Array[Array[Int]]) {
  let block_sizes = rs_blocks(version, ec)
  let data_blocks : Array[Array[Int]] = []
  let ec_blocks : Array[Array[Int]] = []
  let mut offset = 0
  for i = 0; i < block_sizes.length(); i = i + 1 {
    let (total_count, data_count) = block_sizes[i]
    let block_data : Array[Int] = []
    for j = 0; j < data_count; j = j + 1 {
      block_data.push(data_codewords[offset + j])
    }
    offset = offset + data_count
    data_blocks.push(block_data)
    ec_blocks.push(@gf256.rs_encode(block_data, total_count - data_count))
  }
  (data_blocks, ec_blocks)
}

fn append_interleaved_codewords(
  blocks : Array[Array[Int]],
  codewords : Array[Int],
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
        codewords.push(blocks[b][i])
      }
    }
  }
}
