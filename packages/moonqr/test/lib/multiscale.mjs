// Phase 2 Task 12: モニター格子写真対応のマルチスケールデコードヘルパー。
//
// 背景（root cause）: モニターに表示したQRをスマホで撮影すると、モニターの
// サブピクセル格子（白いはずの領域に高周波の暗い格子線が写り込む）が乗る。
// jsQR方式のブロック二値化はこの高周波パターンを「ほぼ50%speckle」と誤認し、
// ファインダパターンを検出できなくなる（jsQR npm でも同一の失敗——自前
// decode_js のコア二値化/ロケータには手を入れていない＝coreはjsQRとパリティ
// のまま）。素朴な単発縮小（例: sips -Z による単一ステップのdownscale）は
// 格子をエイリアシングしてむしろ悪化させる（1600/1200/1000/800/600/400px
// いずれも両実装で失敗を確認済み）。2x2ボックス平均による段階的な半分縮小
// （正しいローパスフィルタ）を繰り返すと、1/8スケール付近で格子の高周波成分
// が十分に減衰し、両実装ともデコードに成功する（1/16まで縮小するとモジュール
// が小さくなりすぎて失敗する）。詳細は bench/RESULT.md Task 12 節を参照。
//
// 同一ロジックが bench/demo.html にも存在する（手動同期。demo.html は bench/
// から静的配信されるため packages/ 配下からimportできない——ロジックを変更
// する場合は両方のファイルを更新すること。両ファイルにこの注記を残す）。

// decode_js (core/src/decode/decode.mbt) の max_pixels 定数と同じ値
// （16 * 1024 * 1024 = 16,777,216）。この上限を超える画素数のまま
// decode_js に渡すと常に "" が返るため、初回試行の前に半分縮小で収める。
const MAX_PIXELS = 16 * 1024 * 1024;

/**
 * RGBA画素配列を2x2ボックス平均で縦横半分に縮小する（決定的・純JS実装）。
 * 幅・高さが奇数の場合は末尾の行/列を切り捨てる。
 * @param {Uint8Array} data RGBA画素（length === width*height*4）
 * @param {number} width
 * @param {number} height
 * @returns {{data: Uint8Array, width: number, height: number}}
 */
export function halveRGBA(data, width, height) {
  const nw = Math.floor(width / 2);
  const nh = Math.floor(height / 2);
  const out = new Uint8Array(nw * nh * 4);
  for (let y = 0; y < nh; y++) {
    for (let x = 0; x < nw; x++) {
      const sx = x * 2;
      const sy = y * 2;
      let r = 0;
      let g = 0;
      let b = 0;
      let a = 0;
      for (let dy = 0; dy < 2; dy++) {
        for (let dx = 0; dx < 2; dx++) {
          const si = ((sy + dy) * width + (sx + dx)) * 4;
          r += data[si];
          g += data[si + 1];
          b += data[si + 2];
          a += data[si + 3];
        }
      }
      const di = (y * nw + x) * 4;
      out[di] = r >> 2;
      out[di + 1] = g >> 2;
      out[di + 2] = b >> 2;
      out[di + 3] = a >> 2;
    }
  }
  return { data: out, width: nw, height: nh };
}

/**
 * decodeFn を現在スケールで試行し、失敗したら halveRGBA で段階的に縮小しながら
 * 再試行するマルチスケールデコード。
 *
 * 手順:
 *   1. メモリガード: width*height が MAX_PIXELS を超える場合、超えなくなるまで
 *      先に半分縮小する（decode_js の16Mピクセル上限に収めるため）。
 *   2. decodeFn(data, width, height) を試行。truthy を返せば成功として
 *      { result, scale, width, height } を返す（scale = 1/scale が実際に使われた
 *      縮小率。scale=1なら無縮小、scale=8なら1/8縮小で成功）。
 *   3. 失敗（falsy）なら max(width, height) >= 150 の間は halveRGBA して再試行。
 *      150未満まで縮小してなお失敗した場合は null を返す。
 *
 * @param {(data: Uint8Array, width: number, height: number) => any} decodeFn
 *   1回のデコード試行。成功時はtruthyな結果（例: パース済みJSON）、失敗時は
 *   null/""等のfalsyを返すこと。
 * @param {Uint8Array} data RGBA画素（ネイティブ解像度）
 * @param {number} width
 * @param {number} height
 * @returns {{result: any, scale: number, width: number, height: number} | null}
 */
export function multiScaleDecode(decodeFn, data, width, height) {
  let curData = data;
  let curW = width;
  let curH = height;

  // 1. メモリガード（16Mピクセル上限に収まるまで先に縮小）
  while (curW * curH > MAX_PIXELS) {
    const halved = halveRGBA(curData, curW, curH);
    curData = halved.data;
    curW = halved.width;
    curH = halved.height;
  }

  // 2-3. 縮小しながらの再試行ループ
  let scale = 1;
  for (;;) {
    const result = decodeFn(curData, curW, curH);
    if (result) {
      return { result, scale, width: curW, height: curH };
    }
    if (Math.max(curW, curH) < 150) {
      return null;
    }
    const halved = halveRGBA(curData, curW, curH);
    curData = halved.data;
    curW = halved.width;
    curH = halved.height;
    scale *= 2;
  }
}
