///| 移植元: 独自実装（encode の `place_data` の逆操作＋`rs_blocks`によるデインターリーブ
///| ＋`@gf256.rs_decode`）。jsQR `decoder.ts` の `readCodewords`/`dataBlocks` は突合参照のみ
///| （移植元ではない）。
///|
///| 落とし穴: どのモジュールが機能パターン領域かは BitMatrix 単体では判別できない。
///| encode 側の `@encode.Matrix::new` + `place_function_patterns` + `place_version` を
///| そのまま「機能領域マップ」として使い回すことで、encode/decode 間の規則ドリフトを
///| 構造的に防ぐ（このファイルで機能領域の判定ロジックを再実装しない）。

///| `@encode.place_data` と全く同じ走査順（右から左へ2列単位、col 6 スキップ、
///| 上下交互のジグザグ）で非機能セルのビットを読み出す。マスクは各セルで
///| XOR して解除する。total_bits に達したら読み取りを止める（place_data 側が
///| 書き込みを止めるのと対称）。
fn read_bits_zigzag(
  m : BitMatrix,
  fm : @encode.Matrix,
  mask : Int,
  total_bits : Int,
) -> Array[Bool] {
  let size = m.width
  let bits : Array[Bool] = []
  let mut col = size - 1
  let mut upward = true
  while col > 0 {
    if col == 6 {
      col = col - 1 // タイミング列をスキップ
    }
    for step = 0; step < size; step = step + 1 {
      let y = if upward { size - 1 - step } else { step }
      for dx = 0; dx < 2; dx = dx + 1 {
        let x = col - dx
        if !fm.is_function(x, y) && bits.length() < total_bits {
          let raw = m.get(x, y)
          let bit = raw != @encode.mask_bit(mask, x, y) // Bool XOR
          bits.push(bit)
        }
      }
    }
    upward = !upward
    col = col - 2
  }
  bits
}

///| 8bitずつMSB-firstでコードワードへ詰める（bits.length() は8の倍数前提）。
fn bits_to_codewords(bits : Array[Bool]) -> Array[Int] {
  let out : Array[Int] = []
  let mut i = 0
  while i < bits.length() {
    let mut cw = 0
    for k = 0; k < 8; k = k + 1 {
      cw = (cw << 1) | (if bits[i + k] { 1 } else { 0 })
    }
    out.push(cw)
    i = i + 8
  }
  out
}

///| マスク解除→ジグザグ読出→デインターリーブ→ブロック毎RS訂正→データコードワード列。
///| 訂正不能ブロックがあれば None
pub fn read_data(m : BitMatrix, version : Int, fmt : FormatInfo) -> Array[Int]? {
  // 機能領域マップ（encode 側の規則をそのまま再利用）
  let fm = @encode.Matrix::new(version)
  @encode.place_function_patterns(fm, version)
  @encode.place_version(fm, version)
  let blocks = @encode.rs_blocks(version, fmt.ec)
  let mut total_codewords = 0
  for i = 0; i < blocks.length(); i = i + 1 {
    let (total, _dcount) = blocks[i]
    total_codewords = total_codewords + total
  }
  let bits = read_bits_zigzag(m, fm, fmt.mask, total_codewords * 8)
  let codewords = bits_to_codewords(bits)

  // デインターリーブ: assemble の「各ブロックのi番目を順に」を逆再生する
  let data_blocks : Array[Array[Int]] = []
  let ec_blocks : Array[Array[Int]] = []
  let mut max_d = 0
  let mut max_e = 0
  for i = 0; i < blocks.length(); i = i + 1 {
    let (total, dcount) = blocks[i]
    let ecount = total - dcount
    data_blocks.push(Array::make(dcount, 0))
    ec_blocks.push(Array::make(ecount, 0))
    if dcount > max_d {
      max_d = dcount
    }
    if ecount > max_e {
      max_e = ecount
    }
  }
  let mut idx = 0
  for i = 0; i < max_d; i = i + 1 {
    for b = 0; b < blocks.length(); b = b + 1 {
      let (_total, dcount) = blocks[b]
      if i < dcount {
        data_blocks[b][i] = codewords[idx]
        idx = idx + 1
      }
    }
  }
  for i = 0; i < max_e; i = i + 1 {
    for b = 0; b < blocks.length(); b = b + 1 {
      let (total, dcount) = blocks[b]
      let ecount = total - dcount
      if i < ecount {
        ec_blocks[b][i] = codewords[idx]
        idx = idx + 1
      }
    }
  }

  // ブロック毎RS訂正
  let out : Array[Int] = []
  for b = 0; b < blocks.length(); b = b + 1 {
    let (_total, dcount) = blocks[b]
    let ecount = ec_blocks[b].length()
    let msg : Array[Int] = []
    for i = 0; i < dcount; i = i + 1 {
      msg.push(data_blocks[b][i])
    }
    for i = 0; i < ecount; i = i + 1 {
      msg.push(ec_blocks[b][i])
    }
    match @gf256.rs_decode(msg, ecount) {
      None => return None
      Some(fixed) =>
        for i = 0; i < dcount; i = i + 1 {
          out.push(fixed[i])
        }
    }
  }
  Some(out)
}
