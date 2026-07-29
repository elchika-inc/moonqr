# moonqr Phase 3: npm パッケージング・scanner・公開 実装計画

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** MoonBit 製の encode/decode を、TypeScript 型定義付きの npm パッケージ `@elchika-inc/moonqr`（純粋関数）と `@elchika-inc/moonqr-scanner`（カメラ統合）として出荷可能にし、mooncakes.io・GitHub Pages デモとともに公開する。

**Architecture:** MoonBit の js backend 出力（`encode_js` / `decode_js`）を薄い TS ラッパで包み、慣用的な API（`encode` / `decode` / `toSvgString` / `QrScanner`）として公開する。ビルドは tsup（esbuild）で ESM 主・CJS 併（Node テスト用）、型は手書き `.d.ts`（MoonBit 生成の `.d.ts` は `MoonBit.Bytes` 等の内部型を露出するため公開 API には使わない）。scanner は Web Worker 上で core を回し、Phase 2 で実証したマルチスケール（小スケール優先）を正式実装する。

**Tech Stack:** MoonBit（js backend）、TypeScript、tsup、Vitest（ラッパの単体テスト）、Playwright（scanner の E2E・fake camera）、pnpm workspace、GitHub Actions（CI + Pages）。

## Global Constraints

- リポジトリ: `/Users/nishikawa/projects/naoto24kawa/moonqr`（main からブランチ `phase3-packaging` を切る）
- `export PATH="$HOME/.moon/bin:$PATH"`。MoonBit ビルド: `cd core && moon build --target js --release`（出力 `core/_build/js/release/build/{encode,decode}/*.js`）。**`moon fmt` は実行禁止**（ツールチェイン版差でリポジトリ全体の設定ファイル移行が走る）
- コア（`core/src/`）の**アルゴリズムは変更しない**。JS 境界の堅牢化（range check 等、下記 Task 2）のみ許可し、変更したら moon suite（92/92）と node suite が緑であることを毎回確認する
- npm 名: **`@elchika-inc/moonqr` / `@elchika-inc/moonqr-scanner`**（既存 org `@elchika-inc` を使用。2026-07-14 時点で両名とも空き確認済み。**`npm login` はユーザーが行う** — Claude は認証情報を扱わない）
- パッケージ内部の相互参照（scanner → core）は `@elchika-inc/moonqr` を `workspace:*` で依存する
- **公開（npm publish / mooncakes publish / Pages 公開）は不可逆な外向き操作。実行前に必ずユーザーの明示承認を得る**（Task 10 の human-gate）。ドライラン（`npm publish --dry-run` / `moon publish --dry-run` 相当）までは自動で進めてよい
- 公開 API はブラウザ・Node 両対応。`moonqr` 本体は DOM 非依存（`toCanvas` 等 DOM 依存物は `@elchika-inc/moonqr/dom` サブパスに分離）
- ライセンス: Apache-2.0。`NOTICE`（既存）に加え `THIRD_PARTY_LICENSES`（jsQR Apache-2.0 / qrcode-generator MIT の全文）を同梱し、両パッケージの `files` に含める
- コミットメッセージ末尾: `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`
- 各タスク完了時に全 suite 緑（moon 92/92 + 既存 node 273 + 新規）

## 前フェーズからの引き継ぎ（本 Plan で消化する）

- **JS 境界の total 化**: `encode_js` の version/ec 範囲外で `abort`（JS 例外）→ 契約通り空配列に（Task 2）
- `write_segment` の alnum 不正文字ガード / `mask_bit` の範囲外ガード（Task 2）
- `to_svg_string` の js export 判断（Task 2 で export、TS 側から使う）
- `encode("")` の仕様明示（Task 2: 空文字は `null` を返す＝`qrcode` npm の throw 相当を Option 化）
- THIRD_PARTY_LICENSES（Task 1）
- demo.html/multiscale.mjs の同期重複 → scanner 実装へ一本化（Task 5・6）
- セグメント復号の追加テスト（unknown-mode 復帰 / kanji-miss / alnum 範囲外）（Task 2）
- RESULT.md 再生成ポリシー（Task 9 で決定・記載）

## File Structure

```
packages/
├── moonqr/                      # npm: @elchika-inc/moonqr（現在はパリティテスト置き場 → 本物のパッケージへ昇格）
│   ├── package.json             # name: moonqr, exports: "." / "./dom"
│   ├── tsup.config.ts
│   ├── src/
│   │   ├── index.ts             # encode / decode / toSvgString / 型
│   │   ├── types.ts             # DecodeResult, EncodeOptions, EcLevel, QrMatrix
│   │   ├── wasm-shim.ts         # ← 不要（js backend のため）。代わりに:
│   │   ├── core.ts              # MoonBit 生成 JS の import と薄い正規化（内部専用）
│   │   └── dom.ts               # toCanvas（moonqr/dom）
│   ├── test/                    # 既存の parity/roundtrip/sweep/lattice テストはここに残す
│   └── README.md
└── scanner/                     # npm: @elchika-inc/moonqr-scanner
    ├── package.json
    ├── tsup.config.ts
    ├── src/
    │   ├── index.ts             # QrScanner クラス
    │   ├── worker.ts            # Worker エントリ（decode をオフロード）
    │   ├── multiscale.ts        # 小スケール優先マルチスケール（Phase 2 の知見を正式実装）
    │   └── camera.ts            # getUserMedia / video / frame grab
    ├── test/
    └── README.md
docs/                            # GitHub Pages 用デモ（bench/demo.html を昇格）
├── index.html
└── assets/
.github/workflows/
├── ci.yml                       # moon build+test / node test / lint / build packages
└── pages.yml                    # docs/ を Pages へデプロイ
THIRD_PARTY_LICENSES
```

---

### Task 1: ワークスペース再編と THIRD_PARTY_LICENSES

**Files:**
- Create: `THIRD_PARTY_LICENSES`, `packages/scanner/`（雛形）
- Modify: `packages/moonqr/package.json`（`moonqr-parity-test` → `moonqr`・private 解除は Task 8 で）, `pnpm-workspace.yaml`（既に `packages/*` を含むので変更不要の確認）

**Interfaces:**
- Produces: 以降のタスクが載るディレクトリ構造とライセンス同梱物

- [ ] **Step 1: THIRD_PARTY_LICENSES を作成**

内容: ①jsQR (https://github.com/cozmo/jsQR, Copyright (c) 2016 Cosmo Wolfe) — Apache License 2.0 全文 ②qrcode-generator (https://github.com/kazuhikoarase/qrcode-generator, Copyright (c) 2009 Kazuhiko Arase) — MIT License 全文。各エントリに「何が派生か」を1行（jsQR: デコーダのアルゴリズム移植 / qrcode-generator: RSブロック表・アライメント位置表）。全文は各公式リポジトリの LICENSE から取得すること（要約・改変禁止）。

- [ ] **Step 2: packages/moonqr の package.json を整える**

```json
{
  "name": "@elchika-inc/moonqr",
  "version": "0.1.0",
  "private": true,
  "type": "module",
  "description": "QR code encoder and decoder written in MoonBit. No dependencies, works in the browser.",
  "license": "Apache-2.0",
  "repository": { "type": "git", "url": "git+https://github.com/naoto24kawa/moonqr.git" },
  "keywords": ["qrcode", "qr", "decoder", "encoder", "moonbit", "browser"],
  "scripts": {
    "test": "node --test test/*.test.mjs"
  },
  "devDependencies": { "qrcode": "^1.5.4" }
}
```
（`private: true` のまま。解除は Task 8 の公開準備で。既存テストの `test` スクリプトは維持し、既存 273 テストが引き続き動くことを確認する）

- [ ] **Step 3: packages/scanner の雛形**

`packages/scanner/package.json`（`@elchika-inc/moonqr-scanner`, private: true, type: module, 依存 `"@elchika-inc/moonqr": "workspace:*"`）と空の `src/index.ts`（`export {}` のみ）を置き、`pnpm install` が通ることを確認。

- [ ] **Step 4: 確認・コミット**

```bash
pnpm install
pnpm --filter @elchika-inc/moonqr test   # 既存273テストが緑
git add -A && git commit -m "chore: Phase 3 ワークスペース再編とTHIRD_PARTY_LICENSES"
```

---

### Task 2: コア JS 境界の堅牢化（引き継ぎ消化）

**Files:**
- Modify: `core/src/encode/encode.mbt`（`encode_js` のガード, `to_svg_string_js` 追加）, `core/src/encode/moon.pkg.json`（exports 追加）, `core/src/encode/segment.mbt`（alnum ガード）, `core/src/encode/mask.mbt`（mask_bit 範囲ガード）
- Test: `core/src/encode/encode_test.mbt`（追加）, `core/src/decode/data_test.mbt`（追加）

**Interfaces (Produces):**
```moonbit
///| JS境界（total）。version は 0(auto) または 1..40、ec は 0..3。範囲外・空文字は []
pub fn encode_js(text : String, ec : Int, version : Int) -> Array[Int]
///| JS境界: SVG文字列。encode 失敗時は ""
pub fn to_svg_string_js(text : String, ec : Int, version : Int, margin : Int, cell : Int) -> String
```

- [ ] **Step 1: 失敗するテストを書く（RED）**

`encode_test.mbt` に追加:
```moonbit
test "encode_js rejects out-of-range version and ec" {
  assert_eq(@encode.encode_js("HI", 1, 41), [])
  assert_eq(@encode.encode_js("HI", 1, -1), [])
  assert_eq(@encode.encode_js("HI", 9, 1), [])   // ec 範囲外
  assert_eq(@encode.encode_js("HI", -1, 1), [])
}

test "encode_js rejects empty text" {
  // 空文字は仕様として拒否する（qrcode npm は throw する。我々は [] で表現）
  assert_eq(@encode.encode_js("", 1, 0), [])
}

test "encode rejects empty text" {
  match @encode.encode("", @encode.EcLevel::M, None) {
    Some(_) => abort("empty text must be rejected")
    None => assert_true(true)
  }
}

test "to_svg_string_js produces svg or empty on failure" {
  let svg = @encode.to_svg_string_js("HI", 1, 0, 4, 10)
  assert_true(svg.contains("<svg"))
  assert_eq(@encode.to_svg_string_js("HI", 1, 41, 4, 10), "")  // 範囲外 → ""
}
```

`data_test.mbt` に追加（Phase 2 レビューの引き継ぎ）:
```moonbit
test "decode_data resumes after unknown mode nibble" {
  // 未知モード(0011=StructuredAppend、この jsQR pin では未対応=ペイロード消費なしでスキップ)
  // の直後に有効な Byte セグメントが続くケース。jsQR と同じく「4bitだけ読み飛ばして継続」
  // する挙動を確認する。コードワードは手組みする。
  // 0011 | 0100(byte) | 00000010(len=2) | 'A' | 'B' | 0000(terminator)
  let cw = [0b0011_0100, 0b0000_0010, 0b0100_0001, 0b0100_0010, 0b0000_0000]
  match @decode.decode_data(cw, 1) {
    Some(d) => assert_eq(d.text, "AB")
    None => abort("must resume after unknown mode")
  }
}

test "decode_data rejects out-of-range alphanumeric index" {
  // alnum ペア値 11bit に 45*45=2025 以上（不正）を入れる → None
  // 1111111111 1 は 2047 > 2024 なので不正
  // 0010(alnum) | 000000010(len=2, v1) | 11111111111(2047) | 終端
  let cw = [0b0010_0000, 0b0001_0111, 0b1111_1111, 0b1100_0000]
  match @decode.decode_data(cw, 1) {
    Some(_) => abort("invalid alnum pair must be rejected")
    None => assert_true(true)
  }
}
```
（**注意**: 上記コードワードのビット配置は手計算した仮値。実装者は BitWriter で組み立て直すか、ビット列を検算してから使うこと。期待値が誤っていると判断したら**導出を示して報告**し、テストの意図（未知モード後の復帰・不正 alnum の拒否）を保ったまま正しい入力に直すこと。**アサートを弱めるのは禁止**）

- [ ] **Step 2: 失敗確認 → 実装**

`encode_js`: 先頭で `if version < 0 || version > 40 || ec < 0 || ec > 3 || text.length() == 0 { return [] }`。
`encode`: 先頭で `if text.length() == 0 { return None }`（doc comment に「空文字は None（qrcode npm は throw 相当）」と明記）。
`to_svg_string_js`: `encode` を呼び、`None` なら `""`、`Some(m)` なら `to_svg_string(m, margin, cell)`。
`write_segment` の Alphanumeric 分岐: `alnum_index(c) < 0` の文字が来たら**契約違反として abort**（内部呼び出しは detect_mode 経由で安全。pub 誤用の早期検知）。doc comment に前提を明記。
`mask_bit`: `mask < 0 || mask > 7` は abort（同上、内部は choose_mask の 0..7 のみ）。

`core/src/encode/moon.pkg.json` の js exports に `to_svg_string_js` を追加。

- [ ] **Step 3: 全 suite 緑を確認してコミット**

`moon test --target js`（92 + 新規）、`cd core && moon build --target js --release` 後に既存 node suite 273 が緑（encode_js の挙動変更が parity/sweep テストを壊していないこと — 空文字を使うテストがないか確認）。

```bash
git add -A && git commit -m "fix(core): JS境界のtotal化（範囲・空文字ガード）とSVG export"
```

---

### Task 3: moonqr パッケージの TS ラッパ（encode 側）

**Files:**
- Create: `packages/moonqr/src/types.ts`, `packages/moonqr/src/core.ts`, `packages/moonqr/src/index.ts`, `packages/moonqr/tsup.config.ts`, `packages/moonqr/vitest.config.ts`
- Create: `packages/moonqr/src/index.test.ts`（Vitest）
- Modify: `packages/moonqr/package.json`（tsup/vitest/typescript を devDeps に、scripts 追加）

**Interfaces (Produces — 公開 API の正本):**
```ts
export type EcLevel = "L" | "M" | "Q" | "H";

export interface EncodeOptions {
  /** 誤り訂正レベル（既定 "M"） */
  ecLevel?: EcLevel;
  /** バージョン 1..40。省略時は収まる最小を自動選択 */
  version?: number;
}

export interface QrMatrix {
  readonly size: number;
  /** true = 黒モジュール */
  get(x: number, y: number): boolean;
}

/** テキストを QR 行列にエンコードする。容量超過・空文字・不正オプションは null */
export function encode(text: string, options?: EncodeOptions): QrMatrix | null;

export interface SvgOptions {
  /** 余白（モジュール単位、既定 4） */
  margin?: number;
  /** 1モジュールの辺長（px、既定 4） */
  cell?: number;
}

/** QR 行列を SVG 文字列にする（純粋関数・DOM 非依存） */
export function toSvgString(matrix: QrMatrix, options?: SvgOptions): string;
```

- [ ] **Step 1: Vitest テストを書く（RED）**

`src/index.test.ts`:
```ts
import { describe, it, expect } from "vitest";
import { encode, toSvgString } from "./index.js";

describe("encode", () => {
  it("encodes and auto-selects version", () => {
    const m = encode("01234567")!;
    expect(m.size).toBe(21); // v1
    expect(typeof m.get(0, 0)).toBe("boolean");
    expect(m.get(0, 0)).toBe(true);   // TL ファインダ左上は黒
    expect(m.get(1, 1)).toBe(false);  // 白リング
  });
  it("honors ecLevel and version", () => {
    const m = encode("HI", { ecLevel: "H", version: 5 })!;
    expect(m.size).toBe(37); // v5
  });
  it("returns null on empty text", () => expect(encode("")).toBeNull());
  it("returns null on capacity overflow", () =>
    expect(encode("A".repeat(5000), { ecLevel: "H", version: 1 })).toBeNull());
  it("returns null on invalid version", () =>
    expect(encode("HI", { version: 41 })).toBeNull());
  it("get() is bounds-safe", () => {
    const m = encode("HI")!;
    expect(m.get(-1, 0)).toBe(false);
    expect(m.get(999, 0)).toBe(false);
  });
});

describe("toSvgString", () => {
  it("produces valid svg with expected viewBox", () => {
    const m = encode("HI")!;
    const svg = toSvgString(m, { margin: 4, cell: 10 });
    expect(svg).toContain("<svg");
    expect(svg).toContain(`viewBox="0 0 ${(m.size + 8) * 10} ${(m.size + 8) * 10}"`);
    expect(svg).toContain("</svg>");
  });
});
```

- [ ] **Step 2: 実装（GREEN）**

`src/core.ts`: MoonBit 出力（`../../../core/_build/js/release/build/encode/encode.js` と `.../decode/decode.js`）を import し、`encodeJs` / `decodeJs` / `toSvgStringJs` として re-export する内部モジュール。**ビルド時に tsup がこれをバンドルに取り込む**（`noExternal` で MoonBit 出力を必ずインライン化）。

`src/index.ts`: `encode` は `encodeJs(text, ecNum, version ?? 0)` の平坦配列 `[size, cells...]` を受け、`QrMatrix`（`get` は範囲外 false）に包む。`toSvgString` は行列から SVG を組み立てる（**TS 側で実装** — MoonBit の `to_svg_string_js` はテキストからしか作れないため、行列を受ける公開 API とは合わない。Task 2 で足した `to_svg_string_js` は demo/簡易用途として残すが、公開 API は TS 実装を正とする。この判断を index.ts のコメントに明記）。

`tsup.config.ts`: entry `src/index.ts` + `src/dom.ts`、format `["esm", "cjs"]`、`dts: true`、`minify: true`、`noExternal: [/core\/_build/]`、`treeshake: true`。

- [ ] **Step 3: ビルド確認・コミット**

```bash
pnpm --filter @elchika-inc/moonqr build   # dist/index.js, index.cjs, index.d.ts が出る
pnpm --filter @elchika-inc/moonqr test:unit  # vitest
ls -la packages/moonqr/dist/
```
バンドルサイズを報告（encode のみを import した場合の tree-shaking 効果も測る — decode を import しなければ decode.js が落ちるか確認し、落ちないなら**サブパス分割**（`@elchika-inc/moonqr/encode` / `@elchika-inc/moonqr/decode`）を検討して報告する）。

```bash
git add -A && git commit -m "feat(moonqr): TSラッパ（encode/toSvgString）とtsupビルド"
```

---

### Task 4: moonqr パッケージの TS ラッパ（decode 側）＋ dom サブパス

**Files:**
- Modify: `packages/moonqr/src/types.ts`, `src/index.ts`, `packages/moonqr/tsup.config.ts`
- Create: `packages/moonqr/src/dom.ts`, `packages/moonqr/src/decode.test.ts`, `packages/moonqr/src/dom.test.ts`

**Interfaces (Produces):**
```ts
export interface DecodeOptions {
  /** 反転色QRも試すか（既定 true） */
  invert?: boolean;
}

export interface Point { x: number; y: number; }

export interface DecodeResult {
  text: string;
  /** 生バイト列（バイナリペイロード用） */
  bytes: Uint8Array;
  version: number;
  ecLevel: EcLevel;
  /** 元画像px。TL,TR,BR,BL 順 */
  corners: [Point, Point, Point, Point];
}

/** RGBA ピクセルから QR を読む。見つからなければ null。不正入力（長さ不一致等）も null */
export function decode(
  data: Uint8Array | Uint8ClampedArray,
  width: number,
  height: number,
  options?: DecodeOptions,
): DecodeResult | null;

// @elchika-inc/moonqr/dom サブパス
export function toCanvas(matrix: QrMatrix, canvas: HTMLCanvasElement, options?: SvgOptions): void;
```

- [ ] **Step 1: テストを書く（RED）**

`decode.test.ts`: 既存の `test/lib/rasterize.mjs` を import して、encode → rasterize → decode のラウンドトリップ（クリーン・回転90・反転）。`bytes` が `Uint8Array` であること。不正入力（`data.length !== w*h*4`）→ null。`invert: false` で反転画像が読めないこと。
`dom.test.ts`: Vitest の jsdom 環境（`// @vitest-environment jsdom`）で `toCanvas` が `getContext("2d")` に対し正しいサイズで描画呼び出しを行うこと（canvas モックで `fillRect` 呼び出し回数＝黒モジュール数＋背景1 を検証）。

- [ ] **Step 2: 実装（GREEN）**

`decode`: `Uint8ClampedArray` は `new Uint8Array(data.buffer, data.byteOffset, data.byteLength)` で正規化してから `decodeJs` へ。返り値の JSON をパースし、`bytes` を `Uint8Array.from(...)` に、`corners` をタプルに整形。`""` → `null`。**JSON.parse 失敗も null**（防御）。
`dom.ts`: `toCanvas(matrix, canvas, {margin, cell})` — canvas のサイズを設定し、背景白 → 黒モジュールを `fillRect`。

`tsup.config.ts` の entry に `src/dom.ts` を追加し、`package.json` の `exports` に `"./dom"` を追加。

- [ ] **Step 3: 全 suite・コミット** — `feat(moonqr): decode ラッパと dom サブパス`

---

### Task 5: マルチスケールデコード（scanner の中核）

**Files:**
- Create: `packages/scanner/src/multiscale.ts`, `packages/scanner/src/multiscale.test.ts`
- Modify: `packages/moonqr/test/lib/multiscale.mjs` → **削除し**、`packages/scanner` の実装に一本化（既存 `monitor-lattice.test.mjs` の import 先を差し替え。テストは残す — Phase 2 の回帰網を失わないこと）

**Interfaces (Produces):**
```ts
export interface MultiScaleOutcome<T> {
  result: T;
  /** 成功時のネイティブ解像度からの総縮小率（1, 2, 4, 8, ...） */
  scale: number;
  /** 試行したスケール（昇順＝小さい画像から） */
  attemptedScales: number[];
}
/** 2x2 ボックス平均で半分に縮小（正しいローパス） */
export function halveRGBA(data: Uint8Array, width: number, height: number):
  { data: Uint8Array; width: number; height: number };
/**
 * ピラミッドを作り、小スケール優先で decodeFn を試す。
 * モニター接写のサブピクセル格子はナイーブ縮小ではエイリアスして残るため、
 * 逐次2x2平均が必須（Phase 2 の実測: 単発縮小は全サイズ失敗、1/8で成功）。
 * 小さい方から試すのは、カメラ写真が小スケールで読めることが多く、
 * 大→小の順だと最悪経路で数秒かかるため（実測 5382ms → 62ms）。
 */
export function multiScaleDecode<T>(
  decodeFn: (data: Uint8Array, w: number, h: number) => T | null,
  data: Uint8Array, width: number, height: number,
): MultiScaleOutcome<T> | null;
```

- [ ] **Step 1: 既存テストを移設して RED を作る**

`packages/moonqr/test/monitor-lattice.test.mjs` の import を `@elchika-inc/moonqr-scanner` の TS 実装（ビルド後の dist、または vitest なら src 直接）へ向ける。**アサートは一切変更しない**（Phase 2 が固定した挙動: 格子画像は単一スケールで失敗・マルチスケールで成功・16M超で事前半減が scale に計上・試行は昇順で最小から）。加えて `multiscale.test.ts`（Vitest）で `halveRGBA` の 2x2 平均を固定ベクタで検証（奇数サイズの切り捨ても）。

- [ ] **Step 2: TS へ移植（GREEN）**

`packages/moonqr/test/lib/multiscale.mjs` の実装を TS へ移植（ロジック不変）。移植後、旧 `.mjs` と `bench/demo.html` の重複実装を**削除**（demo は Task 7 で scanner/moonqr の dist を使う形に作り直す）。

- [ ] **Step 3: 全 suite・コミット** — `refactor(scanner): マルチスケールをTS実装に一本化`

---

### Task 6: `@elchika-inc/moonqr-scanner`（カメラ統合 + Worker）

**Files:**
- Create: `packages/scanner/src/camera.ts`, `src/worker.ts`, `src/index.ts`, `src/index.test.ts`, `tsup.config.ts`
- Modify: `packages/scanner/package.json`

**Interfaces (Produces):**
```ts
export interface QrScannerOptions {
  /** "environment"（背面・既定）または "user" */
  preferredCamera?: "environment" | "user";
  /** 1秒あたりの最大スキャン回数（既定 25） */
  maxScansPerSecond?: number;
  /** 反転色QRも試す（既定 true） */
  invert?: boolean;
  /** エラー通知（カメラ切断・Worker クラッシュ等）。握りつぶさない */
  onError?: (error: Error) => void;
}

export class QrScanner {
  constructor(video: HTMLVideoElement, onResult: (result: DecodeResult) => void, options?: QrScannerOptions);
  /** getUserMedia → video 再生 → Worker 起動 → ループ開始。失敗は reject */
  start(): Promise<void>;
  /** ストリーム・Worker・タイマーを全解放（冪等） */
  stop(): void;
  /** 静止画の一発読取（マルチスケール込み） */
  static scanImage(source: HTMLImageElement | HTMLCanvasElement | ImageBitmap | Blob): Promise<DecodeResult | null>;
  /** カメラが利用可能か（getUserMedia の有無・HTTPS 文脈） */
  static hasCamera(): Promise<boolean>;
}
```

- [ ] **Step 1: テストを書く（RED）**

`index.test.ts`（Vitest + jsdom）: `getUserMedia` をモックして — ①`start()` が getUserMedia を `{ video: { facingMode: "environment" } }` で呼ぶ ②権限拒否（reject）で `start()` が reject し、`onResult` が呼ばれない ③`stop()` が track.stop() と worker.terminate() を呼ぶ（冪等: 2回呼んでも例外なし）④`maxScansPerSecond` がフレーム間隔に反映される（fake timers で検証）。`scanImage` は canvas モックで RGBA を渡し、マルチスケール経由で結果が返ることを検証（Worker はテスト時インライン実行にフォールバック）。

- [ ] **Step 2: 実装（GREEN）**

- `camera.ts`: `getUserMedia({ video: { facingMode } })` → `video.srcObject` → `play()`。失敗は `Error` を throw（メッセージに原因）。
- `worker.ts`: `@elchika-inc/moonqr` の `decode` と `multiscale` を import し、`postMessage` で `{data, width, height, invert}` を受けて結果を返す。**フレームは transferable で渡す**（ゼロコピー）。
- `index.ts`: `QrScanner` は `requestAnimationFrame` ベースのループ（`maxScansPerSecond` でスロットル）→ OffscreenCanvas（なければ通常 canvas）→ `getImageData` → Worker へ transfer → 結果を `onResult`。Worker が使えない環境（テスト/古いブラウザ）は同スレッド実行にフォールバック。`stop()` は全リソース解放（冪等フラグ）。Worker のクラッシュは自動再起動し `onError` へ surface。
- ライブフレームは**マルチスケールを使わない**（毎フレーム数十msを避けるため、まず等倍で試す）。ただし N フレーム連続で失敗したらマルチスケールへエスカレーション（既定 15フレーム。理由をコメントに: 遠い/小さいQRやモニター越しの救済）。`scanImage`（静止画）は常にマルチスケール。

- `tsup.config.ts`: entry `src/index.ts`、format `["esm"]`（Worker を含むため ESM のみ）、`dts: true`、`minify: true`。Worker は inline（`worker.ts` を Blob URL 化する形にし、単一ファイル出荷にする — バンドラ設定不要で使えることを優先）。

- [ ] **Step 3: 全 suite・コミット** — `feat(scanner): QrScannerとWorkerパイプライン`

---

### Task 7: デモページ（GitHub Pages 用）

**Files:**
- Create: `docs/index.html`, `docs/app.js`（または単一 HTML）, `.github/workflows/pages.yml`
- Delete: `bench/demo.html`（機能は docs/ へ移設。bench/ はベンチ専用に戻す）

- [ ] **Step 1: デモを作る**

`docs/index.html`: ビルド済み `@elchika-inc/moonqr` と `@elchika-inc/moonqr-scanner` の dist を `assets/` にコピーして読み込む（CDN 不使用・自己完結）。機能: ①テキスト入力 → QR 生成（EC・バージョン選択・SVG ダウンロード）②画像ファイル/ドラッグ&ドロップ → 読取（マルチスケール・成功スケール表示）③**カメラ起動 → ライブスキャン**（`QrScanner` の実演。HTTPS/localhost 必須の注記）。結果は text/version/ecLevel/corners を表示し、corners を video 上にオーバーレイ描画。

- [ ] **Step 2: Pages ワークフロー**

`.github/workflows/pages.yml`: main への push で ①moon 導入 → `moon build --target js --release` ②`pnpm install && pnpm -r build` ③dist を `docs/assets/` へコピー ④`actions/deploy-pages` で公開。**このワークフローの実行（＝公開）はリポジトリを GitHub に push した後に初めて動く。push 自体は Task 10 の human-gate 対象**。

- [ ] **Step 3: ローカル確認・コミット**

`python3 -m http.server 8125 --directory docs` で3機能を実ブラウザ確認（Claude in Chrome）。カメラは fake device が無い環境では起動可否のみ確認し、実カメラ検証は Task 10 の human-gate で行う。

`git add -A && git commit -m "feat(docs): GitHub Pages デモ（生成・読取・カメラ）"`

---

### Task 8: CI ワークフローと公開メタデータ

**Files:**
- Create: `.github/workflows/ci.yml`
- Modify: `packages/moonqr/package.json`, `packages/scanner/package.json`（公開メタ整備・`private` は残す）, `packages/*/README.md`, ルート `README.md`

- [ ] **Step 1: CI**

`.github/workflows/ci.yml`: push/PR で ①moon セットアップ＋`moon test --target js`（92+）②`moon build --target js --release` ③`pnpm install`（frozen lockfile）④`pnpm -r build` ⑤node テスト全部（parity は fixtures 取得込み: `node scripts/fetch-fixtures.mjs`）⑥Vitest ⑦バンドルサイズを出力（gzip 値をログ）。**fixtures 取得は jsQR の pinned SHA で clone するためネットワークが要る — CI で失敗したら fixtures をキャッシュする（actions/cache）**。

- [ ] **Step 2: 公開メタデータ**

両 package.json に: `files: ["dist", "README.md", "../../LICENSE", "../../NOTICE", "../../THIRD_PARTY_LICENSES"]`（**相対パス上位は npm に含められない** — LICENSE/NOTICE/THIRD_PARTY_LICENSES は各パッケージ直下にコピーする prepack スクリプトを書くこと）、`sideEffects: false`、`engines`、`publishConfig: { "access": "public" }`（**両パッケージとも scope 付きなので必須** — 無いと private 扱いで publish が失敗する）、`exports` マップ（`.` / `./dom`）、`main`/`module`/`types`。

README: 各パッケージにインストール・使用例（encode/decode/scanner の3例）・ブラウザ対応・ライセンス・帰属を記載。ルート README にプロジェクト概要・ベンチ結果（jsQR 比 214==214 / 0.77x）・デモリンク（Pages URL）・開発手順。

- [ ] **Step 3: パック検証・コミット**

```bash
pnpm --filter @elchika-inc/moonqr pack --dry-run     # 同梱物を確認（dist + LICENSE類 + README のみ、srcやtestが入らないこと）
pnpm --filter @elchika-inc/moonqr-scanner pack --dry-run
```
同梱物リストを報告。`git add -A && git commit -m "chore: CIワークフローと公開メタデータ"`

---

### Task 9: mooncakes 公開準備と RESULT.md ポリシー

**Files:**
- Modify: `core/moon.mod.json`（メタ整備）, `bench/RESULT.md`（ポリシー記載）
- Create: `core/README.mbt.md` or `core/README.md`（mooncakes 用）

- [ ] **Step 1: moon.mod.json 整備**: description/keywords/repository/license は既に有り。`readme` フィールドと、必要なら `exclude`（bench パッケージを公開物から外すか判断 — スパイク用なので除外を推奨）を追加。

- [ ] **Step 2: `moon publish --dry-run`（または `moon package --list` 等、実際に存在するコマンドを確認）**でパッケージ内容を検証。**実公開は Task 10 の human-gate**。

- [ ] **Step 3: RESULT.md ポリシー**: 冒頭に「このファイルは各フェーズの実測記録。再計測で数値が変わったら該当節を**置換**する（追記しない）。パリティ/性能の合否はテスト内アサートが正本であり、本ファイルは根拠の保存先」と明記。

- [ ] **Step 4: コミット** — `chore(core): mooncakes公開メタとRESULT.mdポリシー`

---

### Task 10: 人力ゲート — 公開（**ユーザー承認必須**）

**このタスクは Claude が単独で実行してはならない。** 以下はユーザーが行う／ユーザーの明示承認を得てから行う操作:

- [ ] **Step 1: 事前確認をユーザーに提示**
  - 公開されるもの: npm 2パッケージ（同梱物リスト）、mooncakes モジュール、GitHub リポジトリ（**公開リポジトリになる**）、GitHub Pages（デモが公開URLになる）
  - 公開後は取り消しが困難（npm unpublish は72時間以内・条件付き。公開URLは検索/キャッシュに残る）
  - ライセンス・帰属が正しいこと（NOTICE / THIRD_PARTY_LICENSES）
  - **ユーザーが行う必要がある操作**: `npm login`（Claude は認証情報を扱わない。org `@elchika-inc` は既存で作成不要）、GitHub リポジトリの作成（`gh repo create naoto24kawa/moonqr --public`）
- [ ] **Step 2: ユーザー承認後、順に実行**（各ステップ後に結果を報告）
  1. GitHub リポジトリ作成＋push（承認後）
  2. CI が緑になることを確認（`gh run watch`）
  3. Pages 公開を確認（URL を実際に開いて3機能が動くこと — **CI 緑＝公開成功ではない**。実URLで検証する）
  4. `npm publish --access public`（`@elchika-inc/moonqr` → `@elchika-inc/moonqr-scanner` の順。scanner は core に依存するため。**publish 前に workspace:* を実バージョンに解決すること** — pnpm publish は自動解決するが dry-run で確認する）
  5. `moon publish`（mooncakes）
  6. 公開後検証: `npm view @elchika-inc/moonqr` / 新規ディレクトリで `pnpm add @elchika-inc/moonqr` して import が通ること（**実体で確認する**）
- [ ] **Step 3: 実機確認**: 公開 Pages URL をスマホで開き、カメラライブスキャンで実際のQRを読む（Phase 2 で発見したモニター格子ケースも含む）
- [ ] **Step 4: 記録・タグ**: RESULT.md に公開記録、`git tag v0.1.0`（**ブランチ名と異なるタグ名** — URISK-065）

---

## 完了チェック（Phase 3 の Done 判定 = スペック rubric 4）

- [ ] npm 2パッケージが公開され、新規プロジェクトから `pnpm add @elchika-inc/moonqr` → import → encode/decode が動く（実体確認）
- [ ] mooncakes.io に `naoto24kawa/moonqr` が公開されている
- [ ] GitHub Pages デモが公開URLで動く（生成・画像読取・カメラライブスキャンの3機能）
- [ ] README・ライセンス・帰属完備（NOTICE / THIRD_PARTY_LICENSES が npm 同梱物に含まれる）
- [ ] CI が緑（moon + node + vitest + build）
- [ ] 実機スマホでカメラスキャン成功

## 想定リスク

- ~~npm org 作成~~ → **解決済み**: 既存 org `@elchika-inc` を使用（ユーザー確認済み 2026-07-14）。publish 時は `--access public` が必須
- **Worker のインライン化**とバンドラ互換性（Vite/webpack/Next.js で動くか）。最低限 Vite での動作確認を Task 6 で行う
- **decode バンドルサイズ**: 現状 gzip 62KB（SJIS 表が支配的。jsQR も 57KB なので同等）。漢字モード不要な利用者向けに `@elchika-inc/moonqr/decode-no-kanji` 等の分割は**やらない**（YAGNI。要望が出たら検討）
