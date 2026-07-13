pub struct BitWriter {
  bits : Array[Bool]
}

pub fn BitWriter::new() -> BitWriter {
  { bits: [] }
}

///| value の下位 bits ビットを MSB から書き込む
pub fn BitWriter::write(self : BitWriter, value : Int, bits : Int) -> Unit {
  for i = bits - 1; i >= 0; i = i - 1 {
    self.bits.push(((value >> i) & 1) == 1)
  }
}

pub fn BitWriter::bit_length(self : BitWriter) -> Int {
  self.bits.length()
}

///| 8bit単位に詰める（端数は0詰め）
pub fn BitWriter::to_codewords(self : BitWriter) -> Array[Int] {
  let out : Array[Int] = []
  let mut cur = 0
  let mut n = 0
  for i = 0; i < self.bits.length(); i = i + 1 {
    cur = (cur << 1) | (if self.bits[i] { 1 } else { 0 })
    n = n + 1
    if n == 8 {
      out.push(cur)
      cur = 0
      n = 0
    }
  }
  if n > 0 {
    out.push(cur << (8 - n))
  }
  out
}
