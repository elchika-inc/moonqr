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
 * 半減ピラミッドを構築し、**小スケール（画素数の少ない）レベルから昇順に**
 * decodeFn を試行するマルチスケールデコード。
 *
 * 試行順の根拠（perf）: カメラ写真は小スケールでデコードできることが大半
 * （実測: ユーザーの16Mピクセル写真は1/8スケールでのみ成功）なのに、大スケール
 * から試すとネイティブ解像度の失敗試行（Nodeで約3.5秒、スマホ実機ではさらに
 * 遅い）を毎回払うことになる。一般的なスキャナの定石に合わせ、安価な小スケール
 * （~100ms）から試し、フル解像度は「遠く/小さく写ったQR」向けの最後の手段と
 * する。
 *
 * 手順:
 *   1. メモリガード: width*height が MAX_PIXELS を超える場合、超えなくなるまで
 *      先に半分縮小する（decode_js の16Mピクセル上限に収めるため）。この事前
 *      半減も scale に計上する——scale は常に「入力ネイティブ解像度に対する
 *      総縮小率」（48MP級スマホ写真では事前半減が日常的に発動する）。
 *   2. ピラミッド構築: ≤16Mの基点レベルから halveRGBA を繰り返し、
 *      max(width, height) >= 150 のレベルからさらに1段生成する（従来の逐次
 *      halving と同一のレベル集合）。メモリ注記: 全レベルを保持するコストは
 *      幾何級数（1 + 1/4 + 1/16 + ...）で基点画像の約1.33倍——許容範囲として
 *      先行構築を採用（遅延構築より単純で、demo.html との手動同期も容易）。
 *   3. 画素数の少ないレベルから昇順に decodeFn を試行。成功したら
 *      { result, scale, width, height, attemptedScales } を返す
 *      （scale = 成功レベルの総縮小率。attemptedScales = 試行した scale の列、
 *      先頭が最小レベル＝最大 scale）。全レベル失敗なら null。
 *
 * @param {(data: Uint8Array, width: number, height: number) => any} decodeFn
 *   1回のデコード試行。成功時はtruthyな結果（例: パース済みJSON）、失敗時は
 *   null/""等のfalsyを返すこと。
 * @param {Uint8Array} data RGBA画素（ネイティブ解像度）
 * @param {number} width
 * @param {number} height
 * @returns {{result: any, scale: number, width: number, height: number,
 *            attemptedScales: number[]} | null}
 */
export function multiScaleDecode(decodeFn, data, width, height) {
  let curData = data;
  let curW = width;
  let curH = height;
  let scale = 1; // 入力ネイティブ解像度に対する総縮小率（事前半減も計上する）

  // 1. メモリガード（16Mピクセル上限に収まるまで先に縮小。この半減も scale に
  //    計上する——計上しないと「事前半減のおかげで初めて成功した」ケースが
  //    scale=1（無縮小成功）として報告されてしまう）
  while (curW * curH > MAX_PIXELS) {
    const halved = halveRGBA(curData, curW, curH);
    curData = halved.data;
    curW = halved.width;
    curH = halved.height;
    scale *= 2;
  }

  // 2. 半減ピラミッド構築（levels[0] = 基点 = 最大レベル）
  const levels = [{ data: curData, width: curW, height: curH, scale }];
  while (Math.max(curW, curH) >= 150) {
    const halved = halveRGBA(curData, curW, curH);
    curData = halved.data;
    curW = halved.width;
    curH = halved.height;
    scale *= 2;
    levels.push({ data: curData, width: curW, height: curH, scale });
  }

  // 3. 小スケール（画素数の少ない）レベルから昇順に試行
  const attemptedScales = [];
  for (let i = levels.length - 1; i >= 0; i--) {
    const lv = levels[i];
    attemptedScales.push(lv.scale);
    const result = decodeFn(lv.data, lv.width, lv.height);
    if (result) {
      return {
        result,
        scale: lv.scale,
        width: lv.width,
        height: lv.height,
        attemptedScales,
      };
    }
  }
  return null;
}
