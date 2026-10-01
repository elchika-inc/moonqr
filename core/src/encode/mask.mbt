///| 契約: mask は 0..7 のみ（ISO 18004 のマスクパターン番号）。内部呼び出しは
///| choose_mask が 0..7 のループでのみ渡すため常に満たされる。範囲外は誤用として abort。
pub fn mask_bit(mask : Int, x : Int, y : Int) -> Bool {
  if mask < 0 || mask > 7 {
    abort("mask_bit: mask out of range 0..7 (caller contract violation)")
  }
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
  penalty_runs(m) + penalty_blocks(m) + penalty_finder_patterns(m) +
  penalty_dark_balance(m)
}

fn penalty_runs(m : Matrix) -> Int {
  let mut score = 0
  // N1: 同色5連続以上（行・列）: 3 + 超過分
  for axis = 0; axis < 2; axis = axis + 1 {
    for line = 0; line < m.size; line = line + 1 {
      let mut run = 1
      for position = 1; position < m.size; position = position + 1 {
        let current_color = if axis == 0 {
          m.get(position, line)
        } else {
          m.get(line, position)
        }
        let previous_color = if axis == 0 {
          m.get(position - 1, line)
        } else {
          m.get(line, position - 1)
        }
        if current_color == previous_color {
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
  score
}

fn penalty_blocks(m : Matrix) -> Int {
  let mut score = 0
  // N2: 2x2 同色ブロック: 3点/個
  for y = 0; y < m.size - 1; y = y + 1 {
    for x = 0; x < m.size - 1; x = x + 1 {
      let color = m.get(x, y)
      if m.get(x + 1, y) == color && m.get(x, y + 1) == color &&
        m.get(x + 1, y + 1) == color {
        score = score + 3
      }
    }
  }
  score
}

fn penalty_finder_patterns(m : Matrix) -> Int {
  let mut score = 0
  // N3: 1011101 の前後に 0000（ファインダ様）: 40点/個
  let trailing_light_pattern = [
    true, false, true, true, true, false, true, false, false, false, false,
  ]
  let leading_light_pattern = [
    false, false, false, false, true, false, true, true, true, false, true,
  ]
  for axis = 0; axis < 2; axis = axis + 1 {
    for line = 0; line < m.size; line = line + 1 {
      for start = 0; start + 10 < m.size; start = start + 1 {
        let mut is_trailing_match = true
        let mut is_leading_match = true
        for offset = 0; offset < 11; offset = offset + 1 {
          let color = if axis == 0 {
            m.get(start + offset, line)
          } else {
            m.get(line, start + offset)
          }
          if color != trailing_light_pattern[offset] {
            is_trailing_match = false
          }
          if color != leading_light_pattern[offset] {
            is_leading_match = false
          }
        }
        if is_trailing_match {
          score = score + 40
        }
        if is_leading_match {
          score = score + 40
        }
      }
    }
  }
  score
}

fn penalty_dark_balance(m : Matrix) -> Int {
  // N4: 黒率の50%からの乖離 5%毎に10点
  let mut dark_modules = 0
  for y = 0; y < m.size; y = y + 1 {
    for x = 0; x < m.size; x = x + 1 {
      if m.get(x, y) {
        dark_modules = dark_modules + 1
      }
    }
  }
  let total_modules = m.size * m.size
  // 互換性のため、黒率を整数に切り捨ててから50%との差を取る。
  let dark_percent = dark_modules * 100 / total_modules
  let deviation_percent = if dark_percent >= 50 {
    dark_percent - 50
  } else {
    50 - dark_percent
  }
  deviation_percent / 5 * 10
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
