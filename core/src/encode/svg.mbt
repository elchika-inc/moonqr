///| 黒モジュールを1つの path にまとめた SVG 文字列を返す（純粋関数）
pub fn to_svg_string(m : Matrix, margin : Int, cell : Int) -> String {
  let total = (m.size + margin * 2) * cell
  let mut d = ""
  for y = 0; y < m.size; y = y + 1 {
    for x = 0; x < m.size; x = x + 1 {
      if m.get(x, y) {
        let px = (x + margin) * cell
        let py = (y + margin) * cell
        d = d + "M\{px} \{py}h\{cell}v\{cell}h-\{cell}z"
      }
    }
  }
  "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 \{total} \{total}\">" +
  "<rect width=\"\{total}\" height=\"\{total}\" fill=\"#fff\"/>" +
  "<path d=\"\{d}\" fill=\"#000\"/></svg>"
}
