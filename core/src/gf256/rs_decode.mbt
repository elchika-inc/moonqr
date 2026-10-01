///| シンドローム S_i = msg(α^i), i = 0..n_ec-1
fn calc_syndromes(msg : Array[Int], n_ec : Int) -> Array[Int] {
  let synd = Array::make(n_ec, 0)
  for i = 0; i < n_ec; i = i + 1 {
    let x = exp(i)
    let mut acc = 0
    for j = 0; j < msg.length(); j = j + 1 {
      acc = add(mul(acc, x), msg[j])
    }
    synd[i] = acc
  }
  synd
}

///| Berlekamp-Massey: エラーロケータ多項式 σ(x)（index 0 = 最高次。定数項 1 は末尾要素）
fn find_error_locator(synd : Array[Int]) -> Array[Int]? {
  let mut err_loc = [1]
  let mut old_loc = [1]
  for i = 0; i < synd.length(); i = i + 1 {
    old_loc.push(0)
    let mut delta = synd[i]
    for j = 1; j < err_loc.length(); j = j + 1 {
      delta = add(delta, mul(err_loc[err_loc.length() - 1 - j], synd[i - j]))
    }
    if delta != 0 {
      if old_loc.length() > err_loc.length() {
        let new_loc = scale_poly(old_loc, delta)
        old_loc = scale_poly(err_loc, div(1, delta))
        err_loc = new_loc
      }
      err_loc = poly_add_padded(err_loc, scale_poly(old_loc, delta))
    }
  }
  // 先頭の0を除去
  let mut lead = 0
  while lead < err_loc.length() - 1 && err_loc[lead] == 0 {
    lead = lead + 1
  }
  let trimmed : Array[Int] = []
  for i = lead; i < err_loc.length(); i = i + 1 {
    trimmed.push(err_loc[i])
  }
  let n_errors = trimmed.length() - 1
  if n_errors * 2 > synd.length() {
    None
  } else {
    Some(trimmed)
  }
}

fn scale_poly(p : Array[Int], k : Int) -> Array[Int] {
  let out : Array[Int] = []
  for i = 0; i < p.length(); i = i + 1 {
    out.push(mul(p[i], k))
  }
  out
}

///| 右詰めで加算（次数を揃えて XOR）
fn poly_add_padded(a : Array[Int], b : Array[Int]) -> Array[Int] {
  let n = if a.length() > b.length() { a.length() } else { b.length() }
  let out = Array::make(n, 0)
  for i = 0; i < a.length(); i = i + 1 {
    out[n - a.length() + i] = a[i]
  }
  for i = 0; i < b.length(); i = i + 1 {
    let idx = n - b.length() + i
    out[idx] = add(out[idx], b[i])
  }
  out
}

///| Chien search: σ(X_k^{-1}) = 0 となる位置 pos を列挙。
///| エラーロケータ σ(x) = Π(1 - X_k x) の根は X_k の逆数であり、
///| 配列位置 pos の誤りは X_pos = α^{msg_len-1-pos} に対応するため、
///| σ を評価すべき点は X_pos の逆数 = α^{-(msg_len-1-pos)}。
fn find_error_positions(err_loc : Array[Int], msg_len : Int) -> Array[Int]? {
  let n_errors = err_loc.length() - 1
  let positions : Array[Int] = []
  for pos = 0; pos < msg_len; pos = pos + 1 {
    let loc_exp = msg_len - 1 - pos // X_pos = α^{loc_exp}
    let inv_exp = ((-loc_exp) % 255 + 255) % 255 // X_pos^{-1} = α^{inv_exp}
    let x = exp(inv_exp)
    let mut acc = 0
    for j = 0; j < err_loc.length(); j = j + 1 {
      acc = add(mul(acc, x), err_loc[j])
    }
    if acc == 0 {
      positions.push(pos)
    }
  }
  if positions.length() != n_errors {
    None
  } else {
    Some(positions)
  }
}

///| Forney: エラー値を計算し訂正
fn correct_errors(
  msg : Array[Int],
  synd : Array[Int],
  err_loc : Array[Int],
  positions : Array[Int],
) -> Array[Int]? {
  let omega = compute_error_evaluator(synd, err_loc)
  let locator_derivative = differentiate_error_locator(err_loc)
  let corrected = msg.copy()
  for k = 0; k < positions.length(); k = k + 1 {
    let pos = positions[k]
    let position_exponent = msg.length() - 1 - pos // α^{i}, i = 末尾からの冪
    let x = exp(position_exponent)
    let x_inv = div(1, x)
    let evaluator_value = evaluate_polynomial(omega, x_inv)
    let derivative_value = evaluate_polynomial(locator_derivative, x_inv)
    if derivative_value == 0 {
      return None
    }
    let magnitude = mul(x, div(evaluator_value, derivative_value))
    corrected[pos] = add(corrected[pos], magnitude)
  }
  Some(corrected)
}

fn compute_error_evaluator(
  synd : Array[Int],
  err_loc : Array[Int],
) -> Array[Int] {
  // エラーエバリュエータ Ω(x) = [S(x)·σ(x)] mod x^n_ec
  // S(x) は S_0 を最低次とする（index 0 = 最高次表現に変換して poly_mul）
  let synd_rev : Array[Int] = []
  for i = synd.length() - 1; i >= 0; i = i - 1 {
    synd_rev.push(synd[i])
  }
  let omega_full = poly_mul(synd_rev, err_loc)
  // mod x^n_ec: 低次側 n_ec 個を残す（配列は先頭=最高次なので末尾 n_ec 個）
  let omega : Array[Int] = []
  let start = omega_full.length() - synd.length()
  for i = start; i < omega_full.length(); i = i + 1 {
    omega.push(omega_full[i])
  }
  omega
}

fn differentiate_error_locator(err_loc : Array[Int]) -> Array[Int] {
  // σ'(x): 形式微分（GF(2^8)では偶数次の項が消える）
  let derivative : Array[Int] = []
  let degree = err_loc.length() - 1
  for i = 0; i < err_loc.length() - 1; i = i + 1 {
    let power = degree - i // この係数の次数
    if power % 2 == 1 {
      derivative.push(err_loc[i])
    } else {
      derivative.push(0)
    }
  }
  derivative
}

///| 係数は先頭が最高次。Horner 法で評価する。
fn evaluate_polynomial(coefficients : Array[Int], x : Int) -> Int {
  let mut value = 0
  for j = 0; j < coefficients.length(); j = j + 1 {
    value = add(mul(value, x), coefficients[j])
  }
  value
}

///| RS復号: 訂正済み符号語を返す。訂正不能は None。
///| 訂正不要時は入力配列そのものを返し、訂正時は入力を変更せず新しい配列を返す。
pub fn rs_decode(msg : Array[Int], n_ec : Int) -> Array[Int]? {
  let synd = calc_syndromes(msg, n_ec)
  if synd.all(x => x == 0) {
    return Some(msg)
  }
  guard find_error_locator(synd) is Some(err_loc) else { return None }
  guard find_error_positions(err_loc, msg.length()) is Some(positions) else {
    return None
  }
  guard correct_errors(msg, synd, err_loc, positions) is Some(fixed) else {
    return None
  }
  // 検証ゲート: 訂正後のシンドロームが全0でなければ失敗扱い
  let synd2 = calc_syndromes(fixed, n_ec)
  if synd2.all(x => x == 0) {
    Some(fixed)
  } else {
    None
  }
}
