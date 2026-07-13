///| 多項式は Array[Int]、index 0 が最高次係数

pub fn poly_mul(a : Array[Int], b : Array[Int]) -> Array[Int] {
  let out = Array::make(a.length() + b.length() - 1, 0)
  for i = 0; i < a.length(); i = i + 1 {
    for j = 0; j < b.length(); j = j + 1 {
      out[i + j] = add(out[i + j], mul(a[i], b[j]))
    }
  }
  out
}

///| RS生成多項式 g(x) = Π_{i=0}^{n-1} (x - α^i)
pub fn rs_generator(n : Int) -> Array[Int] {
  let mut g = [1]
  for i = 0; i < n; i = i + 1 {
    g = poly_mul(g, [1, exp(i)])
  }
  g
}

///| data * x^n_ec を g(x) で割った剰余 = ECコードワード
pub fn rs_encode(data : Array[Int], n_ec : Int) -> Array[Int] {
  let g = rs_generator(n_ec)
  let rem = Array::make(data.length() + n_ec, 0)
  for i = 0; i < data.length(); i = i + 1 {
    rem[i] = data[i]
  }
  for i = 0; i < data.length(); i = i + 1 {
    let factor = rem[i]
    if factor != 0 {
      for j = 1; j < g.length(); j = j + 1 {
        rem[i + j] = add(rem[i + j], mul(g[j], factor))
      }
    }
    rem[i] = 0
  }
  let ec = Array::make(n_ec, 0)
  for i = 0; i < n_ec; i = i + 1 {
    ec[i] = rem[data.length() + i]
  }
  ec
}
