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
