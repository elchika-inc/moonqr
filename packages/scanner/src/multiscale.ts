// マルチスケールデコード（Phase 2 Task 12 発の回帰網を継承）。
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
// Phase 3 Task 5: このファイルが唯一の実装（旧 packages/moonqr/test/lib/multiscale.mjs
// は削除済み・回帰テストはこの実装を直接importする形で移設した）。bench/demo.html に
// あった手動同期の旧いインライン複製は Task 7 で削除済み——GitHub Pages デモ
// （site/app.js）はこの実装を `@elchika-inc/moonqr-scanner` の公開 export
// （`multiScaleDecode`）経由で使う。

// decode_js (core/src/decode/decode.mbt) の max_pixels 定数と同じ値
// （16 * 1024 * 1024 = 16,777,216）。この上限を超える画素数のまま
// decode_js に渡すと常に "" が返るため、初回試行の前に半分縮小で収める。
const MAX_PIXELS = 16 * 1024 * 1024;

/** RGBA画素バッファ（縮小結果）。 */
export interface RGBAImage {
  data: Uint8Array;
  width: number;
  height: number;
}

export interface MultiScaleOutcome<T> {
  result: T;
  /** 成功時のネイティブ解像度からの総縮小率（1, 2, 4, 8, ...） */
  scale: number;
  width: number;
  height: number;
  /** 試行したスケール（昇順＝小さい画像から） */
  attemptedScales: number[];
}

/**
 * RGBA画素配列を2x2ボックス平均で縦横半分に縮小する（決定的・純TS実装）。
 * 幅・高さが奇数の場合は末尾の行/列を切り捨てる。
 *
 * 2x2 ボックス平均（正しいローパスフィルタ）を採用する理由: モニター接写の
 * サブピクセル格子は高周波成分であり、単発の間引き縮小（例: nearest-neighbor
 * downscale）はこれをエイリアシングしてむしろ悪化させる。ボックス平均は
 * 縮小前に高周波成分を平均化して減衰させるため、段階的に適用すると格子が
 * 消えていく。
 *
 * @param data RGBA画素（length === width*height*4）
 */
export function halveRGBA(data: Uint8Array, width: number, height: number): RGBAImage {
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
          r += data[si] ?? 0;
          g += data[si + 1] ?? 0;
          b += data[si + 2] ?? 0;
          a += data[si + 3] ?? 0;
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
 * する（実測: 5382ms → 62ms）。
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
 *      先行構築を採用（遅延構築より単純）。
 *   3. 画素数の少ないレベルから昇順に decodeFn を試行。成功したら
 *      { result, scale, width, height, attemptedScales } を返す
 *      （scale = 成功レベルの総縮小率。attemptedScales = 試行した scale の列、
 *      先頭が最小レベル＝最大 scale）。全レベル失敗なら null。
 *
 * @param decodeFn 1回のデコード試行。成功時はtruthyな結果、失敗時は
 *   null/""等のfalsyを返すこと。
 * @param data RGBA画素（ネイティブ解像度）
 */
export function multiScaleDecode<T>(
  decodeFn: (data: Uint8Array, width: number, height: number) => T | null,
  data: Uint8Array,
  width: number,
  height: number,
): MultiScaleOutcome<T> | null {
  const baseLevel = shrinkToPixelLimit(data, width, height);
  const levels = buildScalePyramid(baseLevel);

  const attemptedScales: number[] = [];
  for (let i = levels.length - 1; i >= 0; i--) {
    const level = levels[i];
    if (!level) continue;
    attemptedScales.push(level.scale);
    const result = decodeFn(level.data, level.width, level.height);
    if (result) {
      return {
        result,
        scale: level.scale,
        width: level.width,
        height: level.height,
        attemptedScales,
      };
    }
  }
  return null;
}

function shrinkToPixelLimit(
  data: Uint8Array,
  width: number,
  height: number,
): RGBAImage & { scale: number } {
  let current = { data, width, height, scale: 1 };
  // 事前半減も総縮小率に含め、ガード後の画像をscale=1と報告しない。
  while (current.width * current.height > MAX_PIXELS) {
    const halved = halveRGBA(current.data, current.width, current.height);
    current = { ...halved, scale: current.scale * 2 };
  }
  return current;
}

function buildScalePyramid(
  baseLevel: RGBAImage & { scale: number },
): Array<RGBAImage & { scale: number }> {
  const levels = [baseLevel];
  let current = baseLevel;
  while (Math.max(current.width, current.height) >= 150) {
    const halved = halveRGBA(current.data, current.width, current.height);
    current = { ...halved, scale: current.scale * 2 };
    levels.push(current);
  }
  return levels;
}
