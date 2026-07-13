pub fn mask_bit(mask : Int, x : Int, y : Int) -> Bool {
  match mask {
    0 => (x + y) % 2 == 0
    1 => y % 2 == 0
    2 => x % 3 == 0
    3 => (x + y) % 3 == 0
    4 => (y / 2 + x / 3) % 2 == 0
    5 => x * y % 2 + x * y % 3 == 0
    6 => (x * y % 2 + x * y % 3) % 2 == 0
    _ => ((x + y) % 2 + x * y % 3) % 2 == 0
  }
}

///| データ領域（非機能領域）のみマスクXOR
pub fn apply_mask(m : Matrix, mask : Int) -> Unit {
  for y = 0; y < m.size; y = y + 1 {
    for x = 0; x < m.size; x = x + 1 {
      if !m.is_function(x, y) && mask_bit(mask, x, y) {
        m.set(x, y, !m.get(x, y))
      }
    }
  }
}

///| ISO 18004 の4ペナルティ規則
pub fn penalty(m : Matrix) -> Int {
  let mut score = 0
  // N1: 同色5連続以上（行・列）: 3 + 超過分
  for axis = 0; axis < 2; axis = axis + 1 {
    for a = 0; a < m.size; a = a + 1 {
      let mut run = 1
      for b = 1; b < m.size; b = b + 1 {
        let cur = if axis == 0 { m.get(b, a) } else { m.get(a, b) }
        let prev = if axis == 0 { m.get(b - 1, a) } else { m.get(a, b - 1) }
        if cur == prev {
          run = run + 1
          if run == 5 {
            score = score + 3
          } else if run > 5 {
            score = score + 1
          }
        } else {
          run = 1
        }
      }
    }
  }
  // N2: 2x2 同色ブロック: 3点/個
  for y = 0; y < m.size - 1; y = y + 1 {
    for x = 0; x < m.size - 1; x = x + 1 {
      let v = m.get(x, y)
      if m.get(x + 1, y) == v && m.get(x, y + 1) == v &&
        m.get(x + 1, y + 1) == v {
        score = score + 3
      }
    }
  }
  // N3: 1011101 の前後に 0000（ファインダ様）: 40点/個
  let pat1 = [true, false, true, true, true, false, true, false, false, false, false]
  let pat2 = [false, false, false, false, true, false, true, true, true, false, true]
  for axis = 0; axis < 2; axis = axis + 1 {
    for a = 0; a < m.size; a = a + 1 {
      for b = 0; b + 10 < m.size; b = b + 1 {
        let mut m1 = true
        let mut m2 = true
        for k = 0; k < 11; k = k + 1 {
          let v = if axis == 0 { m.get(b + k, a) } else { m.get(a, b + k) }
          if v != pat1[k] {
            m1 = false
          }
          if v != pat2[k] {
            m2 = false
          }
        }
        if m1 {
          score = score + 40
        }
        if m2 {
          score = score + 40
        }
      }
    }
  }
  // N4: 黒率の50%からの乖離 5%毎に10点
  let mut dark = 0
  for y = 0; y < m.size; y = y + 1 {
    for x = 0; x < m.size; x = x + 1 {
      if m.get(x, y) {
        dark = dark + 1
      }
    }
  }
  let total = m.size * m.size
  let percent = dark * 100 / total
  let dev = if percent >= 50 { percent - 50 } else { 50 - percent }
  score = score + dev / 5 * 10
  score
}

///| 8マスク試行して最小ペナルティのマスク番号を返す（フォーマット情報込みで評価）。
///| 契約: 返却時、データ領域は非マスク状態に復元済みだが、フォーマット情報セルには
///| 最後に試したマスクのビットが残る。呼び出し側は必ず
///| apply_mask(m, best) と place_format(m, ec, best) を実行すること（encode() はそうする）。
pub fn choose_mask(m : Matrix, ec : EcLevel) -> Int {
  let mut best = 0
  let mut best_score = 0x7FFFFFFF
  for mask = 0; mask < 8; mask = mask + 1 {
    apply_mask(m, mask)
    place_format(m, ec, mask)
    let s = penalty(m)
    if s < best_score {
      best_score = s
      best = mask
    }
    apply_mask(m, mask) // 戻す
  }
  best
}
