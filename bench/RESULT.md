# Task 3: 両バックエンド計測とバックエンド決定 — 結果

## 環境

- moon: `0.1.20260703 (6fbf8c3 2026-07-03)`
- node: `v24.18.0`
- Chrome: `149.0.0.0`（`navigator.userAgent` 実測。Claude in Chrome 拡張機能経由で自動計測）
- 計測日: 2026-07-13

## ビルド出力パス（実測。ブリーフ記載の `core/target/...` ではない）

moon 0.1.20260703 は `core/target/` ではなく `core/_build/` 配下にビルド成果物を出力する。

```
core/_build/js/release/build/bench/bench.js      # ESM, export { bench_kernel }
core/_build/wasm-gc/release/build/bench/bench.wasm  # imports なし, exports: bench_kernel_arr, frame_set, make_frame
```

`moon build --target js --release` / `moon build --target wasm-gc --release` の2回で両方生成される。

## 方法（wasm-gc の JS 境界コスト）

MoonBit 公式 FFI ドキュメント（`docs.moonbitlang.com/en/latest/language/ffi.html`）を確認した。型
対応表には「`FixedArray[Byte]`/`Bytes` は `Uint8Array` として表現される」という記述はあるが、これは
**js backend**（linear memory を持たない wasm-gc とは別の代表構成）での型対応であり、wasm-gc backend
から JS の `Uint8Array` を一括で `FixedArray[Byte]` へ転送する専用の高速パス（例:
js-string-builtins のバイト列版に相当するもの）はドキュメント上に見つからなかった。`FixedArray[T]`
（数値）は将来的に `TypedArray` へ移行予定という記述はあるが、現行版では未実装。

結論: 現状は `make_frame(len)` で `FixedArray[Byte]` を確保し、`frame_set(f, i, v)` を要素数分
呼び出す per-element 転送が唯一の手段であり、**これが wasm-gc 版の実際の境界コスト**である。
`bench/run-node.mjs` / `bench/bench.html` の計測はこの転送コストをタイマー計測区間に含めている
（本番でフレームを毎回転送する運用を想定した「現実の姿」）。

## 計測結果

計測方式: warmup 30 回 → 200 回計測 → 中央値（median）。フレームは 640x480 RGBA、
mulberry32(seed=42) で決定的生成（背景ノイズ + ファインダ様パターン3個）。

| 環境 | js backend median | wasm-gc median（境界込み） | ratio (wasm/js) | hits (両backend一致) |
|---|---|---|---|---|
| Node v24.18.0 | 7.899 ms/frame | 20.752 ms/frame | **2.63** | 1559 / 1559 |
| Chrome 149.0.0.0 | 13.100 ms/frame | 19.800 ms/frame | **1.51** | 1559 / 1559 |

両バックエンドで `hits=1559`（同一フレーム・同一アルゴリズムの整合性確認 OK。ロジックバグなし）。

幾何平均 (wasm/js) = `sqrt(2.63 × 1.51)` = **1.9928 ≈ 1.99**

## 判定

**判定基準（スペック準拠）: 幾何平均で 1.3 倍以上速い方を採用。1.3 倍未満なら js backend（配布 DX 優位）。**

幾何平均 1.99 は「wasm-gc が js より遅い」方向に 1.3 倍を大きく超えている（= js の方が幾何平均で
約1.99倍速い）。Node・Chrome 個別の ratio も両方とも 1.3 を上回っており（2.63, 1.51）、結果は一貫
している。

**決定: `js` backend を採用。**

`core/moon.mod.json` の `preferred-target` は既に `"js"` であり、変更不要（採用決定と現状設定が
一致することを確認した）。

## 再現手順

```bash
export PATH="$HOME/.moon/bin:$PATH"
cd core
moon build --target js --release
moon build --target wasm-gc --release
cd ..
node bench/run-node.mjs
# Chrome 計測:
python3 -m http.server 8000 --directory ~/moonqr
# ブラウザで http://localhost:8000/bench/bench.html を開き、body 内の出力（console にも出力）を確認
```

## 懸念・注記

- Playwright MCP の共有 Chrome プロファイル（`mcp-chrome-f3d113a`）が計測時に他プロセスにロックされて
  おり（`use --isolated to run multiple instances` エラー、3回リトライも失敗）、代わりに
  Claude in Chrome 拡張機能（ユーザーの実ブラウザ）経由で計測した。ツールは異なるが計測ロジック
  （`bench/bench.html`）自体は同一であり、計測方式・信頼性に影響はない。
- Chrome 計測は1系統・1回のみ（ブリーフの方式通り）。個体差・ブラウザ負荷状況によりブレる可能性は
  あるが、Node/Chrome 両方で ratio > 1.3 と方向が一致しており、判定を覆すほどの誤差とは考えにくい。

## 実機スキャン検証（Task 14・2026-07-14）

ユーザー実機のスマホカメラで `bench/demo.html` の6ケースを全読取: **6/6 成功**。
ケース: HELLO(M) / GitHub URL(M) / 数字10桁(L) / こんにちは世界🦑(H) / A×500(Q) / WIFI設定文字列(M)。
→ v1 Done 基準3「実機スマホスキャナで読める」を充足。


## jsQR e2eコーパスパリティ測定（Task 10・2026-07-14）

### 環境

- node: `v24.18.0`
- jsqr (npm): `1.4.0`
- jsQR移植元 pinned commit: `8e6a036beafa7053dd44b1b76ac578d22b1b3311`（P2 Task 2で固定した値と同一）
- コーパス取得元: jsQR `tests/end-to-end/`（`scripts/fetch-fixtures.mjs` で shallow clone → `fixtures/jsqr-e2e/`、gitignore対象）

### コーパス概要

- 総ケース数: **254**
- ground truth あり（output.json != null）: **214**
- ground truth なし（output.json == null、jsQR自身も読めないnegativeケース）: **40**

### 判定基準（スペック rubric 1）

自前 decode_js の成功数 ≥ jsQR (npm) の成功数。成功 = jsQR/自前の返したテキストが
output.json の `data` フィールドと**一致**すること（output.json が null のケースは
ground truth が無いため、この一致判定の分母から除外——raw success/failure のみ参考記録）。

### 結果（text-match, ground truth 214件中）

| | jsQR (npm) | 自前 (decode_js) |
|---|---|---|
| 成功数 | 214 | 214 |
| 成功率 | 100.0% | 100.0% |

**判定: 自前(214) ≥ jsQR(214) → rubric PASS**

- jsQRのみ成功（自前は不一致/失敗）: 0件 — (なし)
- 自前のみ成功（jsQRは不一致/失敗）: 0件 — (なし)
- jsQRが非null結果を返したが期待テキストと不一致: 0件 — (なし)
- 自前が非null結果を返したが期待テキストと不一致: 0件 — (なし)

### 参考: ground truth無しケース（output.json==null、40件）の raw success

rubricの分母には含めない（一致判定の基準が無いため）。jsQR自身が読めないnegativeケースに
対して非null結果を返す＝誤検出（false positive）の可能性がある、という観点でのみ参考記録。

- jsQRが非null結果を返した件数: 0 — (なし)
- 自前が非null結果を返した件数: 0 — (なし)

### 分類・対応（初回測定で判明した1件差分の修正）

初回測定（対角ミラー再試行の実装前）: 自前213 < jsQR214（`bike-1`ケースのみ差分）。
`bike-1`は実写真（約90度回転したQR）で、format/version情報の読取までは成功するが
codewords段で失敗——jsQR `decoder.ts` の `decode()` が実装する「抽出行列を対角線
(TL-BR)でミラー（転置）して再試行」（locatorのファインダtop-right/bottom-left取り違え
を補正する経路）が自前には未実装だったことが原因と特定した。

対応: `core/src/decode/decode.mbt` に `try_decode_matrix`（format/version/data
フルパイプラインの抽出）と `mirror_matrix`（対角線転置、in-place）を追加し、`scan()`
が通常抽出行列で失敗した候補に対してミラー再試行を1回行うようjsQR `decoder.ts`を
忠実移植した。再測定で自前214=jsQR214の完全一致となり、rubric達成。

whiteboxテスト `core/src/decode/decode_wbtest.mbt` で
(1) `mirror_matrix`のinvolution性（2回適用で元に戻る）、
(2) `scan()`レベルでミラー再試行が転置画像を実際に救うこと（mutation checkで
再試行を無効化すると同テストが確実に失敗することを確認済み）
の2点をピン留めした。

### 再現手順

```bash
export PATH="$HOME/.moon/bin:$PATH"
node scripts/fetch-fixtures.mjs   # 冪等: 既にfixtures/jsqr-e2e/があればスキップ
cd core && moon build --target js --release && cd ..
node --test packages/moonqr/test/jsqr-parity.test.mjs
```

## decode性能ベンチ jsQR比較（Task 11・2026-07-14）

### 環境

- node: `v24.18.0`
- moon: `moon 0.1.20260703 (6fbf8c3 2026-07-03)`
- arch: `arm64` / platform: `darwin`
- jsqr (npm): `1.4.0`
- commit: `14f6903`

### 方法

Phase 1 (`bench/run-node.mjs`) と同一方法論: WARMUP=30, ITERS=200, median。
フレームは 640x480 RGBA、2種:
- **hit**: `bench/gen-frame.mjs` のノイズ背景（seed=42）に、`encode_js`
  で生成した v2-M QR（"PERF BENCH DECODE TEST"）を `packages/moonqr/test/lib/rasterize.mjs`
  でラスタ化（scale=5, margin=4, seed=7）し、オフセンター位置 (400,180) に
  合成。計測前に jsQR・自前の両方が実際にデコードでき、テキストが一致する
  ことを検証済み。
- **miss**: `bench/gen-frame.mjs` の背景のみ（QR非合成）。計測前に両実装
  とも null を返すことを検証済み。

jsQR は `inversionAttempts` オプションで対応: 主計測は `"attemptBoth"`
（自前 `invert=true` に相当）、参考計測は `"dontInvert"`（自前
`invert=false` に相当）。

計測フェアネスの注記:
- 各イテレーションの戻り値を sink に集計・検証している（JIT のデッドコード
  除去対策。hit で sink=ITERS、miss で sink=0 になることを assert 済み）。
- 実行順序は各フレームにつき jsQR → 自前 の固定順・非インターリーブ。時間
  経過によるドリフト（サーマル・GC）は後に走る自前側に不利に働くため、
  報告される自前優位に対して保守的なバイアス（rubric 判定を甘くしない方向）。

### 結果

| frame | jsQR attemptBoth (ms) | ours invert=true (ms) | ratio (ours/jsQR) | 判定 | jsQR dontInvert (ms, 参考) | ours invert=false (ms, 参考) | ratio (参考) |
|---|---|---|---|---|---|---|---|
| hit | 78.620 | 60.122 | 0.765 | PASS | 82.788 | 63.106 | 0.762 |
| miss | 180.165 | 134.224 | 0.745 | PASS | 90.535 | 72.805 | 0.804 |

### 判定（スペック rubric 2）

**基準: 自前 median ≤ jsQR median × 1.2 が hit・miss 両フレームで成立すること。**

**判定: PASS**

## モニター格子写真対応 — マルチスケールデコード（Task 12・2026-07-14）

### 背景・症状

Task 12（実機カメラ画像ゲート）でユーザーがモニターに表示したQRをスマホで撮影した写真
（`PXL_20260714_061734707.MP.jpg`、3472x4624px）を `bench/demo.html` で読ませたところ
失敗した。紙のQR・実機スマホカメラでの直接読取は Task 14 で既に 6/6 成功しており、
「モニター表示 + 撮影」という組み合わせに固有の失敗だった。

### root cause（原因連鎖）

1. **モニターのサブピクセル格子**: 液晶/有機ELモニターの画素構造が、白いはずの背景領域に
   高周波の暗い格子模様として写真に写り込む。
2. **ブロック二値化の誤認**: jsQR方式のブロック単位二値化はこの高周波格子を「ほぼ50%
   speckle（黒白が細かく入り乱れた領域）」と誤認し、ファインダパターン（3隅の四角）を
   検出できなくなる。視覚的に確認済み。**jsQR npm（1.4.0）でも全く同一の失敗が再現する**
   ——つまり自前 `decode_js` のコア二値化・ロケータ（`core/src/decode/`）は無改修のまま
   jsQRとパリティを保っており、**コア自体は原因ではない**。
3. **素朴な単発縮小はエイリアシングで悪化する**: `sips -Z` による単一ステップの縮小を
   1600/1200/1000/800/600/400pxの各サイズで試したが、jsQR npm・自前decode_jsの**両方とも
   全サイズで失敗**した。単発の最近傍/双線形縮小は格子の高周波成分を適切にローパス
   フィルタせずエイリアシングし、むしろパターンを悪化させる。
4. **段階的な2x2ボックス平均縮小（正しいローパスフィルタ）で解決**: 縦横を2x2ブロック
   平均で段階的に半分に縮小していくと、**1/8スケール付近で jsQR npm・自前decode_jsの
   両方がデコードに成功する**（テキスト "HELLO" を正しく復元）。1/16スケールまで縮小すると
   今度はQRモジュールが小さくなりすぎてデコードに失敗する（縮小しすぎの失敗モード）。

### 対応

`bench/demo.html` の画像読取パイプラインを、単発downscale→decode の1回勝負から、
**マルチスケール再試行ループ**に置き換えた:

1. ImageDataをネイティブ解像度で取得（旧実装の「1600px超なら`drawImage`で単発縮小してから
   decode」を廃止——これが root cause 3 のエイリアシングを引き起こしていた）。
2. メモリガード: `decode_js` の16Mピクセル上限（`max_pixels = 16 * 1024 * 1024` =
   16,777,216、`core/src/decode/decode.mbt`）を超える画素数の場合、超えなくなるまで先に
   `halveRGBA`（2x2ボックス平均、純JS実装）で縮小する。この事前半減も表示スケールに
   計上する（レビュー指摘対応: 計上しないと「事前半減のおかげで初めて成功した」ケース
   ——48MP級スマホ写真 8064x6048 で日常的に発動する経路——が「無縮小成功」と誤表示
   される。>16Mピクセル入力での回帰テストを `monitor-lattice.test.mjs` に追加済み）。
3. ≤16Mの基点から `halveRGBA` で `max(width, height) >= 150` の間、半減ピラミッドを
   構築し、**画素数の少ないレベルから昇順に** `decode_js` を試行する（perf対応・
   ユーザーフィードバック「読めたが遅い」への対処）。カメラ写真は小スケールで
   デコードできることが大半（実測: ユーザー写真は1/8でのみ成功）なのに、旧実装の
   大スケール優先はネイティブ解像度の失敗試行（16Mピクセルで数秒）を毎回払っていた。
   一般的なスキャナの定石どおり安価な小スケール（~100ms）から試し、フル解像度は
   「遠く/小さく写ったQR」向けの最後の手段とする。メモリ注記: ピラミッド全レベルの
   先行構築コストは幾何級数（1 + 1/4 + 1/16 + ...）で基点画像の約1.33倍——許容範囲
   として先行構築を採用（遅延構築より単純で demo.html との手動同期が容易）。
4. 成功した総縮小率（事前半減込み）と試行順を結果表示に反映する
   （例:「読取成功（1/8スケール）」＋「試行スケール（小→大): 1/32 → 1/16 → 1/8」）。

同一ロジックを `packages/moonqr/test/lib/multiscale.mjs`（`halveRGBA` + `multiScaleDecode`）
に実装し、`bench/demo.html` と手動同期（demo.html は `bench/` から静的配信され
`packages/` 配下を import できないため）。両ファイルにこの同期の注記を残した。
**コアデコーダ（`core/src/decode/`）は一切変更していない**——修正はJS境界のリトライ
ラッパのみ。

### 回帰テスト（`packages/moonqr/test/monitor-lattice.test.mjs`）

実写真は使わず、`rasterize()` で生成したQR画像に合成のサブピクセル格子（9px周期の
格子線上にある白画素のみ 220→120 に暗化。黒画素は無改変）を重ねたフィクスチャで
失敗モードをコミット可能・決定的に再現した:

- (a) フィクスチャに対する直接 `decode_js`（単一スケール）は **FAIL**（失敗モードの再現を証明）
- (b) 同フィクスチャに対する **jsQR npm も FAIL**（コアがjsQRとパリティのままであることの証明）
- (c) `multiScaleDecode` ヘルパーは **SUCCESS**（小スケール優先の試行順では初回試行の
  1/8スケール・102pxでテキスト "HELLO" を正しく復元。大スケール優先の旧順序では
  1/2スケールで復元していた——どちらの順序でも成功する）

フィクスチャパラメータ: `scale=28`（モジュールあたり28px、写真スケール800px超）、
格子`period=9`、暗化後階調`darkenTo=120`、白判定閾値`whiteThreshold=200`。
scale×period×darkenTo の探索により、上記(a)(b)(c)の3条件を同時に満たす組み合わせとして選定。

### ユーザー実写真での検証（ローカルのみ・非コミット）

`~/Downloads/PXL_20260714_061734707.MP.jpg`（3472x4624px、`sips`で
PNG変換してNode側で検証。写真自体もfixtures/相当物もリポジトリにはコミットしていない）:

- ネイティブ解像度での直接 `decode_js`: **FAIL**
- `multiScaleDecode`: **SUCCESS** — **1/8スケール**（434x578px）でテキスト `"HELLO"` を正しく復元

perf（試行順最適化の前後比較、Node v24.18.0・3回計測の中央値）:

| 実装 | median | 試行順 |
|---|---|---|
| 大スケール優先（旧） | 5382 ms | 1/1(fail・数秒) → 1/2 → 1/4 → 1/8(成功) |
| 小スケール優先（新） | **62 ms** | 1/32(fail) → 1/16(fail) → 1/8(成功) |

約**87倍**の高速化（スマホ実機ではネイティブ解像度試行がさらに遅いため体感差はより大きい）。

Task 10/14で確認済みの「紙QR・直接読取は問題なし」を踏まえると、モニター格子写真という
Task 12で新たに発覆した失敗ケースに対して本修正が有効であることを実機写真で確認した。

### 全体テスト結果

- `moon test`（core）: **92/92 PASS**
- `node --test packages/moonqr/test/*.test.mjs`: **273/273 PASS**（既存268 + 新規
  `monitor-lattice.test.mjs` 5件。4件目は事前半減のスケール計上回帰、5件目は
  小スケール優先の試行順回帰——いずれもmutation checkで修正を打ち消すと確実に
  落ちることを確認済み）

### 再現手順

```bash
export PATH="$HOME/.moon/bin:$PATH"
cd core && moon build --target js --release && cd ..
node --test packages/moonqr/test/monitor-lattice.test.mjs
node --test packages/moonqr/test/*.test.mjs   # 全体回帰
```
