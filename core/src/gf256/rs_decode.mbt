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

///| Berlekamp-Massey: エラーロケータ多項式 σ(x)（index 0 = 定数項 1）
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
  // σ'(x): 形式微分（GF(2^8)では偶数次の項が消える）
  let deriv : Array[Int] = []
  let deg = err_loc.length() - 1
  for i = 0; i < err_loc.length() - 1; i = i + 1 {
    let power = deg - i // この係数の次数
    if power % 2 == 1 {
      deriv.push(err_loc[i])
    } else {
      deriv.push(0)
    }
  }
  // deriv は x で1次下げた多項式として評価する（下の eval で x^2 刻みに対応）
  let out = msg.copy()
  for k = 0; k < positions.length(); k = k + 1 {
    let pos = positions[k]
    let x_inv_log = msg.length() - 1 - pos // α^{i}, i = 末尾からの冪
    let x = exp(x_inv_log)
    let x_inv = div(1, x)
    // Ω(x^{-1})
    let mut om = 0
    for j = 0; j < omega.length(); j = j + 1 {
      om = add(mul(om, x_inv), omega[j])
    }
    // σ'(x^{-1}) を直接評価（deriv の各項は元の次数-1）
    let mut dv = 0
    for j = 0; j < deriv.length(); j = j + 1 {
      dv = add(mul(dv, x_inv), deriv[j])
    }
    if dv == 0 {
      return None
    }
    let magnitude = mul(x, div(om, dv))
    out[pos] = add(out[pos], magnitude)
  }
  Some(out)
}

///| RS復号: 訂正済み符号語を返す。訂正不能は None。
pub fn rs_decode(msg : Array[Int], n_ec : Int) -> Array[Int]? {
  let synd = calc_syndromes(msg, n_ec)
  let mut clean = true
  for i = 0; i < synd.length(); i = i + 1 {
    if synd[i] != 0 {
      clean = false
    }
  }
  if clean {
    return Some(msg)
  }
  match find_error_locator(synd) {
    None => None
    Some(err_loc) =>
      match find_error_positions(err_loc, msg.length()) {
        None => None
        Some(positions) =>
          match correct_errors(msg, synd, err_loc, positions) {
            None => None
            Some(fixed) => {
              // 検証ゲート: 訂正後のシンドロームが全0でなければ失敗扱い
              let synd2 = calc_syndromes(fixed, n_ec)
              let mut ok = true
              for i = 0; i < synd2.length(); i = i + 1 {
                if synd2[i] != 0 {
                  ok = false
                }
              }
              if ok {
                Some(fixed)
              } else {
                None
              }
            }
          }
      }
  }
}
