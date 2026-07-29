# moonqr Phase 2: デコーダ 実装計画

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** カメラ実用級のQRデコーダを MoonBit で実装し、jsQR の e2e 画像コーパスで jsQR 以上の読取率、フレーム処理時間 jsQR の1.2倍以内を達成する。

**Architecture:** `core/src/decode/` に6段パイプライン（二値化→ファインダ検出→透視変換→サンプリング→フォーマット復号→データ復号）。アルゴリズムは jsQR（Apache-2.0、帰属表示）を参照実装として移植し、gf256（RS復号）と encode（テーブル・format_bits/version_bits）を再利用する。テストは「自前エンコーダ＋JSラスタライザによるラウンドトリップ」と「jsQR e2e コーパスとのパリティ測定」の二本立て。

**Tech Stack:** MoonBit（js backend 確定済み）、Node 24 + pnpm、devDeps: `jsqr`（パリティ比較対象）, `pngjs`（fixture PNG読取）。

**コード規定方式（Plan 1 との違い）:** 本計画の移植タスクは、**jsQR のソースファイル・関数名をコード仕様の正本として指定**する（承認済みアプローチA）。計画には完全な MoonBit 公開シグネチャ・完全なテストコード・移植規約・既知の落とし穴を記載し、アルゴリズム本体は jsQR の該当関数から移植する。実装者は https://github.com/cozmo/jsQR の `src/` を読むこと。

## Global Constraints

- リポジトリ: `/Users/nishikawa/projects/naoto24kawa/moonqr`（main からブランチ `phase2-decoder` を切る）
- `export PATH="$HOME/.moon/bin:$PATH"`; テストは `core/` で `moon test --target js`。ビルド出力は `core/_build/`
- jsQR は Apache-2.0。**最初の移植タスク（Task 3）で `NOTICE` ファイルを作成**し「Portions derived from jsQR (https://github.com/cozmo/jsQR), Copyright (c) 2016 Cosmo Wolfe, Apache License 2.0」を記載。qrcode-generator (MIT) 由来のテーブルについても同ファイルに記載
- jsQR の参照は **commit を固定**: 最初に jsQR を clone する Task で `git rev-parse HEAD` を記録し、以降の全タスク・fixtureスクリプトで同じ commit を参照する（レビュー指摘: unpinned master はドリフトする）
- MoonBit 規約: 幾何・輝度計算は `Double`、インデックスは `Int`。TS の `null` → `Option`。TS の nested function → パッケージ内 private fn。enum の外部構築は `pub(all)`。新規コードは `!x`（`not(x)` 禁止）。メソッドは `Type::method`
- 各段の失敗は `None` で上に伝播。例外は契約違反のみ（decode_js は total にする — 範囲外入力も `""` を返す）
- 読取失敗はエラーではない（フレーム単位の正常系）
- コミットメッセージ末尾: `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`
- **テストの assert を弱めて通すのは禁止**（anti-gaming）。期待値が誤りと思われる場合は導出を示して差し戻す

## File Structure

```
core/src/decode/
├── moon.pkg.json      # import: gf256, encode
├── bitmatrix.mbt      # BitMatrix（デコーダ用ビット行列）+ Point
├── binarize.mbt       # グレースケール + jsQR方式適応二値化
├── locator.mbt        # ファインダ/アライメント検出（jsQR locator 移植）
├── extractor.mbt      # 透視変換 + グリッドサンプリング（jsQR extractor 移植）
├── info.mbt           # フォーマット/バージョン情報復号（encode の bits 関数を真値表に）
├── codewords.mbt      # ジグザグ読出 + デインターリーブ + RS訂正
├── data.mbt           # セグメント復号（numeric/alnum/byte/kanji/ECI）
├── sjis.mbt           # Shift-JIS→Unicode 表（スクリプト生成）
└── decode.mbt         # decode() façade + decode_js
scripts/
├── gen-sjis.mjs       # jsQR の shiftJISTable から sjis.mbt を生成
└── fetch-fixtures.mjs # jsQR e2e コーパス取得（pinned commit・fixtures/ は gitignore）
packages/moonqr/test/
├── lib/rasterize.mjs  # 行列→RGBA ラスタライザ（scale/margin/回転/透視/ノイズ）
├── version-sweep.test.mjs   # Task 1: 40×4 qrcode npm パリティ
├── roundtrip.test.mjs       # encode→rasterize→decode
└── jsqr-parity.test.mjs     # コーパス読取率 + 性能比較
```

---

### Task 1: 引き継ぎ事項の処理（バージョンスイープ＋コメント修正）

**Files:**
- Create: `packages/moonqr/test/version-sweep.test.mjs`
- Modify: `core/src/gf256/rs_decode.mbt`（コメント2箇所）, `core/src/encode/format.mbt:59`（コメント1箇所）, `scripts/gen-tables.mjs`（SOURCE_URL を commit SHA 固定）

**Interfaces:**
- Consumes: `encode_js(text, ec, version)`（Phase 1）
- Produces: v1..40 × L/M/Q/H 全160組の qrcode npm 行列一致の実証（Phase 1 最終レビュー Important #1 の解消）

- [ ] **Step 1: バージョンスイープテストを書く**

`packages/moonqr/test/version-sweep.test.mjs`:
```js
import { test } from "node:test";
import assert from "node:assert";
import QRCode from "qrcode";

const mod = await import("../../core/_build/js/release/build/encode/encode.js");
const EC = { L: 0, M: 1, Q: 2, H: 3 };

// マスクも強制して全行列を厳密比較する（readMask 不要の決定的比較）
for (let version = 1; version <= 40; version++) {
  for (const ec of ["L", "M", "Q", "H"]) {
    test(`sweep v${version}-${ec}`, () => {
      const text = `V${version}${ec}`; // 短いテキスト（全バージョンに収まる）
      const ref = QRCode.create(text, {
        errorCorrectionLevel: ec, version, maskPattern: 3,
      });
      const flat = mod.encode_js(text, EC[ec], version);
      assert.notEqual(flat.length, 0);
      const size = ref.modules.size;
      assert.equal(flat[0], size);
      // 自前はマスク自動選択のため、mask 3 を選ぶとは限らない。
      // → データ・EC・機能パターンの一致は「マスク一致時のみ全比較」では
      //   160組で保証できないので、ここでは encode_js に version を強制した上で
      //   qrcode npm 側を「自前が選んだマスク」に合わせて再生成して全比較する。
      const ourMask = readMask(flat);
      const ref2 = QRCode.create(text, {
        errorCorrectionLevel: ec, version, maskPattern: ourMask,
      });
      for (let y = 0; y < size; y++) for (let x = 0; x < size; x++) {
        assert.equal(flat[1 + y * size + x], ref2.modules.get(y, x) ? 1 : 0,
          `v${version}-${ec} mismatch at (${x},${y}) ourMask=${ourMask}`);
      }
    });
  }
}

function readMask(flat) {
  const size = flat[0];
  const get = (x, y) => flat[1 + y * size + x];
  const coords = [
    [8, 0], [8, 1], [8, 2], [8, 3], [8, 4], [8, 5], [8, 7], [8, 8],
    [7, 8], [5, 8], [4, 8], [3, 8], [2, 8], [1, 8], [0, 8],
  ];
  let bits = 0;
  coords.forEach(([x, y], i) => { bits |= get(x, y) << i; });
  return ((bits ^ 0x5412) >> 10) & 0b111;
}
```

Run: `cd packages/moonqr && node --test test/version-sweep.test.mjs`
Expected: 160/160 PASS。失敗があれば該当 (version, ec) を最小再現して原因特定（表の抽出ミスか配置バグ）— **これが出たら本タスクで修正してから先へ進む**。

- [ ] **Step 2: コメント修正**

`core/src/gf256/rs_decode.mbt`: `find_error_locator` のヘッダコメント「σ(x)（index 0 = 定数項 1）」→「σ(x)（index 0 = 最高次。定数項 1 は末尾要素）」。`correct_errors` 内の「deriv は x で1次下げた多項式として評価する（下の eval で x^2 刻みに対応）」→「deriv は σ の形式微分（GF(2^8) では偶数次項が消える）。plain Horner で x_inv を評価する」。

`core/src/encode/format.mbt:59` 付近: 「（bit14 が先頭）」→「（get_bit(0)=LSB が先頭セル (8,0) に入る。bit14 は 15bit 整数の最上位）」。

`scripts/gen-tables.mjs`: fetch URL の `master` を、実際に取得した時点の commit SHA に置換（`git ls-remote https://github.com/kazuhikoarase/qrcode-generator HEAD` で取得し、`https://raw.githubusercontent.com/kazuhikoarase/qrcode-generator/<SHA>/js/dist/qrcode.js` 形式へ）。再生成して tables.mbt に差分が出ないことを確認（`git diff --stat core/src/encode/tables.mbt` が空）。

- [ ] **Step 3: 全suite確認・コミット**

`moon test --target js`（41/41）+ 既存 parity（65/65）+ 新規 sweep（160/160）。

```bash
git add -A && git commit -m "test(encode): 40x4バージョンスイープパリティと引き継ぎコメント修正"
```

---

### Task 2: decode パッケージ雛形 — BitMatrix と二値化

**Files:**
- Create: `core/src/decode/moon.pkg.json`, `core/src/decode/bitmatrix.mbt`, `core/src/decode/binarize.mbt`
- Test: `core/src/decode/bitmatrix_test.mbt`, `core/src/decode/binarize_test.mbt`

**移植元（コード仕様の正本）:** jsQR `src/BitMatrix.ts`, `src/binarizer/index.ts`（binarize 関数。BLOCK_SIZE=8, MIN_DYNAMIC_RANGE=24, 低分散ブロックは左・上の近傍しきい値を継承する方式 — Phase 1 Task 2 レビューで特定した「3x3平均の盲点」への正式な解）

**Interfaces（Produces）:**
```moonbit
pub(all) struct Point { x : Double; y : Double }
pub struct BitMatrix { width : Int; height : Int; ... }
pub fn BitMatrix::make(width : Int, height : Int) -> BitMatrix
pub fn BitMatrix::get(self, x : Int, y : Int) -> Bool   // 範囲外は false
pub fn BitMatrix::set(self, x : Int, y : Int, v : Bool) -> Unit
///| RGBA → 二値行列。返り値 (binarized, inverted)。
///| jsQR 同様、反転版も同時生成する（invertAttempts 用）
pub fn binarize(data : Bytes, width : Int, height : Int) -> (BitMatrix, BitMatrix)
```

- [ ] **Step 1: テストを書く（RED）**

`bitmatrix_test.mbt`: make→全false / set→get 往復 / 範囲外 get は false（クラッシュしない）。
`binarize_test.mbt`: Phase 1 の bench カーネルと同型の合成フレーム（8pxモジュールのファインダ様パターン＋位置依存ノイズ背景。**一様fixture禁止**）で、パターン中心の黒モジュール座標が true・白モジュール座標が false・**中心ブロック（24x24一様領域の内側）も正しく黒**になることをアサート（Phase 1 の盲点の回帰テスト）。反転行列は同座標で論理反転していること。

- [ ] **Step 2: 実装（jsQR binarizer 移植）→ GREEN**

移植規約: `UInt8ClampedArray` ベースの Matrix → `FixedArray[Int]`。輝度は jsQR と同じ係数（0.2126R+0.7152G+0.0722B、jsQR の実装値に従う）。ブロック平均→低分散判定（max-min ≤ 24 なら「左と上のブロックしきい値の平均/2 系の継承規則」— jsQR の実装をそのまま）→ 5x5 近傍ブロック平均でしきい値化（jsQR の threshold 計算に従う）。

`core/src/decode/moon.pkg.json`:
```json
{
  "import": [
    { "path": "naoto24kawa/moonqr/gf256", "alias": "gf256" },
    { "path": "naoto24kawa/moonqr/encode", "alias": "encode" }
  ]
}
```

- [ ] **Step 3: 全suite・コミット** — `feat(decode): BitMatrixとjsQR方式二値化`

---

### Task 3: ファインダ/アライメント検出（locator 移植）＋ NOTICE

**Files:**
- Create: `core/src/decode/locator.mbt`, `NOTICE`
- Test: `core/src/decode/locator_test.mbt`

**移植元:** jsQR `src/locator/index.ts` の `locate(matrix)` 一式（Quad 検出、1:1:3:1:1 スキャン、`scorePattern`、`recenterLocation`、alignment 探索は `locateAlignmentPattern`）。返り値の形（topLeft/topRight/bottomLeft/alignment/dimension 相当）も踏襲する。

**Interfaces（Produces）:**
```moonbit
pub struct QrLocation {
  top_left : Point
  top_right : Point
  bottom_left : Point
  alignment : Point
  dimension : Int          // モジュール数（size）
  module_size : Double
}
///| 候補を最大2件返す（jsQR 同様、通常QRと「ミラー疑い」等の順位付け）
pub fn locate(matrix : BitMatrix) -> Array[QrLocation]
```

- [ ] **Step 1: テストを書く（RED）**

自前エンコーダを真値生成器に使う: `@encode.encode("LOCATOR TEST", @encode.EcLevel::M, Some(2))` → 行列 → **MoonBit 内でピクセル化**（1モジュール=4px、余白16px、黒=false側に注意して BitMatrix へ直接展開 — ラスタライズは二値行列への直接変換でよい、二値化はスキップ）→ `locate` が1件以上返し、`dimension == 25`、`top_left/top_right/bottom_left` が各ファインダ中心の理論座標（(16+3.5*4 ± 2px) 等、モジュール(3.5,3.5)/(21.5,3.5)/(3.5,21.5) の px 換算）に ±(module_size) 以内で一致することをアサート。90度回転させた行列でも locate が成功すること（座標対応は回転を考慮してアサート）。

- [ ] **Step 2: 実装（移植）→ GREEN**

落とし穴: jsQR の locate は Float 座標の重心クラスタリングを使う。`Math.abs`→`Double::abs`、ソートはスコア降順。MoonBit に `Array::sort_by` 系があるか確認し、なければ挿入ソートを書く（要素数は数個）。**移植したファイル冒頭に出典コメント**（jsQR locator/index.ts, commit SHA）を付ける。

`NOTICE` 作成（Global Constraints 記載の文言＋qrcode-generator の帰属）。

- [ ] **Step 3: 全suite・コミット** — `feat(decode): ファインダ検出（jsQR locator移植）+ NOTICE`

---

### Task 4: 透視変換とグリッドサンプリング（extractor 移植）

**Files:**
- Create: `core/src/decode/extractor.mbt`
- Test: `core/src/decode/extractor_test.mbt`

**移植元:** jsQR `src/extractor/index.ts`（`extract(image, location)`。中身は zxing 系 `PerspectiveTransform`: `quadrilateralToQuadrilateral`, `squareToQuadrilateral`, `times`）。

**Interfaces（Produces）:**
```moonbit
pub struct ExtractResult {
  matrix : BitMatrix                    // dimension x dimension のモジュール行列
  mapping : (Double, Double) -> Point   // モジュール座標→元画像px（corners 出力用）
}
pub fn extract(image : BitMatrix, location : QrLocation) -> ExtractResult
```

- [ ] **Step 1: テストを書く（RED）**

①恒等系: Task 3 と同じ「エンコード→px展開」画像に locate→extract をかけ、**得られたモジュール行列が元のエンコード行列と全セル一致**（これが decode 前半パイプラインの結合テスト）。②透視系: 同じQRを JS 側でなく MoonBit テスト内で簡易射影（4隅を (0,0),(W,0),(0,H),(W,H)→少し歪めた四角形へ、逆写像で最近傍サンプル）した画像でも extract 後の行列が元と一致（歪み小: 各隅±10%以内）。

- [ ] **Step 2: 実装（移植）→ GREEN** — 3x3 行列は `FixedArray[Double]`(9要素) で。

- [ ] **Step 3: 全suite・コミット** — `feat(decode): 透視変換とグリッドサンプリング（jsQR extractor移植）`

---

### Task 5: フォーマット/バージョン情報の復号

**Files:**
- Create: `core/src/decode/info.mbt`
- Test: `core/src/decode/info_test.mbt`

**移植元:** jsQR `src/decoder/decoder.ts` の `readFormatInformation` / `readVersion`（有効コード全列挙とのハミング距離最小・許容誤り ≤3(format)/≤3(version) 方式）。**ただし有効コード表は移植せず、encode パッケージの `format_bits(ec, mask)` / `version_bits(v)` を列挙に使う**（実装が既にあり qrcode npm と一致実証済み — これが真値表）。

**Interfaces（Produces）:**
```moonbit
pub struct FormatInfo { ec : @encode.EcLevel; mask : Int }
///| 15bit 生読取値（2系統それぞれ）から最尤フォーマットを返す。距離>3 は None
pub fn decode_format(bits1 : Int, bits2 : Int) -> FormatInfo?
///| 18bit 生読取値から最尤バージョン(7..40)。距離>3 は None
pub fn decode_version(bits1 : Int, bits2 : Int) -> Int?
///| 行列からフォーマット/バージョンのビットを読み出す（座標は encode の place_* と鏡映）
pub fn read_format_bits(m : BitMatrix) -> (Int, Int)
pub fn read_version_bits(m : BitMatrix) -> (Int, Int)
```

- [ ] **Step 1: テストを書く（RED）**

①全32組 (ec 4 × mask 8): `decode_format(format_bits(ec,mask), 同)` が (ec,mask) を返す。②1〜3bit 破壊しても復元、4bit 破壊で None（境界）。③version 7..40 同様（version_bits、3bit 破壊まで復元）。④結合: `@encode.encode("INFO", ..., Some(7))` の行列を BitMatrix 化し read_format_bits/read_version_bits → decode が エンコード時の (ec, mask, version) と一致。

- [ ] **Step 2: 実装 → GREEN**（ハミング距離は XOR + popcount ループ）
- [ ] **Step 3: 全suite・コミット** — `feat(decode): フォーマット/バージョン情報復号（encodeを真値表に）`

---

### Task 6: コードワード読出とRS訂正

**Files:**
- Create: `core/src/decode/codewords.mbt`
- Test: `core/src/decode/codewords_test.mbt`

**移植元:** 独自実装でよい（encode の `place_data` の逆操作 ＋ `rs_blocks` でデインターリーブ ＋ `@gf256.rs_decode`）。jsQR `decoder.ts` の `readCodewords`/`dataBlocks` は突合参照。

**Interfaces（Produces）:**
```moonbit
///| マスク解除→ジグザグ読出→デインターリーブ→ブロック毎RS訂正→データバイト列。
///| 訂正不能ブロックがあれば None
pub fn read_data(m : BitMatrix, version : Int, fmt : FormatInfo) -> Array[Int]?
```

- [ ] **Step 1: テストを書く（RED）**

①ラウンドトリップ: `@encode.encode` の行列（v1-M, v5-H, v7-L）→ BitMatrix → read_data が、encode 側 `assemble` 前の**データコードワード（パディング込み）と完全一致**。v5-H は多ブロックデインターリーブの検証。②誤り訂正: v1-M の行列のデータ領域モジュールを疑似乱数で数bit反転（訂正能力内: ≤4バイト相当）→ read_data が元データと一致。③訂正能力超過の破壊 → None。

（データコードワード期待値の取得: テスト内で `@encode` の BitWriter+write_segment+assemble を同条件で呼び、その先頭 `data_capacity` 個と比較する）

- [ ] **Step 2: 実装 → GREEN**

落とし穴: 機能パターン領域の判定は encode の `Matrix`/`is_function` と同じ規則を decode 側で再構成する必要がある（BitMatrix には function 情報がない）。`@encode.Matrix::new(version)` + `place_function_patterns` + `place_version` を「機能領域マップ」として使い回すのが最短で、encode との規則ドリフトも構造的に防げる — この方法を採ること。

- [ ] **Step 3: 全suite・コミット** — `feat(decode): コードワード読出とRS訂正`

---

### Task 7: セグメント復号（numeric/alnum/byte/kanji/ECI）＋ SJIS 表

**Files:**
- Create: `scripts/gen-sjis.mjs`, `core/src/decode/sjis.mbt`（生成）, `core/src/decode/data.mbt`
- Test: `core/src/decode/data_test.mbt`

**移植元:** jsQR `src/decoder/decodeData/index.ts`（BitStream 読み、モード分岐、ECI）と `shiftJISTable.ts`（→ gen-sjis.mjs で mbt 化。qrcode-generator 表と同様に do-not-hand-edit ヘッダ＋出典）。

**Interfaces（Produces）:**
```moonbit
pub struct DecodedData { text : String; bytes : Array[Int] }
///| データコードワード列 → テキスト。ECI は UTF-8(26) のみ対応、他は byte を UTF-8 として解釈
pub fn decode_data(codewords : Array[Int], version : Int) -> DecodedData?
```

- [ ] **Step 1: テストを書く（RED）**

自前エンコーダとのラウンドトリップ: "0123456789"(numeric) / "HELLO WORLD $%"(alnum) / "héllo, wörld! 🦑"(byte UTF-8) を encode→read_data 相当のコードワード（Task 6 と同じ方法で取得）→ decode_data → 元テキストと一致。漢字モードは自前エンコーダが生成しないため、**手組みのコードワード**でテスト: モード1000 + CCI + 既知の漢字2文字（例: 「点茗」— jsQR/thonky の古典例のSJIS値を使い、期待Unicodeと突合）→ decode_data が正しく復元。UTF-8 バイトモードの多バイト・絵文字も往復。

- [ ] **Step 2: 実装 → GREEN**（BitReader は encode の BitWriter の鏡映として decode 側に private 実装）
- [ ] **Step 3: 全suite・コミット** — `feat(decode): セグメント復号とSJIS表`

---

### Task 8: decode() façade と decode_js

**Files:**
- Create: `core/src/decode/decode.mbt`
- Modify: `core/src/decode/moon.pkg.json`（js link exports 追加）
- Test: `core/src/decode/decode_test.mbt`

**Interfaces（Produces）:**
```moonbit
pub struct DecodeResult {
  text : String
  bytes : Array[Int]
  version : Int
  ec : @encode.EcLevel
  corners : Array[Point]   // 4隅（TL,TR,BR,BL 順、元画像px）
}
///| RGBA ピクセル → 復号結果。invert=true なら反転行列でも試行
pub fn decode(data : Bytes, width : Int, height : Int, invert : Bool) -> DecodeResult?
///| JS境界（total）: 成功時 JSON 文字列、失敗・不正入力は ""
pub fn decode_js(data : Bytes, width : Int, height : Int, invert : Bool) -> String
```

- [ ] **Step 1: テストを書く（RED）**

パイプライン全結合: `@encode.encode("FULL PIPELINE", M, None)` → px展開（1mod=4px, 余白16px, グレースケール値 黒30/白220 の RGBA `Bytes` を組み立て）→ `decode` → text 一致・version/ec 一致・corners が4点で妥当な座標範囲。反転画像（黒白入替え）→ invert=true でのみ成功。`data.length != w*h*4` → decode_js が ""（例外を出さない）。ゴミ画像（ノイズのみ）→ None / ""。

- [ ] **Step 2: 実装 → GREEN**

decode の流れ: binarize → locate（候補順に）→ extract → read_format_bits→decode_format（失敗時は jsQR 同様ミラー/再試行はまず素直に候補ループのみ）→ version（dimension から算出、v7+ は decode_version で照合）→ read_data → decode_data → DecodeResult。invert=true なら反転行列で同じループをもう1周。JSON 生成は moonbitlang/core の json パッケージ（`@json`）を確認して使う。無ければ手組み（text のエスケープは `\\` `"` 制御文字のみで可）。

moon.pkg.json に `"link": { "js": { "exports": ["decode_js"], "format": "esm" } }` を追加。

- [ ] **Step 3: 全suite・コミット** — `feat(decode): decode façadeとJS境界`

---

### Task 9: JSラスタライザとラウンドトリップ統合テスト

**Files:**
- Create: `packages/moonqr/test/lib/rasterize.mjs`, `packages/moonqr/test/roundtrip.test.mjs`

**Interfaces:**
- Produces: `rasterize(flat, {scale, margin, rotate, perspective, noise, seed}) -> {data: Uint8Array, width, height}`（純JS、canvas不使用。回転は90度単位＋任意角、透視は4隅オフセット、ノイズは seeded PRNG — **Date.now/Math.random 直接使用禁止、mulberry32 を Phase 1 bench から流用**）

- [ ] **Step 1: ラスタライザ実装＋自己テスト**（flat行列→スケール展開が正しいことを1ケース手検証）

- [ ] **Step 2: ラウンドトリップテスト**

`roundtrip.test.mjs`: `encode_js` → `rasterize` → `decode_js` で:
- 全 EC × version {1, 2, 5, 7, 10, 20, 40}（28組）× クリーン（scale 4）→ 全成功・テキスト一致
- v2-M × 回転 {90, 180, 270, 5度, -7度} → 成功
- v2-M × 透視歪み（各隅±8%）→ 成功
- v2-M × ガウスっぽいノイズ（振幅±30、seed固定）→ 成功
- v2-M × 反転色 → invert=true で成功

Expected: 全PASS。失敗ケースはどの段で None になったか切り分けて修正（decode_js に段階情報は無いので、MoonBit 側の decode_test に最小再現を移して調査）。回転・透視・ノイズは**カメラ実用級の中核**なのでここで妥協しない。

- [ ] **Step 3: 全suite・コミット** — `test(decode): ラスタライザとラウンドトリップ統合`

---

### Task 10: jsQR e2e コーパスでのパリティ測定

**Files:**
- Create: `scripts/fetch-fixtures.mjs`, `packages/moonqr/test/jsqr-parity.test.mjs`
- Modify: `.gitignore`（`fixtures/`）, `package.json`（devDeps: jsqr, pngjs）

- [ ] **Step 1: fixture 取得スクリプト**

`fetch-fixtures.mjs`: jsQR リポジトリを Task 3 で固定した commit で shallow clone（scratch）→ `tests/end-to-end/`（~187フォルダ、各 input.png + output.json）を `fixtures/jsqr-e2e/` へコピー → フォルダ数とファイル存在を検証して報告。fixtures/ は gitignore（再取得可能・リポジトリ肥大回避）。

- [ ] **Step 2: パリティハーネス**

`jsqr-parity.test.mjs`（node --test だが実体は測定レポート）: 各ケースの input.png を pngjs で RGBA 化 → ①`jsqr` npm ②自前 `decode_js` の両方に投入 → 成功数を集計。**合格基準（スペック rubric 1）: 自前の成功数 ≥ jsQR の成功数**。結果は `bench/RESULT.md` に追記（総数・両者の成功数・自前のみ失敗したケース番号一覧・jsQRのみ失敗したケース番号一覧）。
補足: jsQR の output.json が null（jsQR 自身が読めない negative ケース）も存在する — 分母の扱いは「jsQR が読めたケースのうち自前も読めた数」と「自前のみ読めた数」を両方記録し、rubric は成功総数で比較する。

Expected: 基準未達なら、自前のみ失敗するケースを頻度順に調査（大半は binarizer/locator のパラメータ差）。**基準達成までこのタスクは完了にしない**（rubric が正本）。ただし2セッション相当（fix試行 ~10回）超えて未達なら、差分ケースの分類レポートを添えてエスカレーション。

- [ ] **Step 3: 全suite・RESULT.md追記・コミット** — `test(decode): jsQR e2eコーパスパリティ測定`

---

### Task 11: 性能測定（rubric 2）

**Files:**
- Create: `bench/decode-bench.mjs`
- Modify: `bench/RESULT.md`

- [ ] **Step 1: ベンチ実装**: Phase 1 の gen-frame.mjs に QR を合成した 640x480 フレーム（読取成功するもの＋QRなしフレームの2種）で、jsqr npm と自前 decode_js の median ms/frame を測定（WARMUP 30 / ITERS 200、Phase 1 と同一方法論）。
- [ ] **Step 2: 判定**: **自前 ≤ jsQR × 1.2 が合格（rubric 2）**。未達なら hot path をプロファイル（node --cpu-prof）して最適化（優先: binarize のアロケーション、locator のスキャン）。達成まで完了にしない（エスカレーション条件は Task 10 と同じ）。
- [ ] **Step 3: RESULT.md 追記・コミット** — `perf(decode): jsQR比較ベンチ`

---

### Task 12: 人力ゲート — 実機カメラ画像での読取確認

- [ ] **Step 1**: `bench/demo.html` に「画像ファイルを選択して decode_js に投入し結果表示」する入力を追加（`<input type=file>` → ImageBitmap → OffscreenCanvas → getImageData）。
- [ ] **Step 2**: ユーザーに依頼: スマホで紙/画面のQRを**斜め・暗め含めて数枚撮影**し、そのファイルをデモページで読ませて成否を報告してもらう。全滅・大半失敗なら Task 10 の分類に戻る。
- [ ] **Step 3**: 結果を RESULT.md に記録、`git tag phase2` を打つ（**ブランチ名と異なるタグ名** — URISK-065）。コミット — `feat: Phase 2 完了 — デコーダ実機検証`

---

## 完了チェック（Phase 2 の Done 判定 = スペック rubric 1・2）

- [x] jsQR e2e コーパス: 自前成功数 ≥ jsQR 成功数 — **214 == 214**（254件中、否定40件は偽陽性0をアサート固定。RESULT.md Task 10 節・jsqr-parity.test.mjs）
- [x] 640x480 フレーム: 自前 ≤ jsQR×1.2 — **hit 0.765 / miss 0.745**（RESULT.md Task 11 節・decode-bench.mjs）
- [x] roundtrip: 全EC×7バージョン＋回転(90/180/270/±斜め)・透視・ノイズ・反転 全PASS（roundtrip.test.mjs 42件、ジオメトリピン付き）
- [x] moon test 92/92 / node --test 273/273 全緑、NOTICE 帰属完備（jsQR Apache-2.0 / qrcode-generator MIT）
- [x] 実機カメラ画像ゲート通過（ユーザー実機写真で成功。初回失敗→モニター格子×エイリアシング縮小を根本解決、マルチスケール小スケール優先で87x高速化。RESULT.md Task 12 節）

## Plan 3 への引き継ぎ

- decode_js の JSON 契約（Plan 3 の TS ラッパが型を貼る）
- Phase 1 最終レビューの「Plan 3 で必須」リスト（encode_js range check / to_svg_string export 判断 / encode("") 仕様 / THIRD_PARTY は本 Plan の NOTICE で一部先行対応）
- **Phase 2 最終レビューからの追加引き継ぎ（2026-07-14）:**
  - `@moonqr/scanner` にマルチスケールデコード（小スケール優先・逐次2x2半減）を正式実装（demo.html/multiscale.mjs の同期重複を解消し1実装に）＋同期の機械ガード（それまでの間は文字列比較テスト）
  - unknown-mode 後の復帰成功・kanji-miss→U+0000・alnum範囲外→None のセグメント復号テスト追加
  - THIRD_PARTY_LICENSES（MIT 全文含む）
  - RESULT.md の再生成ポリシー決定（冪等マーカーは結果変化時に古い記録が残る）
  - 受容済み逸脱（ACCEPTED_RISKS）: dimension整合ガード（jsQRより厳格・パニック回避）/ binarizer末尾ブロッククランプ — 双方コード内文書化済み・254件コーパスで無影響実証
