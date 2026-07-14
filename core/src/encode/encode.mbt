///| テキストをQR行列にエンコードする。
///| version=None は 1..40 から最小の収まるバージョンを自動選択。
///| 容量超過は None。空文字は None（仕様上の決定: qrcode npm は throw するが、
///| 本ライブラリは例外を投げず Option で表現する方針のため None に倒す）。
pub fn encode(text : String, ec : EcLevel, version : Int?) -> Matrix? {
  if text.length() == 0 {
    return None
  }
  let mode = detect_mode(text)
  let try_version = fn(v : Int) -> Matrix? {
    let w = BitWriter::new()
    write_segment(w, text, mode, v)
    match assemble(w, v, ec) {
      None => None
      Some(cw) => {
        let m = Matrix::new(v)
        place_function_patterns(m, v)
        place_version(m, v)
        place_data(m, cw)
        let mask = choose_mask(m, ec)
        apply_mask(m, mask)
        place_format(m, ec, mask)
        Some(m)
      }
    }
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
    Some(m) => {
      let out : Array[Int] = [m.size]
      for y = 0; y < m.size; y = y + 1 {
        for x = 0; x < m.size; x = x + 1 {
          out.push(if m.get(x, y) { 1 } else { 0 })
        }
      }
      out
    }
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
