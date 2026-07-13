///| GF(2^8), 既約多項式 x^8+x^4+x^3+x^2+1 = 0x11D（QRコード標準）

fn build_exp() -> FixedArray[Int] {
  let t = FixedArray::make(512, 0)
  let mut x = 1
  for i = 0; i < 255; i = i + 1 {
    t[i] = x
    x = x << 1
    if x >= 256 {
      x = x ^ 0x11D
    }
  }
  for i = 255; i < 512; i = i + 1 {
    t[i] = t[i - 255]
  }
  t
}

fn build_log() -> FixedArray[Int] {
  let t = FixedArray::make(256, 0)
  let mut x = 1
  for i = 0; i < 255; i = i + 1 {
    t[x] = i
    x = x << 1
    if x >= 256 {
      x = x ^ 0x11D
    }
  }
  t
}

let exp_table : FixedArray[Int] = build_exp()

let log_table : FixedArray[Int] = build_log()

///| 加算 = 減算 = XOR
pub fn add(a : Int, b : Int) -> Int {
  a ^ b
}

pub fn exp(i : Int) -> Int {
  exp_table[i % 255]
}

///| 前提: a != 0（a=0 は契約違反）
pub fn log(a : Int) -> Int {
  log_table[a]
}

pub fn mul(a : Int, b : Int) -> Int {
  if a == 0 || b == 0 {
    0
  } else {
    exp_table[log_table[a] + log_table[b]]
  }
}

///| 前提: b != 0
pub fn div(a : Int, b : Int) -> Int {
  if a == 0 {
    0
  } else {
    exp_table[(log_table[a] - log_table[b] + 255) % 255]
  }
}
