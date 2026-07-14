///| 移植元: jsQR (Apache-2.0), commit 8e6a036beafa7053dd44b1b76ac578d22b1b3311
///| https://github.com/cozmo/jsQR/blob/8e6a036beafa7053dd44b1b76ac578d22b1b3311/src/index.ts
///| https://github.com/cozmo/jsQR/blob/8e6a036beafa7053dd44b1b76ac578d22b1b3311/src/decoder/decoder.ts
///|
///| `scan()`（候補 location を順に試し、最初に成功したものを返す）と
///| `jsQR()`（binarize→通常/反転の2系統を順に scan）のトップレベル制御フローを移植する。
///| jsQR `decoder.ts` の `decode()` は失敗時に抽出済み行列を対角線でミラーして
///| 再試行するが、brief の指示により本タスクでは未実装（候補ループのみ。
///| ミラー再試行は将来タスクの検討事項として残す）。
///|
///| バージョン判定: jsQR `readVersion` は dimension から算出した provisional
///| version が6以下ならビット読取なしでそのまま採用し、7以上のときだけ
///| version情報18bitを読んで最尤バージョンを採用する（不一致時はNoneではなく
///| 常に読取値を採用——ただし本ポートでは読取バージョンの想定dimension
///| (v*4+17) が実際の location.dimension と一致することを追加で要求する。
///| jsQR は Uint8ClampedArray 相当の範囲外アクセスが `undefined`＝falsy になる
///| JS の緩さに暗黙依存しているが、MoonBit の FixedArray はそうではなく
///| 範囲外アクセスがパニックするため、不一致は候補失敗として扱う安全側の
///| 意図的アダプテーション）。

///| `decode` の返り値。corners は TL,TR,BR,BL 順、元画像px座標
///| （jsQR `index.ts` の topLeftCorner/topRightCorner/bottomRightCorner/
///| bottomLeftCorner と同じ mapping(0,0)/mapping(dim,0)/mapping(dim,dim)/
///| mapping(0,dim) に対応）。
pub struct DecodeResult {
  text : String
  bytes : Array[Int]
  version : Int
  ec : @encode.EcLevel
  corners : Array[Point]
}

///| 二値行列1枚に対する候補ループ（jsQR `scan()` 相当）。
///| locate の候補を順に試し、format/version/data の全段を通過した最初の
///| 結果を返す。途中で失敗した候補は次候補へ（continue）。
fn scan(matrix : BitMatrix) -> DecodeResult? {
  let locations = locate(matrix)
  for i = 0; i < locations.length(); i = i + 1 {
    let loc = locations[i]
    let extracted = extract(matrix, loc)
    let m = extracted.matrix
    // dimension が version*4+17 の形（version 1..40）でなければ、この時点で
    // 候補として成立しない（jsQR は Uint8ClampedArray の範囲外読みが
    // undefined=falsy になる緩さに暗黙依存するが、MoonBit の FixedArray は
    // 範囲外アクセスがパニックするため、ここで明示的に弾く安全側の
    // アダプテーション。noise由来の誤検出locationで再現確認済み）。
    if (loc.dimension - 17) % 4 != 0 {
      continue
    }
    let provisional = (loc.dimension - 17) / 4
    if provisional < 1 || provisional > 40 {
      continue
    }
    let version = if provisional <= 6 {
      provisional
    } else {
      let (b1, b2) = read_version_bits(m)
      let v = match decode_version(b1, b2) {
        Some(v) => v
        None => continue
      }
      if v * 4 + 17 != loc.dimension {
        continue
      }
      v
    }
    let (f1, f2) = read_format_bits(m)
    let fmt = match decode_format(f1, f2) {
      Some(f) => f
      None => continue
    }
    let codewords = match read_data(m, version, fmt) {
      Some(cw) => cw
      None => continue
    }
    let dd = match decode_data(codewords, version) {
      Some(d) => d
      None => continue
    }
    let dim = loc.dimension.to_double()
    let mapping = extracted.mapping
    let corners = [
      mapping(0.0, 0.0),
      mapping(dim, 0.0),
      mapping(dim, dim),
      mapping(0.0, dim),
    ]
    return Some({ text: dd.text, bytes: dd.bytes, version, ec: fmt.ec, corners })
  }
  None
}

///| RGBA ピクセル → 復号結果。invert=true なら反転行列でも試行
///| （jsQR `jsQR()` の `attemptBoth` 相当）。
pub fn decode(data : Bytes, width : Int, height : Int, invert : Bool) -> DecodeResult? {
  let (normal, inverted) = binarize(data, width, height)
  match scan(normal) {
    Some(r) => Some(r)
    None => if invert { scan(inverted) } else { None }
  }
}

///| EcLevel → "L"/"M"/"Q"/"H"（decode_js のJSON出力用）。
fn ec_level_str(ec : @encode.EcLevel) -> String {
  match ec {
    @encode.EcLevel::L => "L"
    @encode.EcLevel::M => "M"
    @encode.EcLevel::Q => "Q"
    @encode.EcLevel::H => "H"
  }
}

///| RGBAピクセル1枚あたりの上限画素数（16M = 16 * 1024 * 1024）。
let max_pixels : Int = 16 * 1024 * 1024

///| JS境界（total）: `data.length == width*height*4` かつ `width>0`かつ`height>0`
///| かつ `width*height <= 16M` を満たさない不正入力は例外を出さず ""。
///| 成功時は `{"text":...,"bytes":[...],"version":N,"ecLevel":"M","corners":[{"x":..,"y":..}x4]}`
///| のJSON文字列（moonbitlang/core `@json` の `Json::stringify` でエスケープ）。
pub fn decode_js(data : Bytes, width : Int, height : Int, invert : Bool) -> String {
  if width <= 0 || height <= 0 {
    return ""
  }
  if width * height > max_pixels {
    return ""
  }
  if data.length() != width * height * 4 {
    return ""
  }
  match decode(data, width, height, invert) {
    None => ""
    Some(r) => {
      let bytes_json = r.bytes.map(fn(b) { Json::number(b.to_double()) })
      let corners_json = r.corners.map(fn(p) {
        Json::object({ "x": Json::number(p.x), "y": Json::number(p.y) })
      })
      let obj = Json::object({
        "text": Json::string(r.text),
        "bytes": Json::array(bytes_json),
        "version": Json::number(r.version.to_double()),
        "ecLevel": Json::string(ec_level_str(r.ec)),
        "corners": Json::array(corners_json),
      })
      obj.stringify()
    }
  }
}
