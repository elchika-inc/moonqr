# moonqr Phase 1: 基盤＋エンコーダ 実装計画

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** MoonBit ツールチェイン導入・バックエンド選定スパイク・GF(256)/Reed-Solomon・QRエンコーダを完成させ、`qrcode` npm との行列一致テストと実機スキャンで検証された生成器を出荷可能にする。

**Architecture:** モノレポ `moonqr/`。MoonBit モジュール `core/`（mooncakes 名 `naoto24kawa/moonqr`）に gf256 / encode パッケージを実装。純粋関数のみ・DOM 非依存。バックエンド（js / wasm-gc）は最初のスパイクで実測決定する。

**Tech Stack:** MoonBit（moon CLI）、Node.js 20+、pnpm workspace、検証用に `qrcode` npm（devDependency）。

**スコープ注記:** スペック（`docs/superpowers/specs/2026-07-13-moonqr-design.md`）のうち Phase 1 のみ。デコーダは Plan 2、npm パッケージング / `@moonqr/scanner` / 公開は Plan 3 として、本計画完了後に確定バックエンドと実測 FFI 知見を反映して作成する。

## Global Constraints

- リポジトリ: `/Users/nishikawa/projects/naoto24kawa/moonqr`（git init 済み）
- ライセンス: Apache-2.0（jsQR 参照互換のため。Plan 2 で帰属表示を追加）
- mooncakes モジュール名: `naoto24kawa/moonqr`、npm 名: `moonqr` / `@moonqr/scanner`
- core は DOM・Canvas・カメラ非依存の純粋関数のみ
- 例外は契約違反のみ。読取・変換の失敗は Option で表現
- エンコーダの対応モード: numeric / alphanumeric / byte(UTF-8)。漢字テキストは byte モードにフォールバック（漢字専用モードのエンコードは非対応。デコード側の漢字モード対応は Plan 2）
- ECC レベル既定 "M"、バージョン自動選択 1..40
- テストは `moon test --target js` を基本とし、バックエンド決定後は決定ターゲットでも実行
- コミットメッセージ末尾: `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`
- MoonBit 構文はこの計画記載のコードを出発点とし、コンパイルエラー時は https://docs.moonbitlang.com/en/latest/language/ の現行構文に合わせて修正してよい（アルゴリズム・テスト内容・公開シグネチャは変えない）

## File Structure

```
moonqr/
├── core/
│   ├── moon.mod.json
│   └── src/
│       ├── gf256/            # GF(256) 算術・多項式・Reed-Solomon encode/decode
│       │   ├── moon.pkg.json
│       │   ├── gf256.mbt     # exp/log テーブル、mul/div
│       │   ├── poly.mbt      # 多項式演算・RS生成多項式・rs_encode
│       │   ├── rs_decode.mbt # シンドローム・Berlekamp-Massey・Chien・Forney
│       │   └── *_test.mbt
│       ├── encode/
│       │   ├── moon.pkg.json
│       │   ├── bitwriter.mbt # ビット列書き込み
│       │   ├── segment.mbt   # モード判定・セグメント符号化・UTF-8
│       │   ├── tables.mbt    # RSブロック表・アライメント位置表（スクリプト生成）
│       │   ├── matrix.mbt    # 機能パターン配置・データ配置・マスク・ペナルティ
│       │   ├── encode.mbt    # encode() façade・バージョン自動選択
│       │   ├── svg.mbt       # to_svg_string（純粋文字列生成）
│       │   └── *_test.mbt
│       └── bench/
│           ├── moon.pkg.json # スパイク用カーネル（選定後も回帰ベンチとして残す）
│           └── kernel.mbt
├── bench/
│   ├── gen-frame.mjs         # 合成フレーム生成（seeded PRNG）
│   ├── run-node.mjs          # Node 計測ハーネス
│   ├── bench.html            # Chrome 計測ページ
│   └── RESULT.md             # 実測結果と採用決定（Task 3 で作成）
├── scripts/
│   └── gen-tables.mjs        # qrcode-generator ソースから tables.mbt を生成
├── packages/moonqr/          # Phase 1 では統合テストのみ配置（本体は Plan 3）
│   └── test/matrix-parity.test.mjs
├── pnpm-workspace.yaml
├── package.json
├── LICENSE
└── .gitignore
```

---

### Task 1: ツールチェイン導入とモノレポ雛形

**Files:**
- Create: `core/moon.mod.json`, `core/src/gf256/moon.pkg.json`, `core/src/gf256/gf256.mbt`, `core/src/gf256/gf256_test.mbt`
- Create: `pnpm-workspace.yaml`, `package.json`, `.gitignore`, `LICENSE`

**Interfaces:**
- Produces: ビルド・テストが通る MoonBit モジュール雛形。以降の全タスクの土台。

- [ ] **Step 1: moon CLI をインストールし版を確認**

```bash
curl -fsSL https://cli.moonbitlang.com/install/unix.sh | bash
export PATH="$HOME/.moon/bin:$PATH"   # シェルprofileにも追記
moon version
```

Expected: `moon X.Y.Z` が表示される。版番号を後で `bench/RESULT.md` に記録する。

- [ ] **Step 2: モジュール定義と雛形を作成**

`core/moon.mod.json`:
```json
{
  "name": "naoto24kawa/moonqr",
  "version": "0.1.0",
  "license": "Apache-2.0",
  "repository": "https://github.com/naoto24kawa/moonqr",
  "description": "Pure QR code encoder/decoder written in MoonBit",
  "keywords": ["qrcode", "qr"],
  "source": "src",
  "preferred-target": "js"
}
```

`core/src/gf256/moon.pkg.json`:
```json
{}
```

`core/src/gf256/gf256.mbt`（動作確認用の最小実装。Task 4 で本実装に置き換える）:
```moonbit
///| GF(256) 加算（= XOR）
pub fn add(a : Int, b : Int) -> Int {
  a ^ b
}
```

`core/src/gf256/gf256_test.mbt`:
```moonbit
test "gf add is xor" {
  assert_eq(@gf256.add(0x53, 0xCA), 0x99)
}
```

- [ ] **Step 3: テスト実行**

```bash
cd core && moon test --target js
```

Expected: `Total tests: 1, passed: 1, failed: 0`。失敗したら構文を現行ドキュメントに合わせて修正（Global Constraints 参照）。

- [ ] **Step 4: ワークスペースと補助ファイル**

`pnpm-workspace.yaml`:
```yaml
packages:
  - "packages/*"
```

`package.json`:
```json
{
  "name": "moonqr-monorepo",
  "private": true,
  "devDependencies": {
    "qrcode": "^1.5.4"
  }
}
```

`.gitignore`:
```
node_modules/
target/
.mooncakes/
```

`LICENSE`: Apache-2.0 全文（https://www.apache.org/licenses/LICENSE-2.0.txt をコピー、copyright は `2026 naoto24kawa`）。

```bash
pnpm install
```

- [ ] **Step 5: コミット**

```bash
git add -A && git commit -m "chore: MoonBitモジュール雛形とpnpmワークスペース"
```

---

### Task 2: スパイクカーネル実装（js ターゲット）

**Files:**
- Create: `core/src/bench/moon.pkg.json`, `core/src/bench/kernel.mbt`, `core/src/bench/kernel_test.mbt`

**Interfaces:**
- Produces: `pub fn bench_kernel(rgba : Bytes, width : Int, height : Int) -> Int` — RGBA → グレースケール → 8x8ブロック局所二値化 → 全行 1:1:3:1:1 走査で候補数を返す。実デコーダ第1〜2段の計算量を代表するカーネル。

- [ ] **Step 1: 失敗するテストを書く**

`core/src/bench/kernel_test.mbt`:
```moonbit
///| 128x128 の合成フレーム: 白地(200)に 7x7 モジュール相当の
///| ファインダ様パターン(1:1:3:1:1)を1つ描く。検出数 >= 1 を期待。
///| 一様データはインデックスバグを隠すため、背景に位置依存ノイズを乗せる。
fn synth_frame(w : Int, h : Int) -> Bytes {
  let buf = FixedArray::make(w * h * 4, b'\x00')
  for y = 0; y < h; y = y + 1 {
    for x = 0; x < w; x = x + 1 {
      // 位置依存の明背景 (180..219)
      let mut v = 180 + (x * 7 + y * 13) % 40
      // (32,32)-(88,88) にファインダ様パターン: 外周黒・中黒芯
      let fx = x - 32
      let fy = y - 32
      if fx >= 0 && fx < 56 && fy >= 0 && fy < 56 {
        let mx = fx / 8 // 0..6
        let my = fy / 8
        let ring = mx == 0 || mx == 6 || my == 0 || my == 6
        let core_ = mx >= 2 && mx <= 4 && my >= 2 && my <= 4
        v = if ring || core_ { 30 } else { 220 }
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

test "kernel finds finder-like runs in synthetic frame" {
  let frame = synth_frame(128, 128)
  let hits = @bench.bench_kernel(frame, 128, 128)
  assert_true(hits >= 1)
}

test "kernel finds nothing in noise-only frame" {
  let w = 64
  let buf = FixedArray::make(w * w * 4, b'\x00')
  for i = 0; i < w * w; i = i + 1 {
    let v = 100 + (i * 31) % 80
    buf[i * 4] = v.to_byte()
    buf[i * 4 + 1] = v.to_byte()
    buf[i * 4 + 2] = v.to_byte()
    buf[i * 4 + 3] = b'\xFF'
  }
  assert_eq(@bench.bench_kernel(Bytes::from_fixedarray(buf), w, w), 0)
}
```

- [ ] **Step 2: 失敗を確認** — `cd core && moon test --target js` → FAIL（`@bench` 未定義）

- [ ] **Step 3: カーネルを実装**

`core/src/bench/moon.pkg.json`:
```json
{
  "link": {
    "js": { "exports": ["bench_kernel"], "format": "esm" },
    "wasm-gc": { "exports": ["bench_kernel_arr", "make_frame", "frame_set"] }
  }
}
```

`core/src/bench/kernel.mbt`:
```moonbit
///| RGBA → 輝度（整数近似 BT.601: (77R + 150G + 29B) >> 8）
fn to_gray(rgba : Bytes, width : Int, height : Int) -> FixedArray[Int] {
  let gray = FixedArray::make(width * height, 0)
  for p = 0; p < width * height; p = p + 1 {
    let i = p * 4
    let r = rgba[i].to_int()
    let g = rgba[i + 1].to_int()
    let b = rgba[i + 2].to_int()
    gray[p] = (77 * r + 150 * g + 29 * b) >> 8
  }
  gray
}

///| 8x8 ブロック平均でしきい値マップを作り二値化（1=黒）
fn binarize(gray : FixedArray[Int], width : Int, height : Int) -> FixedArray[Int] {
  let bw = (width + 7) / 8
  let bh = (height + 7) / 8
  let means = FixedArray::make(bw * bh, 128)
  for by = 0; by < bh; by = by + 1 {
    for bx = 0; bx < bw; bx = bx + 1 {
      let mut sum = 0
      let mut n = 0
      for dy = 0; dy < 8; dy = dy + 1 {
        for dx = 0; dx < 8; dx = dx + 1 {
          let x = bx * 8 + dx
          let y = by * 8 + dy
          if x < width && y < height {
            sum = sum + gray[y * width + x]
            n = n + 1
          }
        }
      }
      means[by * bw + bx] = sum / n
    }
  }
  let bin = FixedArray::make(width * height, 0)
  for y = 0; y < height; y = y + 1 {
    for x = 0; x < width; x = x + 1 {
      // 自ブロック単独の平均だと一様ブロック（大きな黒/白領域）で
      // mean==pixel となり全て白判定になるため、3x3近傍ブロック平均を使う
      let bx = x / 8
      let by = y / 8
      let mut sum = 0
      let mut n = 0
      for dy = -1; dy <= 1; dy = dy + 1 {
        for dx = -1; dx <= 1; dx = dx + 1 {
          let nx = bx + dx
          let ny = by + dy
          if nx >= 0 && nx < bw && ny >= 0 && ny < bh {
            sum = sum + means[ny * bw + nx]
            n = n + 1
          }
        }
      }
      let m = sum / n
      bin[y * width + x] = if gray[y * width + x] < m { 1 } else { 0 }
    }
  }
  bin
}

///| 走査線上の黒白黒白黒ラン比 1:1:3:1:1（各±50%）をカウント
fn scan_ratios(bin : FixedArray[Int], width : Int, height : Int) -> Int {
  let mut hits = 0
  for y = 0; y < height; y = y + 1 {
    let runs : Array[Int] = []
    let mut cur = bin[y * width]
    let mut len = 1
    for x = 1; x < width; x = x + 1 {
      let v = bin[y * width + x]
      if v == cur {
        len = len + 1
      } else {
        runs.push(len)
        cur = v
        len = 1
      }
    }
    runs.push(len)
    // 先頭ランが白なら奇数indexが黒。黒始まりの5連続を判定
    let start = if bin[y * width] == 1 { 0 } else { 1 }
    for i = start; i + 4 < runs.length(); i = i + 2 {
      let m = runs[i + 2].to_double() / 3.0
      let ok = fn(r : Int) -> Bool {
        r.to_double() > m * 0.5 && r.to_double() < m * 1.5
      }
      if ok(runs[i]) && ok(runs[i + 1]) && ok(runs[i + 3]) && ok(runs[i + 4]) {
        hits = hits + 1
      }
    }
  }
  hits
}

///| スパイク計測対象: フレーム1枚分の代表処理
pub fn bench_kernel(rgba : Bytes, width : Int, height : Int) -> Int {
  let gray = to_gray(rgba, width, height)
  let bin = binarize(gray, width, height)
  scan_ratios(bin, width, height)
}

///| wasm-gc 用エントリ（JS から GC 配列を直接作れないため転送ヘルパを公開）
pub fn make_frame(len : Int) -> FixedArray[Byte] {
  FixedArray::make(len, b'\x00')
}

pub fn frame_set(f : FixedArray[Byte], i : Int, v : Int) -> Unit {
  f[i] = v.to_byte()
}

pub fn bench_kernel_arr(f : FixedArray[Byte], width : Int, height : Int) -> Int {
  bench_kernel(Bytes::from_fixedarray(f), width, height)
}
```

- [ ] **Step 4: テスト通過を確認** — `moon test --target js` → PASS（2件）

- [ ] **Step 5: コミット**

```bash
git add -A && git commit -m "feat(bench): バックエンド選定スパイク用カーネル"
```

---

### Task 3: 両バックエンド計測とバックエンド決定

**Files:**
- Create: `bench/gen-frame.mjs`, `bench/run-node.mjs`, `bench/bench.html`, `bench/RESULT.md`

**Interfaces:**
- Consumes: Task 2 の `bench_kernel`（js）/ `bench_kernel_arr` + `make_frame` + `frame_set`（wasm-gc）
- Produces: バックエンド決定（以降の全タスク・Plan 2/3 が従う）。`bench/RESULT.md` に根拠を記録。

- [ ] **Step 1: 両ターゲットをビルド**

```bash
cd core
moon build --target js --release
moon build --target wasm-gc --release
ls target/js/release/build/bench/ target/wasm-gc/release/build/bench/
```

Expected: `bench.js`（ESM）と `bench.wasm` が存在。出力パス・ロード方法が異なる場合は `moon build --help` と docs の backend ページで確認して調整。

- [ ] **Step 2: wasm-gc の JS 境界の最速パスを調査**

MoonBit docs（ffi.html / wasm-gc backend ページ）で「JS から Uint8Array を wasm-gc へ渡す」公式手段を確認する。専用の高速パス（例: js-string-builtins 相当のバイト列版）が存在すればそれを使い、無ければ `make_frame` + `frame_set` の per-element 転送を採用（それが現実の境界コスト）。調査結果を RESULT.md の「方法」節に1段落で記録。

- [ ] **Step 3: 計測ハーネスを書く**

`bench/gen-frame.mjs`:
```js
// mulberry32 seeded PRNG で 640x480 RGBA 合成フレームを決定的に生成。
// 背景ノイズ + ファインダ様パターン3個（一様fixture回避）。
export function genFrame(width = 640, height = 480, seed = 42) {
  let a = seed >>> 0;
  const rand = () => {
    a |= 0; a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
  const buf = new Uint8Array(width * height * 4);
  for (let p = 0; p < width * height; p++) {
    const v = 150 + Math.floor(rand() * 80);
    buf[p * 4] = v; buf[p * 4 + 1] = v; buf[p * 4 + 2] = v; buf[p * 4 + 3] = 255;
  }
  const drawFinder = (ox, oy, mod) => {
    for (let my = 0; my < 7; my++) for (let mx = 0; mx < 7; mx++) {
      const ring = mx === 0 || mx === 6 || my === 0 || my === 6;
      const core = mx >= 2 && mx <= 4 && my >= 2 && my <= 4;
      const v = ring || core ? 25 : 230;
      for (let dy = 0; dy < mod; dy++) for (let dx = 0; dx < mod; dx++) {
        const x = ox + mx * mod + dx, y = oy + my * mod + dy;
        const i = (y * width + x) * 4;
        buf[i] = v; buf[i + 1] = v; buf[i + 2] = v;
      }
    }
  };
  drawFinder(50, 50, 8); drawFinder(450, 60, 8); drawFinder(60, 350, 8);
  return buf;
}
```

`bench/run-node.mjs`:
```js
import { genFrame } from "./gen-frame.mjs";

const WARMUP = 30, ITERS = 200;
const frame = genFrame();

function measure(label, fn) {
  for (let i = 0; i < WARMUP; i++) fn();
  const times = [];
  for (let i = 0; i < ITERS; i++) {
    const t0 = performance.now();
    const hits = fn();
    times.push(performance.now() - t0);
    if (i === 0) console.log(`${label} hits=${hits}`); // 結果一致の目視確認用
  }
  times.sort((a, b) => a - b);
  const median = times[Math.floor(ITERS / 2)];
  console.log(`${label}: median ${median.toFixed(3)} ms/frame`);
  return median;
}

// --- js backend（ビルド出力のパスは実際の出力に合わせる）---
const jsMod = await import("../core/target/js/release/build/bench/bench.js");
const jsTime = measure("js     ", () => jsMod.bench_kernel(frame, 640, 480));

// --- wasm-gc backend ---
const { readFile } = await import("node:fs/promises");
const wasmBytes = await readFile(
  new URL("../core/target/wasm-gc/release/build/bench/bench.wasm", import.meta.url));
const { instance } = await WebAssembly.instantiate(wasmBytes, {});
const w = instance.exports;
const wasmTime = measure("wasm-gc", () => {
  // 境界コスト込み: フレーム転送も計測に含める（これが本番の姿）
  const f = w.make_frame(frame.length);
  for (let i = 0; i < frame.length; i++) w.frame_set(f, i, frame[i]);
  return w.bench_kernel_arr(f, 640, 480);
});

console.log(`ratio (wasm/js): ${(wasmTime / jsTime).toFixed(2)}`);
```

Run: `node bench/run-node.mjs`
Expected: 両バックエンドの `hits=` が同値（結果整合）、median と ratio が出力される。wasm 側の import object が必要な場合（spectest 等）はエラーメッセージに従い供給する。

- [ ] **Step 4: Chrome でも計測**

`bench/bench.html` を作成（run-node.mjs と同じ計測を `<script type="module">` で実行し `document.body` に結果を出すだけの移植。fetch でビルド成果物をロード）。

```bash
python3 -m http.server 8000 --directory /Users/nishikawa/projects/naoto24kawa/moonqr
```

Chrome で `http://localhost:8000/bench/bench.html` を開き数値を記録（Claude in Chrome があれば自動読取、なければユーザーに依頼）。

- [ ] **Step 5: 決定を記録してコミット**

`bench/RESULT.md` に記録: moon 版・Node 版・Chrome 版、方法（境界転送の方式）、Node/Chrome それぞれの median、幾何平均比。

**判定基準（スペック準拠）: 幾何平均で 1.3 倍以上速い方を採用。1.3 倍未満なら js backend（配布 DX 優位）。**

決定したら `core/moon.mod.json` の `preferred-target` を決定値に合わせ、以降のタスクの `moon test` は決定ターゲットも実行対象に加える。

```bash
git add -A && git commit -m "feat(bench): js/wasm-gc 実測とバックエンド決定 — RESULT.md 参照"
```

---

### Task 4: GF(256) 算術

**Files:**
- Modify: `core/src/gf256/gf256.mbt`（Task 1 の雛形を置き換え）
- Test: `core/src/gf256/gf256_test.mbt`

**Interfaces:**
- Produces: `pub fn mul(a : Int, b : Int) -> Int` / `pub fn div(a : Int, b : Int) -> Int` / `pub fn exp(i : Int) -> Int` / `pub fn log(a : Int) -> Int` / `pub fn add(a : Int, b : Int) -> Int`。既約多項式 0x11D（QR標準）。値域は 0..255。

- [ ] **Step 1: 失敗するテストを書く**

`core/src/gf256/gf256_test.mbt`（全置き換え）:
```moonbit
test "mul basic identities" {
  assert_eq(@gf256.mul(0, 123), 0)
  assert_eq(@gf256.mul(123, 0), 0)
  assert_eq(@gf256.mul(1, 123), 123)
  assert_eq(@gf256.mul(2, 3), 6)        // 縮約なし
  assert_eq(@gf256.mul(128, 2), 29)     // 0x100 ^ 0x11D = 0x1D
}

test "mul is commutative and associative (spot)" {
  for a = 1; a < 256; a = a + 17 {
    for b = 1; b < 256; b = b + 13 {
      assert_eq(@gf256.mul(a, b), @gf256.mul(b, a))
    }
  }
}

test "div inverts mul for all nonzero pairs" {
  for a = 1; a < 256; a = a + 1 {
    for b = 1; b < 256; b = b + 1 {
      assert_eq(@gf256.div(@gf256.mul(a, b), b), a)
    }
  }
}

test "exp log roundtrip" {
  for a = 1; a < 256; a = a + 1 {
    assert_eq(@gf256.exp(@gf256.log(a)), a)
  }
}
```

- [ ] **Step 2: 失敗確認** — `moon test --target js` → FAIL

- [ ] **Step 3: 実装**

`core/src/gf256/gf256.mbt`:
```moonbit
///| GF(2^8), 既約多項式 x^8+x^4+x^3+x^2+1 = 0x11D（QRコード標準）

fn build_exp() -> FixedArray[Int] {
  let t = FixedArray::make(512, 0)
  let mut x = 1
  for i = 0; i < 255; i = i + 1 {
    t[i] = x
    x = x << 1
    if x >= 256 {
      x = x ^ 0x11D
    }
  }
  for i = 255; i < 512; i = i + 1 {
    t[i] = t[i - 255]
  }
  t
}

fn build_log() -> FixedArray[Int] {
  let t = FixedArray::make(256, 0)
  let mut x = 1
  for i = 0; i < 255; i = i + 1 {
    t[x] = i
    x = x << 1
    if x >= 256 {
      x = x ^ 0x11D
    }
  }
  t
}

let exp_table : FixedArray[Int] = build_exp()

let log_table : FixedArray[Int] = build_log()

///| 加算 = 減算 = XOR
pub fn add(a : Int, b : Int) -> Int {
  a ^ b
}

pub fn exp(i : Int) -> Int {
  exp_table[i % 255]
}

///| 前提: a != 0（a=0 は契約違反）
pub fn log(a : Int) -> Int {
  log_table[a]
}

pub fn mul(a : Int, b : Int) -> Int {
  if a == 0 || b == 0 {
    0
  } else {
    exp_table[log_table[a] + log_table[b]]
  }
}

///| 前提: b != 0
pub fn div(a : Int, b : Int) -> Int {
  if a == 0 {
    0
  } else {
    exp_table[(log_table[a] - log_table[b] + 255) % 255]
  }
}
```

- [ ] **Step 4: 通過確認** — `moon test --target js` → PASS
- [ ] **Step 5: コミット** — `git add -A && git commit -m "feat(gf256): GF(256)算術（0x11D）"`

---

### Task 5: 多項式演算と Reed-Solomon エンコード

**Files:**
- Create: `core/src/gf256/poly.mbt`, `core/src/gf256/poly_test.mbt`

**Interfaces:**
- Consumes: `mul`, `add`, `exp`（Task 4）
- Produces: `pub fn rs_encode(data : Array[Int], n_ec : Int) -> Array[Int]`（ECコードワード n_ec 個を返す）、内部関数 `poly_mul`, `poly_rem`, `rs_generator(n : Int) -> Array[Int]`。多項式は係数の配列・先頭が最高次。

- [ ] **Step 1: 失敗するテストを書く**

`core/src/gf256/poly_test.mbt`:
```moonbit
test "rs generator degree and leading coeff" {
  // 生成多項式 g(x) = Π_{i=0}^{n-1} (x - α^i)。次数 n、モニック。
  let g = @gf256.rs_generator(10)
  assert_eq(g.length(), 11)
  assert_eq(g[0], 1)
}

test "rs_encode length and determinism" {
  let data = [32, 91, 11, 120, 209, 114, 220, 77, 67, 64, 236, 17, 236, 17, 236, 17]
  let ec = @gf256.rs_encode(data, 10)
  assert_eq(ec.length(), 10)
  assert_eq(ec, @gf256.rs_encode(data, 10))
}

test "rs_encode makes codeword divisible by generator" {
  // 符号語 = data || ec は g(x) で割り切れる（RS符号の定義）
  let data = [64, 86, 22, 198, 87, 38, 23, 50, 6, 54, 246, 118, 66]
  let n_ec = 13
  let ec = @gf256.rs_encode(data, n_ec)
  let codeword = data.copy()
  for i = 0; i < n_ec; i = i + 1 {
    codeword.push(ec[i])
  }
  // g(α^i) = 0 (i=0..n_ec-1) なので符号語も α^i で評価して 0 になる
  for i = 0; i < n_ec; i = i + 1 {
    let x = @gf256.exp(i)
    let mut acc = 0
    for j = 0; j < codeword.length(); j = j + 1 {
      acc = @gf256.add(@gf256.mul(acc, x), codeword[j])
    }
    assert_eq(acc, 0)
  }
}
```

- [ ] **Step 2: 失敗確認** — `moon test --target js` → FAIL
- [ ] **Step 3: 実装**

`core/src/gf256/poly.mbt`:
```moonbit
///| 多項式は Array[Int]、index 0 が最高次係数

pub fn poly_mul(a : Array[Int], b : Array[Int]) -> Array[Int] {
  let out = Array::make(a.length() + b.length() - 1, 0)
  for i = 0; i < a.length(); i = i + 1 {
    for j = 0; j < b.length(); j = j + 1 {
      out[i + j] = add(out[i + j], mul(a[i], b[j]))
    }
  }
  out
}

///| RS生成多項式 g(x) = Π_{i=0}^{n-1} (x - α^i)
pub fn rs_generator(n : Int) -> Array[Int] {
  let mut g = [1]
  for i = 0; i < n; i = i + 1 {
    g = poly_mul(g, [1, exp(i)])
  }
  g
}

///| data * x^n_ec を g(x) で割った剰余 = ECコードワード
pub fn rs_encode(data : Array[Int], n_ec : Int) -> Array[Int] {
  let g = rs_generator(n_ec)
  let rem = Array::make(data.length() + n_ec, 0)
  for i = 0; i < data.length(); i = i + 1 {
    rem[i] = data[i]
  }
  for i = 0; i < data.length(); i = i + 1 {
    let factor = rem[i]
    if factor != 0 {
      for j = 1; j < g.length(); j = j + 1 {
        rem[i + j] = add(rem[i + j], mul(g[j], factor))
      }
    }
    rem[i] = 0
  }
  let ec = Array::make(n_ec, 0)
  for i = 0; i < n_ec; i = i + 1 {
    ec[i] = rem[data.length() + i]
  }
  ec
}
```

- [ ] **Step 4: 通過確認** — `moon test --target js` → PASS
- [ ] **Step 5: コミット** — `git add -A && git commit -m "feat(gf256): 多項式演算とRSエンコード"`

---

### Task 6: Reed-Solomon デコード（誤り訂正）

**Files:**
- Create: `core/src/gf256/rs_decode.mbt`, `core/src/gf256/rs_decode_test.mbt`

**Interfaces:**
- Consumes: `mul`, `div`, `add`, `exp`, `log`, `rs_encode`
- Produces: `pub fn rs_decode(msg : Array[Int], n_ec : Int) -> Array[Int]?` — 符号語（data+ec）を受け取り訂正済み符号語を返す。訂正不能なら `None`。Plan 2 のデコーダとフォーマット情報復号が利用。

- [ ] **Step 1: 失敗するテストを書く（プロパティテスト）**

`core/src/gf256/rs_decode_test.mbt`:
```moonbit
///| 決定的擬似乱数（テスト再現性のため seed 固定）
fn next_rand(state : Int) -> Int {
  (state * 1103515245 + 12345) & 0x7FFFFFFF
}

test "decode clean codeword unchanged" {
  let data = [10, 20, 30, 40, 50, 60, 70, 80]
  let ec = @gf256.rs_encode(data, 8)
  let msg = data.copy()
  for i = 0; i < ec.length(); i = i + 1 {
    msg.push(ec[i])
  }
  match @gf256.rs_decode(msg, 8) {
    Some(fixed) => assert_eq(fixed, msg)
    None => abort("clean codeword must decode")
  }
}

test "property: encode -> corrupt t bytes -> decode recovers (t <= n_ec/2)" {
  let mut seed = 12345
  for round = 0; round < 50; round = round + 1 {
    let n_data = 16
    let n_ec = 10 // 訂正能力 5
    let data : Array[Int] = []
    for i = 0; i < n_data; i = i + 1 {
      seed = next_rand(seed)
      data.push(seed % 256)
    }
    let ec = @gf256.rs_encode(data, n_ec)
    let original = data.copy()
    for i = 0; i < ec.length(); i = i + 1 {
      original.push(ec[i])
    }
    let corrupted = original.copy()
    seed = next_rand(seed)
    let n_errors = 1 + seed % 5 // 1..5 個
    // 相異なる位置を n_errors 個選んで値を必ず変える
    let used : Array[Int] = []
    let mut placed = 0
    while placed < n_errors {
      seed = next_rand(seed)
      let pos = seed % corrupted.length()
      if used.contains(pos) {
        continue
      }
      used.push(pos)
      seed = next_rand(seed)
      corrupted[pos] = corrupted[pos] ^ (1 + seed % 255)
      placed = placed + 1
    }
    match @gf256.rs_decode(corrupted, n_ec) {
      Some(fixed) => assert_eq(fixed, original)
      None => abort("must correct \{n_errors} errors")
    }
  }
}

test "too many errors returns None or wrong-detect" {
  // 訂正能力超過（6個 > 5）: None を返すか、少なくとも成功と偽らない実装で
  // あることを確認する（RSは超過時に誤訂正しうるが、シンドローム再検査で弾く）
  let data = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16]
  let ec = @gf256.rs_encode(data, 10)
  let msg = data.copy()
  for i = 0; i < ec.length(); i = i + 1 {
    msg.push(ec[i])
  }
  let corrupted = msg.copy()
  for i = 0; i < 6; i = i + 1 {
    corrupted[i * 2] = corrupted[i * 2] ^ 0xA5
  }
  match @gf256.rs_decode(corrupted, 10) {
    Some(fixed) => {
      // 誤訂正が返るならシンドロームは0のはず＝有効な符号語。
      // ただし元データと一致しないことは許容（RS理論上の限界）。
      // ここでは「クラッシュせず Option が返る」ことだけを確認。
      assert_true(fixed.length() == msg.length())
    }
    None => assert_true(true)
  }
}
```

- [ ] **Step 2: 失敗確認** — `moon test --target js` → FAIL
- [ ] **Step 3: 実装（シンドローム → Berlekamp-Massey → Chien → Forney）**

`core/src/gf256/rs_decode.mbt`:
```moonbit
///| シンドローム S_i = msg(α^i), i = 0..n_ec-1
fn calc_syndromes(msg : Array[Int], n_ec : Int) -> Array[Int] {
  let synd = Array::make(n_ec, 0)
  for i = 0; i < n_ec; i = i + 1 {
    let x = exp(i)
    let mut acc = 0
    for j = 0; j < msg.length(); j = j + 1 {
      acc = add(mul(acc, x), msg[j])
    }
    synd[i] = acc
  }
  synd
}

///| Berlekamp-Massey: エラーロケータ多項式 σ(x)（index 0 = 定数項 1）
fn find_error_locator(synd : Array[Int]) -> Array[Int]? {
  let mut err_loc = [1]
  let mut old_loc = [1]
  for i = 0; i < synd.length(); i = i + 1 {
    old_loc.push(0)
    let mut delta = synd[i]
    for j = 1; j < err_loc.length(); j = j + 1 {
      delta = add(delta, mul(err_loc[err_loc.length() - 1 - j], synd[i - j]))
    }
    if delta != 0 {
      if old_loc.length() > err_loc.length() {
        let new_loc = scale_poly(old_loc, delta)
        old_loc = scale_poly(err_loc, div(1, delta))
        err_loc = new_loc
      }
      err_loc = poly_add_padded(err_loc, scale_poly(old_loc, delta))
    }
  }
  // 先頭の0を除去
  let mut lead = 0
  while lead < err_loc.length() - 1 && err_loc[lead] == 0 {
    lead = lead + 1
  }
  let trimmed : Array[Int] = []
  for i = lead; i < err_loc.length(); i = i + 1 {
    trimmed.push(err_loc[i])
  }
  let n_errors = trimmed.length() - 1
  if n_errors * 2 > synd.length() {
    None
  } else {
    Some(trimmed)
  }
}

fn scale_poly(p : Array[Int], k : Int) -> Array[Int] {
  let out : Array[Int] = []
  for i = 0; i < p.length(); i = i + 1 {
    out.push(mul(p[i], k))
  }
  out
}

///| 右詰めで加算（次数を揃えて XOR）
fn poly_add_padded(a : Array[Int], b : Array[Int]) -> Array[Int] {
  let n = if a.length() > b.length() { a.length() } else { b.length() }
  let out = Array::make(n, 0)
  for i = 0; i < a.length(); i = i + 1 {
    out[n - a.length() + i] = a[i]
  }
  for i = 0; i < b.length(); i = i + 1 {
    let idx = n - b.length() + i
    out[idx] = add(out[idx], b[i])
  }
  out
}

///| Chien search: σ(α^{-i}) = 0 となる位置 i（符号語末尾からの冪）を列挙
fn find_error_positions(err_loc : Array[Int], msg_len : Int) -> Array[Int]? {
  let n_errors = err_loc.length() - 1
  let positions : Array[Int] = []
  for i = 0; i < msg_len; i = i + 1 {
    // x = α^i における評価（位置は末尾基準の冪 i に対応）
    let x = exp(i)
    let mut acc = 0
    for j = 0; j < err_loc.length(); j = j + 1 {
      acc = add(mul(acc, x), err_loc[j])
    }
    if acc == 0 {
      positions.push(msg_len - 1 - i)
    }
  }
  if positions.length() != n_errors {
    None
  } else {
    Some(positions)
  }
}

///| Forney: エラー値を計算し訂正
fn correct_errors(
  msg : Array[Int],
  synd : Array[Int],
  err_loc : Array[Int],
  positions : Array[Int],
) -> Array[Int]? {
  // エラーエバリュエータ Ω(x) = [S(x)·σ(x)] mod x^n_ec
  // S(x) は S_0 を最低次とする（index 0 = 最高次表現に変換して poly_mul）
  let synd_rev : Array[Int] = []
  for i = synd.length() - 1; i >= 0; i = i - 1 {
    synd_rev.push(synd[i])
  }
  let omega_full = poly_mul(synd_rev, err_loc)
  // mod x^n_ec: 低次側 n_ec 個を残す（配列は先頭=最高次なので末尾 n_ec 個）
  let omega : Array[Int] = []
  let start = omega_full.length() - synd.length()
  for i = start; i < omega_full.length(); i = i + 1 {
    omega.push(omega_full[i])
  }
  // σ'(x): 形式微分（GF(2^8)では偶数次の項が消える）
  let deriv : Array[Int] = []
  let deg = err_loc.length() - 1
  for i = 0; i < err_loc.length() - 1; i = i + 1 {
    let power = deg - i // この係数の次数
    if power % 2 == 1 {
      deriv.push(err_loc[i])
    } else {
      deriv.push(0)
    }
  }
  // deriv は x で1次下げた多項式として評価する（下の eval で x^2 刻みに対応）
  let out = msg.copy()
  for k = 0; k < positions.length(); k = k + 1 {
    let pos = positions[k]
    let x_inv_log = msg.length() - 1 - pos // α^{i}, i = 末尾からの冪
    let x = exp(x_inv_log)
    let x_inv = div(1, x)
    // Ω(x^{-1})
    let mut om = 0
    for j = 0; j < omega.length(); j = j + 1 {
      om = add(mul(om, x_inv), omega[j])
    }
    // σ'(x^{-1}) を直接評価（deriv の各項は元の次数-1）
    let mut dv = 0
    for j = 0; j < deriv.length(); j = j + 1 {
      dv = add(mul(dv, x_inv), deriv[j])
    }
    if dv == 0 {
      return None
    }
    let magnitude = mul(x, div(om, dv))
    out[pos] = add(out[pos], magnitude)
  }
  Some(out)
}

///| RS復号: 訂正済み符号語を返す。訂正不能は None。
pub fn rs_decode(msg : Array[Int], n_ec : Int) -> Array[Int]? {
  let synd = calc_syndromes(msg, n_ec)
  let mut clean = true
  for i = 0; i < synd.length(); i = i + 1 {
    if synd[i] != 0 {
      clean = false
    }
  }
  if clean {
    return Some(msg)
  }
  match find_error_locator(synd) {
    None => None
    Some(err_loc) =>
      match find_error_positions(err_loc, msg.length()) {
        None => None
        Some(positions) =>
          match correct_errors(msg, synd, err_loc, positions) {
            None => None
            Some(fixed) => {
              // 検証ゲート: 訂正後のシンドロームが全0でなければ失敗扱い
              let synd2 = calc_syndromes(fixed, n_ec)
              let mut ok = true
              for i = 0; i < synd2.length(); i = i + 1 {
                if synd2[i] != 0 {
                  ok = false
                }
              }
              if ok {
                Some(fixed)
              } else {
                None
              }
            }
          }
      }
  }
}
```

**実装ノート:** Forney の指数の取り回し（`x` と `x_inv` のどちらで評価するか、σ' の次数下げ）は符号の定義（α^0 起点・評価方向）に依存して符号ミスが出やすい。プロパティテストが落ちたら wikiversity "Reed–Solomon codes for coders" の定義と突き合わせて修正すること。**テストを弱めて通すのは禁止**（anti-gaming）。

- [ ] **Step 4: 通過確認** — `moon test --target js` → PASS（プロパティ50ラウンド含む）
- [ ] **Step 5: コミット** — `git add -A && git commit -m "feat(gf256): RS復号（BM+Chien+Forney）とプロパティテスト"`

---

### Task 7: BitWriter とセグメント符号化

**Files:**
- Create: `core/src/encode/moon.pkg.json`, `core/src/encode/bitwriter.mbt`, `core/src/encode/segment.mbt`
- Test: `core/src/encode/bitwriter_test.mbt`, `core/src/encode/segment_test.mbt`

**Interfaces:**
- Produces:
  - `BitWriter`: `pub fn BitWriter::new() -> BitWriter` / `pub fn write(self, value : Int, bits : Int) -> Unit` / `pub fn to_codewords(self) -> Array[Int]` / `pub fn bit_length(self) -> Int`
  - `pub enum Mode { Numeric; Alphanumeric; Byte }` / `pub fn detect_mode(text : String) -> Mode`
  - `pub fn utf8_encode(text : String) -> Array[Int]`
  - `pub fn write_segment(w : BitWriter, text : String, mode : Mode, version : Int) -> Unit`（モード指示子4bit＋文字数指示子＋データ）
  - `pub fn cci_bits(mode : Mode, version : Int) -> Int`

`core/src/encode/moon.pkg.json`:
```json
{
  "import": [{ "path": "naoto24kawa/moonqr/gf256", "alias": "gf256" }]
}
```

- [ ] **Step 1: 失敗するテストを書く**

`core/src/encode/bitwriter_test.mbt`:
```moonbit
test "bitwriter packs msb first" {
  let w = @encode.BitWriter::new()
  w.write(0b0100, 4)  // byte mode indicator
  w.write(3, 8)       // 長さ3
  assert_eq(w.bit_length(), 12)
  let cw = w.to_codewords() // 8bit境界までは0詰めせず、to_codewordsで末尾0詰め
  assert_eq(cw, [0b01000000, 0b00110000])
}
```

`core/src/encode/segment_test.mbt`:
```moonbit
test "mode detection" {
  assert_eq(@encode.detect_mode("0123456789"), @encode.Mode::Numeric)
  assert_eq(@encode.detect_mode("HELLO WORLD $1"), @encode.Mode::Alphanumeric)
  assert_eq(@encode.detect_mode("hello"), @encode.Mode::Byte) // 小文字はalnum外
  assert_eq(@encode.detect_mode("こんにちは"), @encode.Mode::Byte)
}

test "cci bits per version range" {
  assert_eq(@encode.cci_bits(@encode.Mode::Numeric, 1), 10)
  assert_eq(@encode.cci_bits(@encode.Mode::Numeric, 10), 12)
  assert_eq(@encode.cci_bits(@encode.Mode::Numeric, 27), 14)
  assert_eq(@encode.cci_bits(@encode.Mode::Alphanumeric, 1), 9)
  assert_eq(@encode.cci_bits(@encode.Mode::Byte, 1), 8)
  assert_eq(@encode.cci_bits(@encode.Mode::Byte, 10), 16)
}

test "numeric segment: 01234567 -> known bit pattern" {
  // ISO 18004 の古典例: "01234567" numeric v1
  // 012=0000001100, 345=0101011001, 67=1000011
  let w = @encode.BitWriter::new()
  @encode.write_segment(w, "01234567", @encode.Mode::Numeric, 1)
  // mode(0001) + cci(0000001000=8) + data
  assert_eq(w.bit_length(), 4 + 10 + 10 + 10 + 7)
}

test "alphanumeric segment: AC-42" {
  // A=10,C=12 -> 10*45+12=462; -=41,4=4 -> 41*45+4=1849; 2=2
  let w = @encode.BitWriter::new()
  @encode.write_segment(w, "AC-42", @encode.Mode::Alphanumeric, 1)
  assert_eq(w.bit_length(), 4 + 9 + 11 + 11 + 6)
}

test "utf8 encode multibyte" {
  assert_eq(@encode.utf8_encode("A"), [0x41])
  assert_eq(@encode.utf8_encode("é"), [0xC3, 0xA9])
  assert_eq(@encode.utf8_encode("あ"), [0xE3, 0x81, 0x82])
  assert_eq(@encode.utf8_encode("🦑"), [0xF0, 0x9F, 0xA6, 0x91])
}
```

- [ ] **Step 2: 失敗確認** — `moon test --target js` → FAIL
- [ ] **Step 3: 実装**

`core/src/encode/bitwriter.mbt`:
```moonbit
pub struct BitWriter {
  mut bits : Array[Bool]
}

pub fn BitWriter::new() -> BitWriter {
  { bits: [] }
}

///| value の下位 bits ビットを MSB から書き込む
pub fn write(self : BitWriter, value : Int, bits : Int) -> Unit {
  for i = bits - 1; i >= 0; i = i - 1 {
    self.bits.push(((value >> i) & 1) == 1)
  }
}

pub fn bit_length(self : BitWriter) -> Int {
  self.bits.length()
}

///| 8bit単位に詰める（端数は0詰め）
pub fn to_codewords(self : BitWriter) -> Array[Int] {
  let out : Array[Int] = []
  let mut cur = 0
  let mut n = 0
  for i = 0; i < self.bits.length(); i = i + 1 {
    cur = (cur << 1) | (if self.bits[i] { 1 } else { 0 })
    n = n + 1
    if n == 8 {
      out.push(cur)
      cur = 0
      n = 0
    }
  }
  if n > 0 {
    out.push(cur << (8 - n))
  }
  out
}
```

`core/src/encode/segment.mbt`:
```moonbit
pub enum Mode {
  Numeric
  Alphanumeric
  Byte
} derive(Eq, Show)

///| 英数字モードの文字集合における index。非対応は -1
fn alnum_index(c : Char) -> Int {
  let code = c.to_int()
  if code >= 48 && code <= 57 {
    code - 48 // 0-9
  } else if code >= 65 && code <= 90 {
    code - 65 + 10 // A-Z
  } else {
    match c {
      ' ' => 36
      '$' => 37
      '%' => 38
      '*' => 39
      '+' => 40
      '-' => 41
      '.' => 42
      '/' => 43
      ':' => 44
      _ => -1
    }
  }
}

pub fn detect_mode(text : String) -> Mode {
  let mut numeric = true
  let mut alnum = true
  for c in text {
    let code = c.to_int()
    if code < 48 || code > 57 {
      numeric = false
    }
    if alnum_index(c) < 0 {
      alnum = false
    }
  }
  if numeric {
    Mode::Numeric
  } else if alnum {
    Mode::Alphanumeric
  } else {
    Mode::Byte
  }
}

///| 文字数指示子のビット数（ISO 18004 Table 3）
pub fn cci_bits(mode : Mode, version : Int) -> Int {
  if version <= 9 {
    match mode {
      Mode::Numeric => 10
      Mode::Alphanumeric => 9
      Mode::Byte => 8
    }
  } else if version <= 26 {
    match mode {
      Mode::Numeric => 12
      Mode::Alphanumeric => 11
      Mode::Byte => 16
    }
  } else {
    match mode {
      Mode::Numeric => 14
      Mode::Alphanumeric => 13
      Mode::Byte => 16
    }
  }
}

pub fn utf8_encode(text : String) -> Array[Int] {
  let out : Array[Int] = []
  for c in text {
    let cp = c.to_int()
    if cp < 0x80 {
      out.push(cp)
    } else if cp < 0x800 {
      out.push(0xC0 | (cp >> 6))
      out.push(0x80 | (cp & 0x3F))
    } else if cp < 0x10000 {
      out.push(0xE0 | (cp >> 12))
      out.push(0x80 | ((cp >> 6) & 0x3F))
      out.push(0x80 | (cp & 0x3F))
    } else {
      out.push(0xF0 | (cp >> 18))
      out.push(0x80 | ((cp >> 12) & 0x3F))
      out.push(0x80 | ((cp >> 6) & 0x3F))
      out.push(0x80 | (cp & 0x3F))
    }
  }
  out
}

///| モード指示子＋文字数指示子＋データビットを書く
pub fn write_segment(
  w : BitWriter,
  text : String,
  mode : Mode,
  version : Int,
) -> Unit {
  match mode {
    Mode::Numeric => {
      w.write(0b0001, 4)
      let chars : Array[Char] = []
      for c in text {
        chars.push(c)
      }
      w.write(chars.length(), cci_bits(mode, version))
      let mut i = 0
      while i + 3 <= chars.length() {
        let v = (chars[i].to_int() - 48) * 100 +
          (chars[i + 1].to_int() - 48) * 10 + (chars[i + 2].to_int() - 48)
        w.write(v, 10)
        i = i + 3
      }
      let rest = chars.length() - i
      if rest == 2 {
        w.write((chars[i].to_int() - 48) * 10 + (chars[i + 1].to_int() - 48), 7)
      } else if rest == 1 {
        w.write(chars[i].to_int() - 48, 4)
      }
    }
    Mode::Alphanumeric => {
      w.write(0b0010, 4)
      let idx : Array[Int] = []
      for c in text {
        idx.push(alnum_index(c))
      }
      w.write(idx.length(), cci_bits(mode, version))
      let mut i = 0
      while i + 2 <= idx.length() {
        w.write(idx[i] * 45 + idx[i + 1], 11)
        i = i + 2
      }
      if i < idx.length() {
        w.write(idx[i], 6)
      }
    }
    Mode::Byte => {
      w.write(0b0100, 4)
      let bytes = utf8_encode(text)
      w.write(bytes.length(), cci_bits(mode, version))
      for i = 0; i < bytes.length(); i = i + 1 {
        w.write(bytes[i], 8)
      }
    }
  }
}
```

- [ ] **Step 4: 通過確認** — `moon test --target js` → PASS
- [ ] **Step 5: コミット** — `git add -A && git commit -m "feat(encode): BitWriterとセグメント符号化（numeric/alnum/byte+UTF-8）"`

---

### Task 8: 容量・RSブロック表の生成とデータコードワード組み立て

**Files:**
- Create: `scripts/gen-tables.mjs`, `core/src/encode/tables.mbt`（スクリプト生成）, `core/src/encode/assemble.mbt`
- Test: `core/src/encode/tables_test.mbt`, `core/src/encode/assemble_test.mbt`

**Interfaces:**
- Produces:
  - `pub fn rs_blocks(version : Int, ec : EcLevel) -> Array[(Int, Int)]` — (totalCount, dataCount) のブロック列
  - `pub fn data_capacity(version : Int, ec : EcLevel) -> Int` — データコードワード総数
  - `pub fn alignment_positions(version : Int) -> Array[Int]`
  - `pub enum EcLevel { L; M; Q; H }`
  - `pub fn assemble(bits : BitWriter, version : Int, ec : EcLevel) -> Array[Int]?` — 終端子・パディング（0xEC/0x11交互）・ブロック分割・RS計算・インターリーブ済み最終コードワード列。容量超過は `None`

- [ ] **Step 1: テーブル生成スクリプトを書く**

`scripts/gen-tables.mjs`:
```js
// qrcode-generator (MIT, kazuhikoarase) のソースから RS_BLOCK_TABLE と
// PATTERN_POSITION_TABLE を抽出して MoonBit コードを生成する。
// 出典コメントを生成ファイル先頭に付ける。
import { writeFileSync } from "node:fs";

const src = await (await fetch(
  "https://raw.githubusercontent.com/kazuhikoarase/qrcode-generator/master/js/qrcode.js"
)).text();

// RS_BLOCK_TABLE: [ [count,total,data](,...) ] × (40版 × L,M,Q,H)
const rsMatch = src.match(/RS_BLOCK_TABLE\s*=\s*\[([\s\S]*?)\];/);
const posMatch = src.match(/PATTERN_POSITION_TABLE\s*=\s*\[([\s\S]*?)\];/);
if (!rsMatch || !posMatch) throw new Error("table not found — ソース構造が変わった。手動確認せよ");

const rsRows = JSON.parse("[" + rsMatch[1].replace(/\/\/[^\n]*/g, "") + "]");
// qrcode-generator の並びは (version-1)*4 + [L,M,Q,H] index。3個組の繰り返し。
const posRows = JSON.parse("[" + posMatch[1].replace(/\/\/[^\n]*/g, "") + "]");

let mbt = `///| このファイルは scripts/gen-tables.mjs により生成。手編集禁止。
///| 出典: qrcode-generator (MIT) https://github.com/kazuhikoarase/qrcode-generator

pub enum EcLevel {
  L
  M
  Q
  H
} derive(Eq, Show)

fn ec_index(ec : EcLevel) -> Int {
  match ec {
    EcLevel::L => 0
    EcLevel::M => 1
    EcLevel::Q => 2
    EcLevel::H => 3
  }
}

///| (totalCount, dataCount) のブロック列。version 1..40
pub fn rs_blocks(version : Int, ec : EcLevel) -> Array[(Int, Int)] {
  let row = rs_block_row((version - 1) * 4 + ec_index(ec))
  let out : Array[(Int, Int)] = []
  let mut i = 0
  while i < row.length() {
    let count = row[i]
    for k = 0; k < count; k = k + 1 {
      out.push((row[i + 1], row[i + 2]))
    }
    i = i + 3
  }
  out
}

pub fn data_capacity(version : Int, ec : EcLevel) -> Int {
  let blocks = rs_blocks(version, ec)
  let mut sum = 0
  for i = 0; i < blocks.length(); i = i + 1 {
    let (_, data) = blocks[i]
    sum = sum + data
  }
  sum
}

pub fn alignment_positions(version : Int) -> Array[Int] {
  pattern_position_row(version - 1)
}

fn rs_block_row(idx : Int) -> Array[Int] {
  match idx {
`;
for (let i = 0; i < 160; i++) {
  const row = rsRows[i];
  mbt += `    ${i} => [${row.join(", ")}]\n`;
}
mbt += `    _ => abort("invalid rs block index")
  }
}

fn pattern_position_row(idx : Int) -> Array[Int] {
  match idx {
`;
for (let i = 0; i < 40; i++) {
  mbt += `    ${i} => [${posRows[i].join(", ")}]\n`;
}
mbt += `    _ => abort("invalid version")
  }
}
`;
writeFileSync("core/src/encode/tables.mbt", mbt);
console.log("generated core/src/encode/tables.mbt");
```

Run: `node scripts/gen-tables.mjs`
Expected: `core/src/encode/tables.mbt` 生成。**注意: qrcode-generator の実際のテーブル構造（1版あたりのエントリが可変長か、行がフラットか）を必ずソースで確認し、スクリプトを実態に合わせること。** JSON.parse が通らない形式なら正規表現を調整。

- [ ] **Step 2: テーブルの検証テスト**

`core/src/encode/tables_test.mbt`:
```moonbit
test "known capacities from ISO 18004" {
  // 有名な既知値でテーブル全体の並び順ミスを検出する
  assert_eq(@encode.data_capacity(1, @encode.EcLevel::L), 19)
  assert_eq(@encode.data_capacity(1, @encode.EcLevel::M), 16)
  assert_eq(@encode.data_capacity(1, @encode.EcLevel::Q), 13)
  assert_eq(@encode.data_capacity(1, @encode.EcLevel::H), 9)
  assert_eq(@encode.data_capacity(40, @encode.EcLevel::L), 2956)
}

test "total codewords match version formula for all versions" {
  // 総コードワード数 = 全ブロックの totalCount 合計。
  // version の総モジュール数から導かれる既知系列と一致すること
  // (v1=26, v2=44, v3=70, ..., v40=3706)
  let expected_v1_to_5 = [26, 44, 70, 100, 134]
  for v = 1; v <= 5; v = v + 1 {
    let blocks = @encode.rs_blocks(v, @encode.EcLevel::M)
    let mut total = 0
    for i = 0; i < blocks.length(); i = i + 1 {
      let (t, _) = blocks[i]
      total = total + t
    }
    assert_eq(total, expected_v1_to_5[v - 1])
  }
}

test "alignment positions" {
  assert_eq(@encode.alignment_positions(1), [])
  assert_eq(@encode.alignment_positions(2), [6, 18])
  assert_eq(@encode.alignment_positions(7), [6, 22, 38])
}
```

Run: `moon test --target js` → PASS（失敗したらテーブル抽出の並び順を修正）

- [ ] **Step 3: assemble の失敗するテストを書く**

`core/src/encode/assemble_test.mbt`:
```moonbit
test "assemble pads with ec11 pattern and interleaves" {
  // v1-M: data 16 codewords, ec 10 codewords, 1ブロック → 26個
  let w = @encode.BitWriter::new()
  @encode.write_segment(w, "01234567", @encode.Mode::Numeric, 1)
  match @encode.assemble(w, 1, @encode.EcLevel::M) {
    Some(cw) => {
      assert_eq(cw.length(), 26)
      // 先頭: 0001 0000001000 ... の詰め結果（ISO 18004 の古典例）
      assert_eq(cw[0], 0b00010000)
      assert_eq(cw[1], 0b00100000)
      // パディングは 0xEC, 0x11 交互
      assert_eq(cw[14], 0xEC)
      assert_eq(cw[15], 0x11)
    }
    None => abort("must fit in v1-M")
  }
}

test "assemble returns None when over capacity" {
  let w = @encode.BitWriter::new()
  let long = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA" // 40文字 > v1-H
  @encode.write_segment(w, long, @encode.Mode::Alphanumeric, 1)
  match @encode.assemble(w, 1, @encode.EcLevel::H) {
    Some(_) => abort("must overflow")
    None => assert_true(true)
  }
}
```

- [ ] **Step 4: 失敗確認 → 実装**

`core/src/encode/assemble.mbt`:
```moonbit
///| 終端子(最大4bit)→8bit境界0詰め→0xEC/0x11交互パディング→
///| ブロック分割→RS→インターリーブ
pub fn assemble(bits : BitWriter, version : Int, ec : EcLevel) -> Array[Int]? {
  let cap_bits = data_capacity(version, ec) * 8
  if bits.bit_length() > cap_bits {
    return None
  }
  // 終端子: 残り容量と4bitの小さい方
  let term = if cap_bits - bits.bit_length() < 4 {
    cap_bits - bits.bit_length()
  } else {
    4
  }
  bits.write(0, term)
  let data = bits.to_codewords()
  let n_data = data_capacity(version, ec)
  let mut pad_toggle = true
  while data.length() < n_data {
    data.push(if pad_toggle { 0xEC } else { 0x11 })
    pad_toggle = not(pad_toggle)
  }
  // ブロック分割 + RS
  let blocks = rs_blocks(version, ec)
  let data_blocks : Array[Array[Int]] = []
  let ec_blocks : Array[Array[Int]] = []
  let mut offset = 0
  for i = 0; i < blocks.length(); i = i + 1 {
    let (total, dcount) = blocks[i]
    let d : Array[Int] = []
    for j = 0; j < dcount; j = j + 1 {
      d.push(data[offset + j])
    }
    offset = offset + dcount
    data_blocks.push(d)
    ec_blocks.push(@gf256.rs_encode(d, total - dcount))
  }
  // インターリーブ: 各ブロックの i 番目を順に
  let out : Array[Int] = []
  let mut max_d = 0
  for i = 0; i < data_blocks.length(); i = i + 1 {
    if data_blocks[i].length() > max_d {
      max_d = data_blocks[i].length()
    }
  }
  for i = 0; i < max_d; i = i + 1 {
    for b = 0; b < data_blocks.length(); b = b + 1 {
      if i < data_blocks[b].length() {
        out.push(data_blocks[b][i])
      }
    }
  }
  let mut max_e = 0
  for i = 0; i < ec_blocks.length(); i = i + 1 {
    if ec_blocks[i].length() > max_e {
      max_e = ec_blocks[i].length()
    }
  }
  for i = 0; i < max_e; i = i + 1 {
    for b = 0; b < ec_blocks.length(); b = b + 1 {
      if i < ec_blocks[b].length() {
        out.push(ec_blocks[b][i])
      }
    }
  }
  Some(out)
}
```

Run: `moon test --target js` → PASS

- [ ] **Step 5: コミット** — `git add -A && git commit -m "feat(encode): RS表生成スクリプトとコードワード組み立て"`

---

### Task 9: 行列レイアウト（機能パターン配置）

**Files:**
- Create: `core/src/encode/matrix.mbt`
- Test: `core/src/encode/matrix_test.mbt`

**Interfaces:**
- Produces:
  - `pub struct Matrix { size : Int; ... }` — `pub fn Matrix::new(version : Int) -> Matrix` / `pub fn get(self, x : Int, y : Int) -> Bool` / `pub fn set(self, x : Int, y : Int, v : Bool) -> Unit` / `pub fn is_function(self, x : Int, y : Int) -> Bool`
  - `pub fn place_function_patterns(m : Matrix, version : Int) -> Unit` — ファインダ＋セパレータ・タイミング・アライメント・ダークモジュール・フォーマット/バージョン領域の予約
  - `pub fn place_data(m : Matrix, codewords : Array[Int]) -> Unit` — ジグザグ配置

- [ ] **Step 1: 失敗するテストを書く**

`core/src/encode/matrix_test.mbt`:
```moonbit
test "v1 matrix is 21x21 with finder patterns" {
  let m = @encode.Matrix::new(1)
  assert_eq(m.size, 21)
  @encode.place_function_patterns(m, 1)
  // ファインダ外周は黒
  assert_true(m.get(0, 0))
  assert_true(m.get(6, 0))
  assert_true(m.get(0, 6))
  // ファインダ内白リング
  assert_false(m.get(1, 1))
  // 中心3x3は黒
  assert_true(m.get(3, 3))
  // 右上ファインダ
  assert_true(m.get(20, 0))
  // タイミングパターン（交互）
  assert_true(m.get(8, 6))   // x=8 は黒（偶数=黒: (6,8)側で確認）
  assert_false(m.get(9, 6))
  // ダークモジュール (8, 4*1+9=13)
  assert_true(m.get(8, 13))
}

test "function area is reserved" {
  let m = @encode.Matrix::new(1)
  @encode.place_function_patterns(m, 1)
  assert_true(m.is_function(0, 0))    // ファインダ
  assert_true(m.is_function(8, 0))    // フォーマット領域
  assert_true(m.is_function(6, 10))   // タイミング
  assert_false(m.is_function(10, 10)) // データ領域
}

test "v2 has alignment pattern at (18,18)" {
  let m = @encode.Matrix::new(2)
  @encode.place_function_patterns(m, 2)
  assert_true(m.get(18, 18))          // 中心黒
  assert_false(m.get(17, 18))         // 白リング
  assert_true(m.get(16, 16))          // 外周黒
}

test "place_data fills all non-function modules" {
  let m = @encode.Matrix::new(1)
  @encode.place_function_patterns(m, 1)
  // v1 のデータモジュール数 = 26 codewords * 8 = 208
  let cw : Array[Int] = []
  for i = 0; i < 26; i = i + 1 {
    cw.push(0xFF) // 全1で埋めれば全データ位置が黒になる
  }
  @encode.place_data(m, cw)
  let mut dark_data = 0
  for y = 0; y < 21; y = y + 1 {
    for x = 0; x < 21; x = x + 1 {
      if not(m.is_function(x, y)) && m.get(x, y) {
        dark_data = dark_data + 1
      }
    }
  }
  assert_eq(dark_data, 208)
}
```

- [ ] **Step 2: 失敗確認** — FAIL
- [ ] **Step 3: 実装**

`core/src/encode/matrix.mbt`:
```moonbit
pub struct Matrix {
  size : Int
  modules : FixedArray[Bool]
  function : FixedArray[Bool] // 機能パターン領域（データ配置対象外）
}

pub fn Matrix::new(version : Int) -> Matrix {
  let size = version * 4 + 17
  {
    size,
    modules: FixedArray::make(size * size, false),
    function: FixedArray::make(size * size, false),
  }
}

pub fn get(self : Matrix, x : Int, y : Int) -> Bool {
  self.modules[y * self.size + x]
}

pub fn set(self : Matrix, x : Int, y : Int, v : Bool) -> Unit {
  self.modules[y * self.size + x] = v
}

pub fn is_function(self : Matrix, x : Int, y : Int) -> Bool {
  self.function[y * self.size + x]
}

fn set_function(self : Matrix, x : Int, y : Int, v : Bool) -> Unit {
  self.set(x, y, v)
  self.function[y * self.size + x] = true
}

///| 7x7 ファインダ＋白セパレータを (ox, oy) 起点で描く
fn place_finder(m : Matrix, ox : Int, oy : Int) -> Unit {
  for dy = -1; dy <= 7; dy = dy + 1 {
    for dx = -1; dx <= 7; dx = dx + 1 {
      let x = ox + dx
      let y = oy + dy
      if x >= 0 && x < m.size && y >= 0 && y < m.size {
        let in7 = dx >= 0 && dx <= 6 && dy >= 0 && dy <= 6
        let dark = in7 &&
          (dx == 0 || dx == 6 || dy == 0 || dy == 6 ||
          (dx >= 2 && dx <= 4 && dy >= 2 && dy <= 4))
        m.set_function(x, y, dark)
      }
    }
  }
}

pub fn place_function_patterns(m : Matrix, version : Int) -> Unit {
  place_finder(m, 0, 0)
  place_finder(m, m.size - 7, 0)
  place_finder(m, 0, m.size - 7)
  // タイミングパターン（row/col 6、偶数座標が黒）
  for i = 8; i < m.size - 8; i = i + 1 {
    let dark = i % 2 == 0
    if not(m.is_function(i, 6)) {
      m.set_function(i, 6, dark)
    }
    if not(m.is_function(6, i)) {
      m.set_function(6, i, dark)
    }
  }
  // アライメントパターン（ファインダと重なる位置は除外）
  let pos = alignment_positions(version)
  for a = 0; a < pos.length(); a = a + 1 {
    for b = 0; b < pos.length(); b = b + 1 {
      let cx = pos[a]
      let cy = pos[b]
      // 3つのファインダ位置と重なるものはスキップ
      let overlaps = (cx <= 8 && cy <= 8) ||
        (cx >= m.size - 9 && cy <= 8) || (cx <= 8 && cy >= m.size - 9)
      if not(overlaps) {
        for dy = -2; dy <= 2; dy = dy + 1 {
          for dx = -2; dx <= 2; dx = dx + 1 {
            let dark = dx == -2 || dx == 2 || dy == -2 || dy == 2 ||
              (dx == 0 && dy == 0)
            m.set_function(cx + dx, cy + dy, dark)
          }
        }
      }
    }
  }
  // ダークモジュール
  m.set_function(8, version * 4 + 9, true)
  // フォーマット情報領域の予約（値は Task 10 で書く）
  for i = 0; i <= 8; i = i + 1 {
    if not(m.is_function(i, 8)) {
      m.set_function(i, 8, false)
    }
    if not(m.is_function(8, i)) {
      m.set_function(8, i, false)
    }
  }
  for i = 0; i < 8; i = i + 1 {
    if not(m.is_function(m.size - 1 - i, 8)) {
      m.set_function(m.size - 1 - i, 8, false)
    }
    if not(m.is_function(8, m.size - 1 - i)) {
      m.set_function(8, m.size - 1 - i, false)
    }
  }
  // バージョン情報領域（v7+、6x3 を2箇所）予約
  if version >= 7 {
    for i = 0; i < 6; i = i + 1 {
      for j = 0; j < 3; j = j + 1 {
        m.set_function(i, m.size - 11 + j, false)
        m.set_function(m.size - 11 + j, i, false)
      }
    }
  }
}

///| データビットを右下から2列単位のジグザグで配置（col 6 スキップ）
pub fn place_data(m : Matrix, codewords : Array[Int]) -> Unit {
  let mut bit_index = 0
  let total_bits = codewords.length() * 8
  let mut col = m.size - 1
  let mut upward = true
  while col > 0 {
    if col == 6 {
      col = col - 1 // タイミング列をスキップ
    }
    for step = 0; step < m.size; step = step + 1 {
      let y = if upward { m.size - 1 - step } else { step }
      for dx = 0; dx < 2; dx = dx + 1 {
        let x = col - dx
        if not(m.is_function(x, y)) && bit_index < total_bits {
          let cw = codewords[bit_index / 8]
          let bit = ((cw >> (7 - bit_index % 8)) & 1) == 1
          m.set(x, y, bit)
          bit_index = bit_index + 1
        }
      }
    }
    upward = not(upward)
    col = col - 2
  }
}
```

- [ ] **Step 4: 通過確認** — `moon test --target js` → PASS
- [ ] **Step 5: コミット** — `git add -A && git commit -m "feat(encode): 行列レイアウト（機能パターン・ジグザグ配置）"`

---

### Task 10: フォーマット/バージョン情報（BCH）

**Files:**
- Create: `core/src/encode/format.mbt`
- Test: `core/src/encode/format_test.mbt`

**Interfaces:**
- Consumes: `Matrix`, `EcLevel`
- Produces: `pub fn format_bits(ec : EcLevel, mask : Int) -> Int`（15bit）/ `pub fn version_bits(version : Int) -> Int`（18bit）/ `pub fn place_format(m : Matrix, ec : EcLevel, mask : Int) -> Unit` / `pub fn place_version(m : Matrix, version : Int) -> Unit`

- [ ] **Step 1: 失敗するテストを書く**

`core/src/encode/format_test.mbt`:
```moonbit
test "format bits known vector" {
  // ISO 18004 の例: M(00) + mask 101 -> 101010000010010 (0x5412 XOR後)
  // 既知: L/mask0 は 0b111011111000100
  assert_eq(@encode.format_bits(@encode.EcLevel::L, 0), 0b111011111000100)
  assert_eq(@encode.format_bits(@encode.EcLevel::M, 5), 0b100000011001110)
}

test "version bits known vector" {
  // ISO 18004: v7 -> 000111110010010100
  assert_eq(@encode.version_bits(7), 0b000111110010010100)
}
```

**注意: 既知ベクタは https://www.thonky.com/qr-code-tutorial/format-version-tables の表と照合して転記ミスがないか確認してから使う。** 照合結果が計画記載値と異なる場合は表の値を正とする。

- [ ] **Step 2: 失敗確認 → 実装**

`core/src/encode/format.mbt`:
```moonbit
///| BCH(15,5): 5bit情報 + 10bit誤り訂正、生成多項式 0x537、マスク 0x5412
pub fn format_bits(ec : EcLevel, mask : Int) -> Int {
  let ec_bits = match ec {
    EcLevel::L => 0b01
    EcLevel::M => 0b00
    EcLevel::Q => 0b11
    EcLevel::H => 0b10
  }
  let data = (ec_bits << 3) | mask
  let mut rem = data
  for i = 0; i < 10; i = i + 1 {
    rem = (rem << 1) ^ (if (rem >> 9) != 0 { 0x537 } else { 0 })
  }
  ((data << 10) | (rem & 0x3FF)) ^ 0x5412
}

///| BCH(18,6): 生成多項式 0x1F25
pub fn version_bits(version : Int) -> Int {
  let mut rem = version
  for i = 0; i < 12; i = i + 1 {
    rem = (rem << 1) ^ (if (rem >> 11) != 0 { 0x1F25 } else { 0 })
  }
  (version << 12) | (rem & 0xFFF)
}

///| フォーマット情報15bitを2系統の位置に書き込む（bit14 が先頭）
pub fn place_format(m : Matrix, ec : EcLevel, mask : Int) -> Unit {
  let bits = format_bits(ec, mask)
  let get_bit = fn(i : Int) -> Bool { ((bits >> i) & 1) == 1 }
  // 第1系統: 左上（タイミング行列 (6) を飛ばす標準配置）
  // bit 0..5 -> (8, 0..5), bit 6 -> (8,7), bit 7 -> (8,8), bit 8 -> (7,8),
  // bit 9..14 -> (5..0, 8)
  for i = 0; i <= 5; i = i + 1 {
    m.set_function(8, i, get_bit(i))
  }
  m.set_function(8, 7, get_bit(6))
  m.set_function(8, 8, get_bit(7))
  m.set_function(7, 8, get_bit(8))
  for i = 9; i <= 14; i = i + 1 {
    m.set_function(14 - i, 8, get_bit(i))
  }
  // 第2系統: bit 0..7 -> (size-1..size-8, 8), bit 8..14 -> (8, size-7..size-1)
  for i = 0; i <= 7; i = i + 1 {
    m.set_function(m.size - 1 - i, 8, get_bit(i))
  }
  for i = 8; i <= 14; i = i + 1 {
    m.set_function(8, m.size - 15 + i, get_bit(i))
  }
}

///| バージョン情報18bit（v7+）: 左下 3x6 と右上 6x3
pub fn place_version(m : Matrix, version : Int) -> Unit {
  if version < 7 {
    return
  }
  let bits = version_bits(version)
  for i = 0; i < 18; i = i + 1 {
    let bit = ((bits >> i) & 1) == 1
    let a = i / 3
    let b = i % 3
    m.set_function(a, m.size - 11 + b, bit) // 左下
    m.set_function(m.size - 11 + b, a, bit) // 右上
  }
}
```

Run: `moon test --target js` → PASS

- [ ] **Step 3: コミット** — `git add -A && git commit -m "feat(encode): フォーマット/バージョン情報（BCH）"`

---

### Task 11: マスクとペナルティ評価

**Files:**
- Create: `core/src/encode/mask.mbt`
- Test: `core/src/encode/mask_test.mbt`

**Interfaces:**
- Produces: `pub fn mask_bit(mask : Int, x : Int, y : Int) -> Bool` / `pub fn apply_mask(m : Matrix, mask : Int) -> Unit`（データ領域のみ XOR）/ `pub fn penalty(m : Matrix) -> Int`（N1=3, N2=3, N3=40, N4=10 の4規則合計）/ `pub fn choose_mask(m : Matrix, ec : EcLevel) -> Int`（8種試行し最小ペナルティ。place_format を含めて評価）

- [ ] **Step 1: 失敗するテストを書く**

`core/src/encode/mask_test.mbt`:
```moonbit
test "mask conditions" {
  // mask 0: (x+y) % 2 == 0
  assert_true(@encode.mask_bit(0, 0, 0))
  assert_false(@encode.mask_bit(0, 1, 0))
  // mask 1: y % 2 == 0
  assert_true(@encode.mask_bit(1, 5, 0))
  // mask 6: ((x*y)%2 + (x*y)%3) % 2 == 0
  assert_true(@encode.mask_bit(6, 0, 0))
}

test "apply_mask twice is identity on data area" {
  let m = @encode.Matrix::new(1)
  @encode.place_function_patterns(m, 1)
  let cw : Array[Int] = []
  for i = 0; i < 26; i = i + 1 {
    cw.push(i * 7 % 256)
  }
  @encode.place_data(m, cw)
  let before : Array[Bool] = []
  for y = 0; y < 21; y = y + 1 {
    for x = 0; x < 21; x = x + 1 {
      before.push(m.get(x, y))
    }
  }
  @encode.apply_mask(m, 3)
  @encode.apply_mask(m, 3)
  for y = 0; y < 21; y = y + 1 {
    for x = 0; x < 21; x = x + 1 {
      assert_eq(m.get(x, y), before[y * 21 + x])
    }
  }
}

test "penalty rule examples" {
  // 全白 21x21: N1 = 行21本×(21-5+1)…ではなく「5連続で3点+超過1点/個」
  // 全白行1本 = 3 + (21-5) = 19点。行21+列21 = 798。N2 = 20*20*3=1200。
  // N4 = 全白なので |0-50|/5 = 10 -> 100点。
  let m = @encode.Matrix::new(1) // 全白・機能パターンなし
  let p = @encode.penalty(m)
  assert_eq(p, 798 + 1200 + 100)
}
```

- [ ] **Step 2: 失敗確認 → 実装**

`core/src/encode/mask.mbt`:
```moonbit
pub fn mask_bit(mask : Int, x : Int, y : Int) -> Bool {
  match mask {
    0 => (x + y) % 2 == 0
    1 => y % 2 == 0
    2 => x % 3 == 0
    3 => (x + y) % 3 == 0
    4 => (y / 2 + x / 3) % 2 == 0
    5 => x * y % 2 + x * y % 3 == 0
    6 => (x * y % 2 + x * y % 3) % 2 == 0
    _ => ((x + y) % 2 + x * y % 3) % 2 == 0
  }
}

///| データ領域（非機能領域）のみマスクXOR
pub fn apply_mask(m : Matrix, mask : Int) -> Unit {
  for y = 0; y < m.size; y = y + 1 {
    for x = 0; x < m.size; x = x + 1 {
      if not(m.is_function(x, y)) && mask_bit(mask, x, y) {
        m.set(x, y, not(m.get(x, y)))
      }
    }
  }
}

///| ISO 18004 の4ペナルティ規則
pub fn penalty(m : Matrix) -> Int {
  let mut score = 0
  // N1: 同色5連続以上（行・列）: 3 + 超過分
  for axis = 0; axis < 2; axis = axis + 1 {
    for a = 0; a < m.size; a = a + 1 {
      let mut run = 1
      for b = 1; b < m.size; b = b + 1 {
        let cur = if axis == 0 { m.get(b, a) } else { m.get(a, b) }
        let prev = if axis == 0 { m.get(b - 1, a) } else { m.get(a, b - 1) }
        if cur == prev {
          run = run + 1
          if run == 5 {
            score = score + 3
          } else if run > 5 {
            score = score + 1
          }
        } else {
          run = 1
        }
      }
    }
  }
  // N2: 2x2 同色ブロック: 3点/個
  for y = 0; y < m.size - 1; y = y + 1 {
    for x = 0; x < m.size - 1; x = x + 1 {
      let v = m.get(x, y)
      if m.get(x + 1, y) == v && m.get(x, y + 1) == v &&
        m.get(x + 1, y + 1) == v {
        score = score + 3
      }
    }
  }
  // N3: 1011101 の前後に 0000（ファインダ様）: 40点/個
  let pat1 = [true, false, true, true, true, false, true, false, false, false, false]
  let pat2 = [false, false, false, false, true, false, true, true, true, false, true]
  for axis = 0; axis < 2; axis = axis + 1 {
    for a = 0; a < m.size; a = a + 1 {
      for b = 0; b + 10 < m.size; b = b + 1 {
        let mut m1 = true
        let mut m2 = true
        for k = 0; k < 11; k = k + 1 {
          let v = if axis == 0 { m.get(b + k, a) } else { m.get(a, b + k) }
          if v != pat1[k] {
            m1 = false
          }
          if v != pat2[k] {
            m2 = false
          }
        }
        if m1 {
          score = score + 40
        }
        if m2 {
          score = score + 40
        }
      }
    }
  }
  // N4: 黒率の50%からの乖離 5%毎に10点
  let mut dark = 0
  for y = 0; y < m.size; y = y + 1 {
    for x = 0; x < m.size; x = x + 1 {
      if m.get(x, y) {
        dark = dark + 1
      }
    }
  }
  let total = m.size * m.size
  let percent = dark * 100 / total
  let dev = if percent >= 50 { percent - 50 } else { 50 - percent }
  score = score + dev / 5 * 10
  score
}

///| 8マスク試行して最小ペナルティを選択（フォーマット情報込みで評価）
pub fn choose_mask(m : Matrix, ec : EcLevel) -> Int {
  let mut best = 0
  let mut best_score = 0x7FFFFFFF
  for mask = 0; mask < 8; mask = mask + 1 {
    apply_mask(m, mask)
    place_format(m, ec, mask)
    let s = penalty(m)
    if s < best_score {
      best_score = s
      best = mask
    }
    apply_mask(m, mask) // 戻す
  }
  best
}
```

Run: `moon test --target js` → PASS

- [ ] **Step 3: コミット** — `git add -A && git commit -m "feat(encode): マスク8種とペナルティ評価"`

---

### Task 12: encode() façade と SVG 出力

**Files:**
- Create: `core/src/encode/encode.mbt`, `core/src/encode/svg.mbt`
- Test: `core/src/encode/encode_test.mbt`

**Interfaces:**
- Produces（Plan 3 の npm ラッパと Plan 2 のテストが利用する公開API）:
  - `pub fn encode(text : String, ec : EcLevel, version : Int?) -> Matrix?` — version None なら 1..40 から自動選択。容量超過は `None`
  - `pub fn to_svg_string(m : Matrix, margin : Int, cell : Int) -> String`

- [ ] **Step 1: 失敗するテストを書く**

`core/src/encode/encode_test.mbt`:
```moonbit
test "encode auto-selects smallest version" {
  match @encode.encode("01234567", @encode.EcLevel::M, None) {
    Some(m) => assert_eq(m.size, 21) // v1
    None => abort("must encode")
  }
}

test "encode long text picks bigger version" {
  let mut long = ""
  for i = 0; i < 100; i = i + 1 {
    long = long + "ABCDEFGH"
  } // 800文字 alnum
  match @encode.encode(long, @encode.EcLevel::M, None) {
    Some(m) => assert_true(m.size > 21)
    None => abort("must fit in some version")
  }
}

test "encode over capacity returns None" {
  let mut huge = ""
  for i = 0; i < 1000; i = i + 1 {
    huge = huge + "あいうえおかきくけこ"
  } // 30KB 超 -> v40 でも不可
  match @encode.encode(huge, @encode.EcLevel::L, None) {
    Some(_) => abort("must overflow")
    None => assert_true(true)
  }
}

test "svg output contains rect per dark module" {
  match @encode.encode("HI", @encode.EcLevel::M, None) {
    Some(m) => {
      let svg = @encode.to_svg_string(m, 4, 10)
      assert_true(svg.contains("<svg"))
      assert_true(svg.contains("</svg>"))
      assert_true(svg.contains("<path") || svg.contains("<rect"))
    }
    None => abort("must encode")
  }
}
```

- [ ] **Step 2: 失敗確認 → 実装**

`core/src/encode/encode.mbt`:
```moonbit
///| テキストをQR行列にエンコードする。
///| version=None は 1..40 から最小の収まるバージョンを自動選択。
///| 容量超過は None。
pub fn encode(text : String, ec : EcLevel, version : Int?) -> Matrix? {
  let mode = detect_mode(text)
  let try_version = fn(v : Int) -> Matrix? {
    let w = BitWriter::new()
    write_segment(w, text, mode, v)
    match assemble(w, v, ec) {
      None => None
      Some(cw) => {
        let m = Matrix::new(v)
        place_function_patterns(m, v)
        place_version(m, v)
        place_data(m, cw)
        let mask = choose_mask(m, ec)
        apply_mask(m, mask)
        place_format(m, ec, mask)
        Some(m)
      }
    }
  }
  match version {
    Some(v) => try_version(v)
    None => {
      // cci_bits がバージョン帯(1-9/10-26/27-40)で変わるため素直に線形試行
      for v = 1; v <= 40; v = v + 1 {
        match try_version(v) {
          Some(m) => return Some(m)
          None => continue
        }
      }
      None
    }
  }
}
```

`core/src/encode/svg.mbt`:
```moonbit
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
```

Run: `moon test --target js` → PASS

**パフォーマンス注記: 自動選択の線形試行（1..40）はエンコード1回あたり最悪40回の組み立てになるが、v1 では正しさ優先で許容（YAGNI）。**ビット長見積もりによる二分探索は必要が実証されてから。

- [ ] **Step 3: コミット** — `git add -A && git commit -m "feat(encode): encode façadeとSVG出力"`

---

### Task 13: `qrcode` npm との行列一致テスト（統合検証）

**Files:**
- Create: `packages/moonqr/test/matrix-parity.test.mjs`, `packages/moonqr/package.json`
- Modify: `core/src/encode/moon.pkg.json`（js export 追加）

**Interfaces:**
- Consumes: Task 12 の `encode` / ビルド成果物（js または決定バックエンド）
- Produces: エンコーダの外部実装一致の証明（v1 Done基準3の自動化部分）

- [ ] **Step 1: encode パッケージを JS から呼べるようにする**

`core/src/encode/moon.pkg.json` に追記:
```json
{
  "import": [{ "path": "naoto24kawa/moonqr/gf256", "alias": "gf256" }],
  "link": {
    "js": {
      "exports": ["encode_js"],
      "format": "esm"
    }
  }
}
```

`core/src/encode/encode.mbt` に JS 境界用の関数を追加（Matrix を平坦な Int 配列で返す）:
```moonbit
///| JS境界用: [size, m00, m01, ...] の平坦配列。エラー時は空配列。
///| ec: 0=L 1=M 2=Q 3=H, version: 0=auto
pub fn encode_js(text : String, ec : Int, version : Int) -> Array[Int] {
  let level = match ec {
    0 => EcLevel::L
    1 => EcLevel::M
    2 => EcLevel::Q
    _ => EcLevel::H
  }
  let v : Int? = if version == 0 { None } else { Some(version) }
  match encode(text, level, v) {
    None => []
    Some(m) => {
      let out : Array[Int] = [m.size]
      for y = 0; y < m.size; y = y + 1 {
        for x = 0; x < m.size; x = x + 1 {
          out.push(if m.get(x, y) { 1 } else { 0 })
        }
      }
      out
    }
  }
}
```

- [ ] **Step 2: パリティテストを書く**

`packages/moonqr/package.json`:
```json
{
  "name": "moonqr-parity-test",
  "private": true,
  "type": "module",
  "scripts": { "test": "node --test test/" }
}
```

`packages/moonqr/test/matrix-parity.test.mjs`:
```js
import { test } from "node:test";
import assert from "node:assert";
import QRCode from "qrcode";

// ビルド出力パスは実際の moon build 出力に合わせて調整
const mod = await import(
  "../../core/target/js/release/build/encode/encode.js");

const CASES = [
  ["01234567", "M"], ["HELLO WORLD", "Q"], ["hello, world!", "L"],
  ["https://example.com/path?q=1&r=2", "M"],
  ["こんにちは世界", "M"], ["🦑🐙", "H"],
  ["A".repeat(500), "L"], ["1".repeat(1000), "M"],
];
const EC_NUM = { L: 0, M: 1, Q: 2, H: 3 };

for (const [text, ec] of CASES) {
  for (let mask = 0; mask < 8; mask++) {
    test(`parity: ${JSON.stringify(text.slice(0, 20))} ec=${ec} mask=${mask}`, async () => {
      // qrcode npm に強制マスクで生成させ、バージョンを合わせて自前と比較
      const ref = QRCode.create(text, {
        errorCorrectionLevel: ec, maskPattern: mask,
      });
      const size = ref.modules.size;
      const version = ref.version;
      // 自前実装: 同バージョン強制。マスクは自動選択なので、
      // マスク自動選択が ref.maskPattern と一致した場合のみ全比較、
      // それ以外はサイズ一致のみ（マスク選択はどちらも仕様適合でありうる）
      const flat = mod.encode_js(text, EC_NUM[ec], version);
      assert.notEqual(flat.length, 0, "encode must succeed");
      assert.equal(flat[0], size, "matrix size must match version");
      if (ref.maskPattern === mask) {
        // TODO ではない恒久仕様: 完全一致検証は同マスク時のみ意味を持つ
        // 自前の選択マスクを知るため、format情報から読み取る:
        // format bits は (8,0..5),(8,7),(8,8),(7,8),(5..0,8) に配置済み
        // → 比較は「ref と自前のどちらのマスク選択も許し、行列一致は
        //    自前マスク == ref マスクのときのみ」
        const ourMask = readMask(flat);
        if (ourMask === mask) {
          for (let y = 0; y < size; y++) for (let x = 0; x < size; x++) {
            assert.equal(
              flat[1 + y * size + x],
              ref.modules.get(y, x) ? 1 : 0,
              `mismatch at (${x},${y})`);
          }
        }
      }
    });
  }
}

// フォーマット情報15bitからマスク3bitを復元（XOR 0x5412 を戻す）
function readMask(flat) {
  const size = flat[0];
  const get = (x, y) => flat[1 + y * size + x];
  let bits = 0;
  const coords = [
    [8, 0], [8, 1], [8, 2], [8, 3], [8, 4], [8, 5], [8, 7], [8, 8],
    [7, 8], [5, 8], [4, 8], [3, 8], [2, 8], [1, 8], [0, 8],
  ];
  coords.forEach(([x, y], i) => { bits |= get(x, y) << i; });
  const unmasked = bits ^ 0x5412;
  return (unmasked >> 10) & 0b111;
}
```

**設計判断（記録）:** マスク選択はどの実装も「最小ペナルティ」だが同点時の順序差で分かれうる。強制マスクの qrcode npm 出力と「自前が同じマスクを選んだケース」でのみ全モジュール比較する。8マスク × 8ケース中、少なくとも自動選択の一致ケースが各テキストで1つは全比較になる（自前の選択も 0..7 のどれかだから）。全64テストで一度も全比較が発火しないことはない。

- [ ] **Step 3: 実行**

```bash
cd core && moon build --target js --release && cd ..
pnpm --filter moonqr-parity-test test
```

Expected: 全 PASS。行列不一致が出たら、Task 9〜11 のどこかにバグがある（マスク・フォーマット配置・ジグザグの順で疑う）。

- [ ] **Step 4: コミット** — `git add -A && git commit -m "test(encode): qrcode npmとの行列一致テスト"`

---

### Task 14: 人力ゲート — 実機スキャン確認

**Files:**
- Create: `bench/demo.html`

**Interfaces:**
- Consumes: `encode_js` ビルド成果物
- Produces: v1 Done 基準3の「実機スマホスキャナで読める」確認

- [ ] **Step 1: デモページを作成**

`bench/demo.html`:
```html
<!doctype html>
<meta charset="utf-8">
<title>moonqr demo</title>
<style>
  body { font-family: sans-serif; display: flex; flex-wrap: wrap; gap: 24px; }
  figure { margin: 0; text-align: center; }
  svg { width: 240px; height: 240px; }
  figcaption { max-width: 240px; word-break: break-all; font-size: 12px; }
</style>
<body>
<script type="module">
  // ビルド出力パスは実際の moon build 出力に合わせて調整
  const mod = await import("../core/target/js/release/build/encode/encode.js");
  const EC = { L: 0, M: 1, Q: 2, H: 3 };
  const CASES = [
    ["HELLO", "M"],
    ["https://github.com/naoto24kawa/moonqr", "M"],
    ["0123456789", "L"],
    ["こんにちは世界🦑", "H"],
    ["A".repeat(500), "Q"],
    ["WIFI:T:WPA;S:test;P:pass1234;;", "M"],
  ];
  for (const [text, ec] of CASES) {
    const flat = mod.encode_js(text, EC[ec], 0);
    const size = flat[0];
    const margin = 4;
    const total = size + margin * 2;
    let d = "";
    for (let y = 0; y < size; y++) for (let x = 0; x < size; x++) {
      if (flat[1 + y * size + x]) d += `M${x + margin} ${y + margin}h1v1h-1z`;
    }
    const fig = document.createElement("figure");
    fig.innerHTML =
      `<svg viewBox="0 0 ${total} ${total}">` +
      `<rect width="${total}" height="${total}" fill="#fff"/>` +
      `<path d="${d}" fill="#000"/></svg>` +
      `<figcaption>[${ec}] ${text.slice(0, 60)}</figcaption>`;
    document.body.appendChild(fig);
  }
</script>
</body>
```

- [ ] **Step 2: サーブして人力確認を依頼**

```bash
python3 -m http.server 8000 --directory /Users/nishikawa/projects/naoto24kawa/moonqr
```

ユーザーに依頼: 「スマホのカメラで http://localhost:8000/bench/demo.html の6つのQRを全部読んで、内容が一致するか確認してほしい」。**6/6 成功が合格。**失敗があれば該当ケースを固定バージョン・固定マスクで最小再現し、Task 9〜12 を修正。

- [ ] **Step 3: 結果を記録してコミット・タグ**

結果を `bench/RESULT.md` に追記（機種・OS・6ケースの成否）。

```bash
git add -A && git commit -m "feat: Phase 1 完了 — エンコーダ実機検証済み"
git tag phase1-encoder
```

---

## 完了チェック（Phase 1 の Done 判定）

- [ ] `moon test --target js`（＋決定バックエンド）が全 PASS
- [ ] `pnpm --filter moonqr-parity-test test` 全 PASS
- [ ] `bench/RESULT.md` にバックエンド決定の実測根拠がある
- [ ] 実機スキャン 6/6 成功の記録がある
- [ ] スペックの v1 Done 基準のうち 3（エンコード側）を満たす。1,2,4 は Plan 2/3 スコープ

## 最終ブランチレビューからの引き継ぎ（2026-07-14・マージ承認済み・ACCEPTED_RISKS）

**Plan 2 冒頭で必須:**
- 40バージョン×4ECレベルの総当たりパリティテスト（version強制で qrcode npm と全行列比較。v17-40 の表が未実証のまま — 機械生成＋既知値検証済みのため低リスクだが Done 基準3 の前提）
- rs_decode.mbt の BM 係数順コメント誤記・format.mbt:59 コメントの修正（Plan 2 の BCH 復号実装を誤導しうる）
- Plan 2 の binarizer は jsQR 方式（低分散ブロックは近傍しきい値継承）— 3x3近傍平均は24px以上の一様領域で盲点（Task 2 レビューの知見）

**Plan 3 で必須（JS境界の total 化）:**
- encode_js の version/ec range check（現状 41 等で abort→JS例外、契約は空配列）
- write_segment の alnum 不正文字ガード / mask_bit の範囲外ガード
- to_svg_string の js export 判断（demo.html の重複実装解消）
- encode("") の仕様明示（qrcode npm は throw、現状 Some を返す）
- THIRD_PARTY notice（qrcode-generator MIT・jsQR Apache-2.0 帰属）
- gen-tables.mjs の取得元を commit SHA に固定

## Plan 2 / Plan 3 への引き継ぎ事項

- 決定バックエンドと FFI 境界の実測知見（`bench/RESULT.md`）
- `rs_decode` は Plan 2 のフォーマット情報復号・コードワード訂正でそのまま使う
- `encode` は Plan 2 のデコーダテストのデータ生成器として使う（encode→ラスタライズ→decode ラウンドトリップ）
- Plan 3 で `packages/moonqr` を本物の npm パッケージに昇格（現状はパリティテスト置き場）
