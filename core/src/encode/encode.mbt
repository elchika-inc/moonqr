///| テキストをQR行列にエンコードする。
///| version=None は 1..40 から最小の収まるバージョンを自動選択。
///| 容量超過・範囲外の明示 version は None。空文字も None（仕様上の決定:
///| qrcode npm は throw するが、本ライブラリは例外を投げず Option で表現する方針）。
pub fn encode(text : String, ec : EcLevel, version : Int?) -> Matrix? {
  match version {
    Some(v) =>
      if v < 1 || v > 40 {
        return None
      }
    None => ()
  }
  if text.length() == 0 || !input_within_model2_capacity(text) {
    return None
  }
  // 文字数指示子は 1-9 / 10-26 / 27-40 の帯でのみ変わるため、
  // 最適分割は帯ごとに1回だけ求めてバージョン試行間で再利用する。
  let segments_low = match optimal_segments(text, 1) {
    Some(segments) => segments
    None => return None
  }
  let segments_mid = match optimal_segments(text, 10) {
    Some(segments) => segments
    None => return None
  }
  let segments_high = match optimal_segments(text, 27) {
    Some(segments) => segments
    None => return None
  }
  let try_version = fn(v : Int) -> Matrix? {
    let writer = BitWriter::new()
    let segments = if v <= 9 {
      segments_low
    } else if v <= 26 {
      segments_mid
    } else {
      segments_high
    }
    write_segment_list(writer, text, v, segments)
    assemble_matrix(writer, v, ec)
  }
  match version {
    Some(v) => try_version(v)
    None => {
      // cci_bits がバージョン帯(1-9/10-26/27-40)で変わるため素直に線形試行
      for v = 1; v <= 40; v = v + 1 {
        match try_version(v) {
          Some(m) => return Some(m)
          None => continue
        }
      }
      None
    }
  }
}

///| JS境界用: [size, m00, m01, ...] の平坦配列。エラー時は空配列。
///| ec: 0=L 1=M 2=Q 3=H, version: 0=auto または 1..40。
///| total 関数（例外を投げない）: version・ec が範囲外、または text が空文字なら []。
pub fn encode_js(text : String, ec : Int, version : Int) -> Array[Int] {
  if version < 0 || version > 40 || ec < 0 || ec > 3 || text.length() == 0 {
    return []
  }
  let level = match ec {
    0 => EcLevel::L
    1 => EcLevel::M
    2 => EcLevel::Q
    _ => EcLevel::H
  }
  let v : Int? = if version == 0 { None } else { Some(version) }
  match encode(text, level, v) {
    None => []
    Some(matrix) => matrix_to_js_array(matrix)
  }
}

///| JS境界用: SVG文字列を直接返す。encode に失敗した場合（範囲外・空文字・容量超過）は ""。
///| ec: 0=L 1=M 2=Q 3=H, version: 0=auto または 1..40。
pub fn to_svg_string_js(
  text : String,
  ec : Int,
  version : Int,
  margin : Int,
  cell : Int,
) -> String {
  if version < 0 || version > 40 || ec < 0 || ec > 3 || text.length() == 0 {
    return ""
  }
  let level = match ec {
    0 => EcLevel::L
    1 => EcLevel::M
    2 => EcLevel::Q
    _ => EcLevel::H
  }
  let v : Int? = if version == 0 { None } else { Some(version) }
  match encode(text, level, v) {
    None => ""
    Some(m) => to_svg_string(m, margin, cell)
  }
}

fn assemble_matrix(writer : BitWriter, version : Int, ec : EcLevel) -> Matrix? {
  match assemble(writer, version, ec) {
    None => None
    Some(codewords) => {
      let matrix = Matrix::new(version)
      place_function_patterns(matrix, version)
      place_version(matrix, version)
      place_data(matrix, codewords)
      let mask = choose_mask(matrix, ec)
      apply_mask(matrix, mask)
      place_format(matrix, ec, mask)
      Some(matrix)
    }
  }
}

fn matrix_to_js_array(matrix : Matrix) -> Array[Int] {
  let out : Array[Int] = [matrix.size]
  for y = 0; y < matrix.size; y = y + 1 {
    for x = 0; x < matrix.size; x = x + 1 {
      out.push(if matrix.get(x, y) { 1 } else { 0 })
    }
  }
  out
}
