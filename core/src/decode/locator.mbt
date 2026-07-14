///| 移植元: jsQR (Apache-2.0), commit 8e6a036beafa7053dd44b1b76ac578d22b1b3311
///| https://github.com/cozmo/jsQR/blob/8e6a036beafa7053dd44b1b76ac578d22b1b3311/src/locator/index.ts
///| 二値行列から3つのファインダパターン（1:1:3:1:1 のB:W:B:W:B 比率）と
///| アライメントパターン（1:1:1 のW:B:W 比率）を走査で検出し、Quad にまとめ、
///| スコアリング → グルーピング → 再センタリング → 次元推定までを忠実に移植する。
///| 詳細な行対応・アダプテーションは task-3-report.md 参照。

let max_finderpatterns_to_search : Int = 4

let min_quad_ratio : Double = 0.5

let max_quad_ratio : Double = 1.5

///| 検出結果。jsQR `QRLocation` 相当（`moduleSize` はこの移植で追加保持する）。
pub struct QrLocation {
  top_left : Point
  top_right : Point
  bottom_left : Point
  alignment : Point
  dimension : Int
  module_size : Double
}

///| 走査中の1行分の候補セグメント（jsQR Quad.top / Quad.bottom 相当）。
priv struct Line {
  start_x : Int
  end_x : Int
  y : Int
}

///| 縦方向に連続した Line をひとまとめにしたファインダ/アライメント候補。
priv struct Quad {
  top : Line
  bottom : Line
}

///| ファインダパターン候補の初期スコアリング結果。
///| idx は元の挿入順。jsQR は ES2019 で安定保証された Array.prototype.sort に
///| 依存するが、MoonBit の Array::sort_by は安定性を保証しないため、
///| スコア同点時のタイブレーカとして idx を比較し安定ソートをエミュレートする
///| （Task 10 のコーパスパリティで jsQR と同じ実効順序を保つため）。
priv struct ScoredPoint {
  point : Point
  score : Double
  size : Double
  idx : Int
}

///| finderPatternGroups の1グループ（3点 + 合計スコア）。
///| idx は ScoredPoint と同じ安定ソートエミュレーション用タイブレーカ。
priv struct FinderGroup {
  p0 : Point
  p1 : Point
  p2 : Point
  score : Double
  idx : Int
}

priv struct DimensionResult {
  dimension : Int
  module_size : Double
}

priv struct AlignmentResult {
  point : Point
  dimension : Int
  module_size : Double
}

fn distance(a : Point, b : Point) -> Double {
  let dx = b.x - a.x
  let dy = b.y - a.y
  (dx * dx + dy * dy).sqrt()
}

fn sum(values : Array[Double]) -> Double {
  let mut total = 0.0
  for v in values {
    total = total + v
  }
  total
}

fn compare_double(a : Double, b : Double) -> Int {
  if a < b {
    -1
  } else if a > b {
    1
  } else {
    0
  }
}

///| ScoredPoint のスコア昇順比較。同点は挿入順（idx）で決着
///| （安定ソートエミュレーション — ScoredPoint のコメント参照）。
fn compare_scored_point(a : ScoredPoint, b : ScoredPoint) -> Int {
  let c = compare_double(a.score, b.score)
  if c != 0 {
    c
  } else {
    a.idx - b.idx
  }
}

///| 3つのファインダパターン中心を bottomLeft / topLeft / topRight に並べ替える
///| （jsQR `reorderFinderPatterns`）。
fn reorder_finder_patterns(
  pattern1 : Point,
  pattern2 : Point,
  pattern3 : Point,
) -> (Point, Point, Point) {
  let one_two = distance(pattern1, pattern2)
  let two_three = distance(pattern2, pattern3)
  let one_three = distance(pattern1, pattern3)
  let (bl0, tl0, tr0) = if two_three >= one_two && two_three >= one_three {
    (pattern2, pattern1, pattern3)
  } else if one_three >= two_three && one_three >= one_two {
    (pattern1, pattern2, pattern3)
  } else {
    (pattern1, pattern3, pattern2)
  }

  // 外積 BC x BA の z 成分が負なら bottomLeft/topRight が入れ替わっている
  let cross = (tr0.x - tl0.x) * (bl0.y - tl0.y) - (tr0.y - tl0.y) * (bl0.x - tl0.x)
  let (bottom_left, top_right) = if cross < 0.0 { (tr0, bl0) } else { (bl0, tr0) }
  (bottom_left, tl0, top_right)
}

///| 3つのファインダパターン中心からモジュールサイズと dimension（辺のモジュール数）を推定する
///| （jsQR `computeDimension`）。moduleSize < 1 は無効候補として None を返す
///| （jsQR は例外を投げて呼び出し元で捕捉するが、この移植では Option で表現する）。
fn compute_dimension(
  top_left : Point,
  top_right : Point,
  bottom_left : Point,
  matrix : BitMatrix,
) -> DimensionResult? {
  let module_size = (
      sum(count_black_white_run(top_left, bottom_left, matrix, 5)) / 7.0 +
      sum(count_black_white_run(top_left, top_right, matrix, 5)) / 7.0 +
      sum(count_black_white_run(bottom_left, top_left, matrix, 5)) / 7.0 +
      sum(count_black_white_run(top_right, top_left, matrix, 5)) / 7.0
    ) /
    4.0
  if module_size < 1.0 {
    None
  } else {
    let top_dimension = (distance(top_left, top_right) / module_size).round().to_int()
    let side_dimension = (distance(top_left, bottom_left) / module_size).round().to_int()
    let mut dimension = (top_dimension + side_dimension) / 2 + 7
    dimension = match dimension % 4 {
      0 => dimension + 1
      2 => dimension - 1
      _ => dimension
    }
    Some({ dimension, module_size })
  }
}

///| origin から end 方向へ、白黒反転が起きるたびの画素長を length 個集める
///| （Bresenham の変種。jsQR `countBlackWhiteRunTowardsPoint`）。
fn count_black_white_run_towards_point(
  origin : Point,
  end : Point,
  matrix : BitMatrix,
  length : Int,
) -> Array[Double] {
  let switch_xs : Array[Int] = [origin.x.floor().to_int()]
  let switch_ys : Array[Int] = [origin.y.floor().to_int()]
  let steep = Double::abs(end.y - origin.y) > Double::abs(end.x - origin.x)
  let (from_x, from_y, to_x, to_y) = if steep {
    (
      origin.y.floor().to_int(),
      origin.x.floor().to_int(),
      end.y.floor().to_int(),
      end.x.floor().to_int(),
    )
  } else {
    (
      origin.x.floor().to_int(),
      origin.y.floor().to_int(),
      end.x.floor().to_int(),
      end.y.floor().to_int(),
    )
  }
  let dx = Int::abs(to_x - from_x)
  let dy = Int::abs(to_y - from_y)
  let mut error = ((-dx).to_double() / 2.0).floor().to_int()
  let x_step = if from_x < to_x { 1 } else { -1 }
  let y_step = if from_y < to_y { 1 } else { -1 }
  let mut current_pixel = true
  let mut x = from_x
  let mut y = from_y
  while x != to_x + x_step {
    let real_x = if steep { y } else { x }
    let real_y = if steep { x } else { y }
    if matrix.get(real_x, real_y) != current_pixel {
      current_pixel = !current_pixel
      switch_xs.push(real_x)
      switch_ys.push(real_y)
      if switch_xs.length() == length + 1 {
        break
      }
    }
    error = error + dy
    if error > 0 {
      if y == to_y {
        break
      }
      y = y + y_step
      error = error - dx
    }
    x = x + x_step
  }
  let distances : Array[Double] = []
  for i = 0; i < length; i = i + 1 {
    if i + 1 < switch_xs.length() {
      let ddx = (switch_xs[i + 1] - switch_xs[i]).to_double()
      let ddy = (switch_ys[i + 1] - switch_ys[i]).to_double()
      distances.push((ddx * ddx + ddy * ddy).sqrt())
    } else {
      distances.push(0.0)
    }
  }
  distances
}

///| origin を中心に end 方向・その逆方向の両方から黒白ランを数え、
///| origin を挟む length 個のランに合成する（jsQR `countBlackWhiteRun`）。
fn count_black_white_run(
  origin : Point,
  end : Point,
  matrix : BitMatrix,
  length : Int,
) -> Array[Double] {
  let rise = end.y - origin.y
  let run = end.x - origin.x
  let half = (length + 1) / 2
  let towards_end = count_black_white_run_towards_point(origin, end, matrix, half)
  let away_end : Point = { x: origin.x - run, y: origin.y - rise }
  let away_from_end = count_black_white_run_towards_point(origin, away_end, matrix, half)
  let middle_value = towards_end[0] + away_from_end[0] - 1.0
  let result : Array[Double] = []
  for i = 1; i < away_from_end.length(); i = i + 1 {
    result.push(away_from_end[i])
  }
  result.push(middle_value)
  for i = 1; i < towards_end.length(); i = i + 1 {
    result.push(towards_end[i])
  }
  result
}

///| 黒白ランと期待比率(ratios)を比較し、平均モジュールサイズと誤差を返す
///| （jsQR `scoreBlackWhiteRun`）。
fn score_black_white_run(sequence : Array[Double], ratios : Array[Double]) -> (Double, Double) {
  let average_size = sum(sequence) / sum(ratios)
  let mut error = 0.0
  for i = 0; i < ratios.length(); i = i + 1 {
    let diff = sequence[i] - ratios[i] * average_size
    error = error + diff * diff
  }
  (average_size, error)
}

///| point を中心に水平・垂直・両斜め方向へ黒白ランを取り、ratios（1:1:3:1:1 等）との
///| 一致度をスコア化する（値が小さいほど良い）。jsQR `scorePattern`。
///| jsQR は try/catch で例外時に Infinity を返すが、`matrix.get` が範囲外で
///| 例外を投げない（false を返す）ため、この移植では例外パスは到達不能であり
///| 素直に計算する（詳細は task-3-report.md）。
fn score_pattern(point : Point, ratios : Array[Double], matrix : BitMatrix) -> Double {
  let end_left : Point = { x: -1.0, y: point.y }
  let horizontal_run = count_black_white_run(point, end_left, matrix, ratios.length())
  let end_up : Point = { x: point.x, y: -1.0 }
  let vertical_run = count_black_white_run(point, end_up, matrix, ratios.length())
  let top_left_point : Point = {
    x: Double::max(0.0, point.x - point.y) - 1.0,
    y: Double::max(0.0, point.y - point.x) - 1.0,
  }
  let diag_down_run = count_black_white_run(point, top_left_point, matrix, ratios.length())
  let bottom_left_point : Point = {
    x: Double::min(matrix.width.to_double(), point.x + point.y) + 1.0,
    y: Double::min(matrix.height.to_double(), point.y + point.x) + 1.0,
  }
  let diag_up_run = count_black_white_run(point, bottom_left_point, matrix, ratios.length())
  let (horz_size, horz_error) = score_black_white_run(horizontal_run, ratios)
  let (vert_size, vert_error) = score_black_white_run(vertical_run, ratios)
  let (diag_down_size, diag_down_error) = score_black_white_run(diag_down_run, ratios)
  let (diag_up_size, diag_up_error) = score_black_white_run(diag_up_run, ratios)
  let ratio_error = (
    horz_error * horz_error +
    vert_error * vert_error +
    diag_down_error * diag_down_error +
    diag_up_error * diag_up_error
  ).sqrt()
  let avg_size = (horz_size + vert_size + diag_down_size + diag_up_size) / 4.0
  let size_error = (
      (horz_size - avg_size) * (horz_size - avg_size) +
      (vert_size - avg_size) * (vert_size - avg_size) +
      (diag_down_size - avg_size) * (diag_down_size - avg_size) +
      (diag_up_size - avg_size) * (diag_up_size - avg_size)
    ) /
    avg_size
  ratio_error + size_error
}

///| 点 p の周囲の黒領域の重心へ再センタリングする（jsQR `recenterLocation`）。
fn recenter_location(matrix : BitMatrix, p : Point) -> Point {
  let row_y = p.y.round().to_int()
  let mut left_x = p.x.round().to_int()
  while matrix.get(left_x, row_y) {
    left_x = left_x - 1
  }
  let mut right_x = p.x.round().to_int()
  while matrix.get(right_x, row_y) {
    right_x = right_x + 1
  }
  let x = (left_x + right_x).to_double() / 2.0
  let col_x = x.round().to_int()
  let mut top_y = p.y.round().to_int()
  while matrix.get(col_x, top_y) {
    top_y = top_y - 1
  }
  let mut bottom_y = p.y.round().to_int()
  while matrix.get(col_x, bottom_y) {
    bottom_y = bottom_y + 1
  }
  let y = (top_y + bottom_y).to_double() / 2.0
  { x, y }
}

///| 与えられた3つのファインダパターン中心からアライメントパターンと dimension を探す
///| （jsQR `findAlignmentPattern`）。dimension 推定が無効な場合は None。
fn find_alignment_pattern(
  matrix : BitMatrix,
  alignment_pattern_quads : Array[Quad],
  top_right : Point,
  top_left : Point,
  bottom_left : Point,
) -> AlignmentResult? {
  match compute_dimension(top_left, top_right, bottom_left, matrix) {
    None => None
    Some(dim) => {
      let bottom_right_x = top_right.x - top_left.x + bottom_left.x
      let bottom_right_y = top_right.y - top_left.y + bottom_left.y
      let modules_between = (distance(top_left, bottom_left) + distance(top_left, top_right)) /
        2.0 /
        dim.module_size
      let correction_to_top_left = 1.0 - 3.0 / modules_between
      let expected : Point = {
        x: top_left.x + correction_to_top_left * (bottom_right_x - top_left.x),
        y: top_left.y + correction_to_top_left * (bottom_right_y - top_left.y),
      }
      let ratios_1_1_1 : Array[Double] = [1.0, 1.0, 1.0]
      let candidates : Array[ScoredPoint] = []
      for q in alignment_pattern_quads {
        let cx = (q.top.start_x + q.top.end_x + q.bottom.start_x + q.bottom.end_x).to_double() /
          4.0
        let cy = (q.top.y + q.bottom.y + 1).to_double() / 2.0
        if matrix.get(cx.floor().to_int(), cy.floor().to_int()) {
          let score_point : Point = { x: cx.floor(), y: cy.floor() }
          let size_score = score_pattern(score_point, ratios_1_1_1, matrix)
          let center : Point = { x: cx, y: cy }
          let score = size_score + distance(center, expected)
          // size フィールドは未使用（アライメント候補には size ペナルティが無いため）。
          // idx は挿入順（安定ソートエミュレーション用タイブレーカ）。
          candidates.push({ point: center, score, size: 0.0, idx: candidates.length() })
        }
      }
      candidates.sort_by(compare_scored_point)
      let alignment_point = if modules_between >= 15.0 && candidates.length() > 0 {
        candidates[0].point
      } else {
        expected
      }
      Some({ point: alignment_point, dimension: dim.dimension, module_size: dim.module_size })
    }
  }
}

///| 二値行列からファインダパターン3点とアライメントパターン、dimension を推定する
///| （jsQR `locate`）。最大2件（通常のクラスタ重心版と、黒領域再センタリング版）を返す。
///| どちらも見つからない場合は空配列を返す（jsQR は null を返すがここでは Option を
///| 使わず空配列に正規化する）。
pub fn locate(matrix : BitMatrix) -> Array[QrLocation] {
  let finder_pattern_quads : Array[Quad] = []
  let mut active_finder_pattern_quads : Array[Quad] = []
  let alignment_pattern_quads : Array[Quad] = []
  let mut active_alignment_pattern_quads : Array[Quad] = []
  for y = 0; y <= matrix.height; y = y + 1 {
    let mut length = 0
    let mut last_bit = false
    let mut s0 = 0
    let mut s1 = 0
    let mut s2 = 0
    let mut s3 = 0
    let mut s4 = 0
    for x = -1; x <= matrix.width; x = x + 1 {
      let v = matrix.get(x, y)
      if v == last_bit {
        length = length + 1
      } else {
        s0 = s1
        s1 = s2
        s2 = s3
        s3 = s4
        s4 = length
        length = 1
        last_bit = v
        let avg_finder = (s0 + s1 + s2 + s3 + s4).to_double() / 7.0
        let valid_finder = Double::abs(s0.to_double() - avg_finder) < avg_finder &&
          Double::abs(s1.to_double() - avg_finder) < avg_finder &&
          Double::abs(s2.to_double() - 3.0 * avg_finder) < 3.0 * avg_finder &&
          Double::abs(s3.to_double() - avg_finder) < avg_finder &&
          Double::abs(s4.to_double() - avg_finder) < avg_finder &&
          !v
        let avg_alignment = (s2 + s3 + s4).to_double() / 3.0
        let valid_alignment = Double::abs(s2.to_double() - avg_alignment) < avg_alignment &&
          Double::abs(s3.to_double() - avg_alignment) < avg_alignment &&
          Double::abs(s4.to_double() - avg_alignment) < avg_alignment &&
          v
        if valid_finder {
          let end_x = x - s3 - s4
          let start_x = end_x - s2
          let line : Line = { start_x, end_x, y }
          let mut matched = false
          for i = 0; i < active_finder_pattern_quads.length(); i = i + 1 {
            if !matched {
              let q = active_finder_pattern_quads[i]
              let ratio = s2.to_double() / (q.bottom.end_x - q.bottom.start_x).to_double()
              let is_match = (start_x >= q.bottom.start_x && start_x <= q.bottom.end_x) ||
                (end_x >= q.bottom.start_x && start_x <= q.bottom.end_x) ||
                (
                  start_x <= q.bottom.start_x &&
                  end_x >= q.bottom.end_x &&
                  ratio < max_quad_ratio &&
                  ratio > min_quad_ratio
                )
              if is_match {
                active_finder_pattern_quads[i] = { top: q.top, bottom: line }
                matched = true
              }
            }
          }
          if !matched {
            active_finder_pattern_quads.push({ top: line, bottom: line })
          }
        }
        if valid_alignment {
          let end_x = x - s4
          let start_x = end_x - s3
          let line : Line = { start_x, end_x, y }
          let mut matched = false
          for i = 0; i < active_alignment_pattern_quads.length(); i = i + 1 {
            if !matched {
              let q = active_alignment_pattern_quads[i]
              let ratio = s2.to_double() / (q.bottom.end_x - q.bottom.start_x).to_double()
              let is_match = (start_x >= q.bottom.start_x && start_x <= q.bottom.end_x) ||
                (end_x >= q.bottom.start_x && start_x <= q.bottom.end_x) ||
                (
                  start_x <= q.bottom.start_x &&
                  end_x >= q.bottom.end_x &&
                  ratio < max_quad_ratio &&
                  ratio > min_quad_ratio
                )
              if is_match {
                active_alignment_pattern_quads[i] = { top: q.top, bottom: line }
                matched = true
              }
            }
          }
          if !matched {
            active_alignment_pattern_quads.push({ top: line, bottom: line })
          }
        }
      }
    }
    for q in active_finder_pattern_quads {
      if q.bottom.y != y && q.bottom.y - q.top.y >= 2 {
        finder_pattern_quads.push(q)
      }
    }
    let keep_finder = fn(q : Quad) -> Bool { q.bottom.y == y }
    active_finder_pattern_quads = active_finder_pattern_quads.filter(keep_finder)
    for q in active_alignment_pattern_quads {
      if q.bottom.y != y {
        alignment_pattern_quads.push(q)
      }
    }
    let keep_alignment = fn(q : Quad) -> Bool { q.bottom.y == y }
    active_alignment_pattern_quads = active_alignment_pattern_quads.filter(keep_alignment)
  }
  for q in active_finder_pattern_quads {
    if q.bottom.y - q.top.y >= 2 {
      finder_pattern_quads.push(q)
    }
  }
  for q in active_alignment_pattern_quads {
    alignment_pattern_quads.push(q)
  }

  // ---- ファインダパターン候補の初期スコアリング（比率のみ、位置は未考慮） ----
  let candidates : Array[ScoredPoint] = []
  let ratios_1_1_3_1_1 : Array[Double] = [1.0, 1.0, 3.0, 1.0, 1.0]
  for q in finder_pattern_quads {
    let cx = (q.top.start_x + q.top.end_x + q.bottom.start_x + q.bottom.end_x).to_double() / 4.0
    let cy = (q.top.y + q.bottom.y + 1).to_double() / 2.0
    let rx = cx.round().to_int()
    let ry = cy.round().to_int()
    if matrix.get(rx, ry) {
      let l1 = q.top.end_x - q.top.start_x
      let l2 = q.bottom.end_x - q.bottom.start_x
      let l3 = q.bottom.y - q.top.y + 1
      let size = (l1 + l2 + l3).to_double() / 3.0
      let score_point : Point = { x: rx.to_double(), y: ry.to_double() }
      let score = score_pattern(score_point, ratios_1_1_3_1_1, matrix)
      let center : Point = { x: cx, y: cy }
      // idx は挿入順（安定ソートエミュレーション用タイブレーカ）
      candidates.push({ point: center, score, size, idx: candidates.length() })
    }
  }
  candidates.sort_by(compare_scored_point)

  // ---- 近いサイズの3点でグループ化 ----
  let groups : Array[FinderGroup] = []
  for i = 0; i < candidates.length(); i = i + 1 {
    if i <= max_finderpatterns_to_search {
      let point = candidates[i]
      let others : Array[ScoredPoint] = []
      for j = 0; j < candidates.length(); j = j + 1 {
        if j != i {
          let p = candidates[j]
          let size_penalty = (p.size - point.size) * (p.size - point.size) / point.size
          // idx は挿入順（安定ソートエミュレーション用タイブレーカ）
          others.push({
            point: p.point,
            score: p.score + size_penalty,
            size: p.size,
            idx: others.length(),
          })
        }
      }
      others.sort_by(compare_scored_point)
      if others.length() >= 2 {
        let group_score = point.score + others[0].score + others[1].score
        groups.push({
          p0: point.point,
          p1: others[0].point,
          p2: others[1].point,
          score: group_score,
          idx: groups.length(),
        })
      }
    }
  }
  if groups.is_empty() {
    return []
  }
  // groups もスコア同点時は挿入順で決着（安定ソートエミュレーション）
  let cmp_groups = fn(a : FinderGroup, b : FinderGroup) -> Int {
    let c = compare_double(a.score, b.score)
    if c != 0 {
      c
    } else {
      a.idx - b.idx
    }
  }
  groups.sort_by(cmp_groups)
  let best = groups[0]
  let (bottom_left, top_left, top_right) = reorder_finder_patterns(best.p0, best.p1, best.p2)
  let result : Array[QrLocation] = []
  match find_alignment_pattern(matrix, alignment_pattern_quads, top_right, top_left, bottom_left) {
    None => ()
    Some(a) =>
      result.push({
        top_left,
        top_right,
        bottom_left,
        alignment: a.point,
        dimension: a.dimension,
        module_size: a.module_size,
      })
  }

  // 量子化前の重心クラスタでの推定に加え、黒領域中心への再センタリング版も試す
  // （jsQR コメント: 画像圧縮起因の見かけの歪みに対する保険）。
  let mid_top_right = recenter_location(matrix, top_right)
  let mid_top_left = recenter_location(matrix, top_left)
  let mid_bottom_left = recenter_location(matrix, bottom_left)
  match
    find_alignment_pattern(
      matrix,
      alignment_pattern_quads,
      mid_top_right,
      mid_top_left,
      mid_bottom_left,
    ) {
    None => ()
    Some(a) =>
      result.push({
        top_left: mid_top_left,
        top_right: mid_top_right,
        bottom_left: mid_bottom_left,
        alignment: a.point,
        dimension: a.dimension,
        module_size: a.module_size,
      })
  }
  result
}
