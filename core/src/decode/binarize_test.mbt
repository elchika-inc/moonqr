///| 160x160 の合成フレーム。位置依存ノイズの明背景に、8pxモジュール相当の
///| ファインダ様パターン（外周リング黒・ギャップ白・中心72x72一様黒芯）を1つ描く。
///| 一様fixtureは禁止（インデックスバグを隠すため）なので背景は常にノイズを乗せる。
///|
///| 黒芯を72x72pxにしているのは、jsQR のしきい値化は「低分散ブロックの
///| 左/上/左上への継承」（binarize.mbt L83-95）と「5x5近傍ブロック平均」
///| （L127-135, 5ブロック=40px幅の窓）の二段構えであり、黒芯が40px程度だと
///| 5x5窓が一様領域の外（境界の実測ブロック）まで直接届いてしまい継承が
///| 効かなくても偶然正解してしまう（要検証: 継承を無効化しても本テストは
///| 落ちない場合、テスト自体が盲点を再現できていない）。72pxなら芯の中心
///| ブロックを中心とする5x5窓（±2ブロック=40px）が芯の内部に完全に収まり、
///| 境界の実測ブロックへ継承なしに到達できないため、Phase 1で見つかった
///| 「一様ブロックは低分散→mean/2で白化され、境界から遠いと盲点になる」
///| ケースを継承機構なしでは解けない形で再現できる。
fn synth_frame(w : Int, h : Int) -> Bytes {
  let buf = FixedArray::make(w * h * 4, b'\x00')
  for y = 0; y < h; y = y + 1 {
    for x = 0; x < w; x = x + 1 {
      let mut v = 180 + (x * 7 + y * 13) % 40
      let fx = x - 20
      let fy = y - 20
      if fx >= 0 && fx < 104 && fy >= 0 && fy < 104 {
        let mx = fx / 8
        let my = fy / 8
        let ring = mx == 0 || mx == 12 || my == 0 || my == 12
        let core = mx >= 2 && mx <= 10 && my >= 2 && my <= 10
        v = if ring || core { 30 } else { 220 }
      }
      let i = (y * w + x) * 4
      buf[i] = v.to_byte()
      buf[i + 1] = v.to_byte()
      buf[i + 2] = v.to_byte()
      buf[i + 3] = b'\xFF'
    }
  }
  Bytes::from_fixedarray(buf)
}

test "binarize marks ring pixel black and gap pixel white" {
  let frame = synth_frame(160, 160)
  let (bin, _inv) = @decode.binarize(frame, 160, 160)
  // リング（外周, fx=4,fy=4 -> 絶対座標 24,24）は黒
  assert_true(bin.get(24, 24))
  // ギャップ（fx=12,fy=12, mx=my=1 -> 絶対座標 32,32）は白
  assert_false(bin.get(32, 32))
  // パターン外の明背景（10,10）は白
  assert_false(bin.get(10, 10))
}

test "binarize resolves >24px uniform black core correctly (jsQR blind spot regression)" {
  let frame = synth_frame(160, 160)
  let (bin, _inv) = @decode.binarize(frame, 160, 160)
  // 黒芯の深部（fx=fy=52 -> 絶対座標 72,72, ブロック hr=vr=9）。この
  // ブロックを中心とする5x5しきい値窓（ブロック7..11）は芯の内部
  // （mx,my 2..10 の範囲に完全に収まる）に収まり、継承なしには境界の
  // 実測しきい値へ到達できない。
  assert_true(bin.get(72, 72))
  // 黒芯の中でも境界に近い側（fx=fy=17 -> 絶対座標 37,37）も黒
  assert_true(bin.get(37, 37))
  // 黒芯の中でも境界から最も遠い側（fx=fy=87 -> 絶対座標 107,107）も黒
  assert_true(bin.get(107, 107))
}

test "inverted matrix is logical negation of binarized at same coords" {
  let frame = synth_frame(160, 160)
  let (bin, inv) = @decode.binarize(frame, 160, 160)
  let coords : Array[(Int, Int)] = [(24, 24), (32, 32), (10, 10), (72, 72), (37, 37)]
  for i = 0; i < coords.length(); i = i + 1 {
    let (x, y) = coords[i]
    assert_eq(inv.get(x, y), !bin.get(x, y))
  }
}
