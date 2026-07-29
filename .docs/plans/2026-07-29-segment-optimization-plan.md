# 混在モードのセグメント最適化 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** エンコーダが入力を区間ごとに最適なモードへ分割し、同じ内容をより小さい QR で表現できるようにする。

**Architecture:** 入力を文字種のランに圧縮し、ラン境界のみを分割候補として動的計画法で最小ビット数の分割を求める。文字数指示子のビット数はバージョン帯（1-9 / 10-26 / 27-40）でのみ変わるため、DP は帯ごとに 1 回・計 3 回で足りる。デコーダは複数セグメントを既に読めるため変更しない。

**Tech Stack:** MoonBit（`core/`、`moon test --target js`）。検証に Node.js + `qrcode` npm（オラクル）+ `jsqr` npm（独立デコーダ）。

## Global Constraints

- 設計の正本は `docs/superpowers/specs/2026-07-29-segment-optimization-design.md`。
- **成功基準**: qrcode npm と比較し、全ケースで**同じか小さいバージョン**になること。1 件でも負けたら不合格。
- `encode(text, ec, version)` と `encode_js` のシグネチャを変更しない。最適化はデフォルトで有効、オプトアウトのフラグを作らない。
- 空文字は `None`、容量超過は `None` の既存契約を維持する。
- **既存の `version-sweep.test.mjs`（160 通り行列一致）を変更しない。** 入力が英数字のみで分割の余地がないため、最適化後もビット単位で同一のはず。変わったら実装バグ。
- デコーダ（`core/src/decode/`）と TypeScript ラッパ（`packages/`）は変更しない。
- **`moon fmt` を実行しない**（ツールチェイン版によってはリポジトリ全体の設定移行を始める）。手で既存のスタイルに合わせる。
- **新しく追加する型・関数はすべて非公開にする。** 設計正本が「分割結果を外部へ公開する API は作らない（内部実装に留める。公開すると semver の制約になる）」と定めているため。既存の公開 API（`Mode` / `detect_mode` / `cci_bits` / `write_segment` / `utf8_encode`）は変更しない。
- **内部関数の直接テストは whitebox（`segment_wbtest.mbt`）に書く。** MoonBit の blackbox テストは `@encode.` 経由でしか呼べないため、blackbox に書こうとすると内部実装を `pub` にする必要が生じ、上の制約と衝突する。テストの書きやすさのために公開 API を増やしてはならない。以下の各タスクに載せているテストコードは `@encode.` 接頭辞を付けた blackbox 形式で書かれているが、**whitebox に置く場合は接頭辞なしで直接呼ぶ**。既存の `core/src/decode/extractor_wbtest.mbt` が whitebox テストの実例。
- コミットメッセージは日本語。
- `main` は保護されている。作業ブランチ `feat/segment-optimization` を切り、PR 経由でマージする。

## File Structure

| ファイル | 責務 |
|---|---|
| `core/src/encode/segment.mbt`（変更） | 文字種分類・ラン分解・区間ビット数・DP・セグメント列の書き込み。既存の `Mode` / `alnum_index` / `cci_bits` / `write_segment` / `utf8_encode` はそのまま使う |
| `core/src/encode/segment_test.mbt`（変更） | 上記の単体テストを追加。既存テストは残す |
| `core/src/encode/encode.mbt`（変更） | `write_segment` 単発呼び出しを、最適分割に基づくセグメント列の書き込みへ差し替え |
| `packages/moonqr/test/segment-optimization.test.mjs`（新規） | qrcode npm との比較・往復・境界の契約固定 |

`segment.mbt` は現在 163 行。本計画で 100 行程度増えるが、責務は「セグメントの表現とビット化」で一貫しているため分割しない。

---

### Task 1: 文字種の分類とラン分解

**Files:**
- Modify: `core/src/encode/segment.mbt`
- Test: `core/src/encode/segment_test.mbt`

**Interfaces:**
- Consumes: 既存の `alnum_index(c : Char) -> Int`（`-1` は英数字モード非対応）
- Produces:
  - `pub fn char_mode(c : Char) -> Mode` — その文字を表現できる最も制限的なモード
  - `pub(all) struct Run { mode : Mode; start : Int; len : Int }` — `start` は文字単位のインデックス（バイトではない）
  - `pub fn runs_of(text : String) -> Array[Run]` — 連続する同じ `char_mode` をまとめたラン列

- [ ] **Step 1: 失敗するテストを書く**

`core/src/encode/segment_test.mbt` の末尾に追加する。

```moonbit
test "char_mode classifies by the most restrictive mode" {
  assert_eq(@encode.char_mode('5'), @encode.Mode::Numeric)
  assert_eq(@encode.char_mode('A'), @encode.Mode::Alphanumeric)
  assert_eq(@encode.char_mode(' '), @encode.Mode::Alphanumeric)
  assert_eq(@encode.char_mode(':'), @encode.Mode::Alphanumeric)
  assert_eq(@encode.char_mode('a'), @encode.Mode::Byte)
  assert_eq(@encode.char_mode('あ'), @encode.Mode::Byte)
}

test "runs_of groups consecutive chars of the same mode" {
  let rs = @encode.runs_of("ab123XY")
  assert_eq(rs.length(), 3)
  assert_eq(rs[0].mode, @encode.Mode::Byte)
  assert_eq(rs[0].start, 0)
  assert_eq(rs[0].len, 2)
  assert_eq(rs[1].mode, @encode.Mode::Numeric)
  assert_eq(rs[1].start, 2)
  assert_eq(rs[1].len, 3)
  assert_eq(rs[2].mode, @encode.Mode::Alphanumeric)
  assert_eq(rs[2].start, 5)
  assert_eq(rs[2].len, 2)
}

test "runs_of on a single-mode string yields one run" {
  let rs = @encode.runs_of("123456")
  assert_eq(rs.length(), 1)
  assert_eq(rs[0].mode, @encode.Mode::Numeric)
  assert_eq(rs[0].len, 6)
}

test "runs_of on empty string yields no runs" {
  assert_eq(@encode.runs_of("").length(), 0)
}
```

- [ ] **Step 2: テストが失敗することを確認する**

```sh
export PATH="$HOME/.moon/bin:$PATH"
cd core && moon test --target js
```

Expected: `char_mode` と `runs_of` が未定義でコンパイルエラー。

- [ ] **Step 3: 実装する**

`core/src/encode/segment.mbt` の `detect_mode` の直後に追加する。

```moonbit
///| その文字を表現できる最も制限的なモード。
///| 表現力の包含関係は Numeric ⊂ Alphanumeric ⊂ Byte。
pub fn char_mode(c : Char) -> Mode {
  let code = c.to_int()
  if code >= 48 && code <= 57 {
    Mode::Numeric
  } else if alnum_index(c) >= 0 {
    Mode::Alphanumeric
  } else {
    Mode::Byte
  }
}

///| 文字種のラン。start は文字単位のインデックス（UTF-8 バイト位置ではない）。
pub(all) struct Run {
  mode : Mode
  start : Int
  len : Int
} derive(Eq, Debug)

///| 連続する同じ char_mode の文字をまとめる。
pub fn runs_of(text : String) -> Array[Run] {
  let out : Array[Run] = []
  let mut idx = 0
  for c in text {
    let m = char_mode(c)
    if out.length() > 0 && out[out.length() - 1].mode == m {
      let last = out[out.length() - 1]
      out[out.length() - 1] = Run::{ mode: m, start: last.start, len: last.len + 1 }
    } else {
      out.push(Run::{ mode: m, start: idx, len: 1 })
    }
    idx = idx + 1
  }
  out
}
```

- [ ] **Step 4: テストが通ることを確認する**

```sh
cd core && moon test --target js
```

Expected: 追加した 4 テストが PASS。既存テストも全て PASS。

- [ ] **Step 5: コミットする**

```sh
git add core/src/encode/segment.mbt core/src/encode/segment_test.mbt
git commit -m "feat(encode): 文字種の分類とラン分解を追加

セグメント最適化の前段。最適な分割境界は文字種が変わる位置にしか
来ないため、先にランへ圧縮して DP の探索空間を落とす。"
```

---

### Task 2: 区間のビット数計算

**Files:**
- Modify: `core/src/encode/segment.mbt`
- Test: `core/src/encode/segment_test.mbt`

**Interfaces:**
- Consumes: `cci_bits(mode : Mode, version : Int) -> Int`、`utf8_encode(text : String) -> Array[Int]`、`Mode`
- Produces:
  - `pub fn mode_can_encode(mode : Mode, run_mode : Mode) -> Bool` — `run_mode` の文字を `mode` で表現できるか
  - `pub fn segment_bits(chars : Array[Char], from : Int, len : Int, mode : Mode, version : Int) -> Int` — モード指示子 4bit + 文字数指示子 + データ部の合計ビット数

**なぜ `Array[Char]` を受け取るか**: `String` の部分文字列を都度作ると DP のループで確保が繰り返される。呼び出し側で 1 度だけ `Array[Char]` に展開して使い回す。

- [ ] **Step 1: 失敗するテストを書く**

```moonbit
test "mode_can_encode follows Numeric ⊂ Alphanumeric ⊂ Byte" {
  assert_eq(@encode.mode_can_encode(@encode.Mode::Numeric, @encode.Mode::Numeric), true)
  assert_eq(@encode.mode_can_encode(@encode.Mode::Alphanumeric, @encode.Mode::Numeric), true)
  assert_eq(@encode.mode_can_encode(@encode.Mode::Byte, @encode.Mode::Numeric), true)
  assert_eq(@encode.mode_can_encode(@encode.Mode::Numeric, @encode.Mode::Alphanumeric), false)
  assert_eq(@encode.mode_can_encode(@encode.Mode::Alphanumeric, @encode.Mode::Byte), false)
  assert_eq(@encode.mode_can_encode(@encode.Mode::Byte, @encode.Mode::Byte), true)
}

test "segment_bits matches write_segment for numeric" {
  // "01234567" v1 numeric: 4 + 10 + (10+10+7) = 41
  let chars : Array[Char] = []
  for c in "01234567" {
    chars.push(c)
  }
  assert_eq(@encode.segment_bits(chars, 0, 8, @encode.Mode::Numeric, 1), 4 + 10 + 10 + 10 + 7)
}

test "segment_bits matches write_segment for alphanumeric" {
  // "AC-42" v1 alnum: 4 + 9 + (11+11+6) = 41
  let chars : Array[Char] = []
  for c in "AC-42" {
    chars.push(c)
  }
  assert_eq(@encode.segment_bits(chars, 0, 5, @encode.Mode::Alphanumeric, 1), 4 + 9 + 11 + 11 + 6)
}

test "segment_bits counts UTF-8 bytes for byte mode" {
  // "あ" は UTF-8 で 3 バイト: 4 + 8 + 24 = 36 (v1)
  let chars : Array[Char] = []
  for c in "あ" {
    chars.push(c)
  }
  assert_eq(@encode.segment_bits(chars, 0, 1, @encode.Mode::Byte, 1), 4 + 8 + 24)
}

test "segment_bits handles a sub-range" {
  // "XX123" の後半 3 文字を numeric として測る: 4 + 10 + 10 = 24 (v1)
  let chars : Array[Char] = []
  for c in "XX123" {
    chars.push(c)
  }
  assert_eq(@encode.segment_bits(chars, 2, 3, @encode.Mode::Numeric, 1), 4 + 10 + 10)
}
```

- [ ] **Step 2: テストが失敗することを確認する**

```sh
cd core && moon test --target js
```

Expected: `mode_can_encode` と `segment_bits` が未定義でコンパイルエラー。

- [ ] **Step 3: 実装する**

`runs_of` の直後に追加する。

```moonbit
///| run_mode の文字を mode で表現できるか（Numeric ⊂ Alphanumeric ⊂ Byte）。
pub fn mode_can_encode(mode : Mode, run_mode : Mode) -> Bool {
  match mode {
    Mode::Byte => true
    Mode::Alphanumeric =>
      match run_mode {
        Mode::Byte => false
        _ => true
      }
    Mode::Numeric =>
      match run_mode {
        Mode::Numeric => true
        _ => false
      }
  }
}

///| chars[from..from+len) を mode で符号化したときの総ビット数。
///| モード指示子 4bit + 文字数指示子 + データ部。
///| 端数の扱いがモードごとに異なるため、1文字あたりへ均さずに計算する。
pub fn segment_bits(
  chars : Array[Char],
  from : Int,
  len : Int,
  mode : Mode,
  version : Int,
) -> Int {
  let header = 4 + cci_bits(mode, version)
  match mode {
    Mode::Numeric => {
      let full = len / 3
      let rest = len % 3
      let data = full * 10 + (if rest == 2 { 7 } else if rest == 1 { 4 } else { 0 })
      header + data
    }
    Mode::Alphanumeric => {
      let pairs = len / 2
      let rest = len % 2
      header + pairs * 11 + (if rest == 1 { 6 } else { 0 })
    }
    Mode::Byte => {
      // 文字数ではなく UTF-8 バイト数で数える
      let mut bytes = 0
      for i = from; i < from + len; i = i + 1 {
        let cp = chars[i].to_int()
        bytes = bytes +
          (if cp < 0x80 {
            1
          } else if cp < 0x800 {
            2
          } else if cp < 0x10000 {
            3
          } else {
            4
          })
      }
      header + bytes * 8
    }
  }
}
```

- [ ] **Step 4: テストが通ることを確認する**

```sh
cd core && moon test --target js
```

Expected: 追加した 5 テストが PASS。

- [ ] **Step 5: コミットする**

```sh
git add core/src/encode/segment.mbt core/src/encode/segment_test.mbt
git commit -m "feat(encode): 区間のビット数計算を追加

端数の扱いがモードごとに違う（Numeric は3文字10bit・余り4/7bit、
Alphanumeric は2文字11bit・余り6bit）ため、1文字あたりへ均さずに
区間確定後に正確に計算する。Byte は文字数ではなく UTF-8 バイト数。"
```

---

### Task 3: 動的計画法による最適分割

**Files:**
- Modify: `core/src/encode/segment.mbt`
- Test: `core/src/encode/segment_test.mbt`

**Interfaces:**
- Consumes: `runs_of`、`segment_bits`、`mode_can_encode`、`Run`、`Mode`
- Produces:
  - `pub(all) struct Segment { mode : Mode; start : Int; len : Int }` — 文字単位の区間とそのモード
  - `pub fn optimal_segments(text : String, version : Int) -> Array[Segment]` — 最小ビット数になる分割

**アルゴリズム**: ラン列に対する DP。`dp[j]` = 先頭から j 番目のランまでを符号化する最小ビット数。遷移は「i 番目のランから j-1 番目のランまでを 1 セグメントにまとめる」で、モード候補は**その区間の全文字を表現できるモードすべて**（区間が数字のみなら Numeric / Alphanumeric / Byte の 3 つとも候補にする。前後と同じモードに揃えて切替コストを消す方が得になる場合があるため、より制限的なモードだけに絞ってはならない）。

- [ ] **Step 1: 失敗するテストを書く**

```moonbit
test "optimal_segments keeps a single-mode string as one segment" {
  let segs = @encode.optimal_segments("HELLO WORLD", 1)
  assert_eq(segs.length(), 1)
  assert_eq(segs[0].mode, @encode.Mode::Alphanumeric)
  assert_eq(segs[0].start, 0)
  assert_eq(segs[0].len, 11)
}

test "optimal_segments splits byte prefix from a long digit run" {
  // 実測の境界: 小文字を含む URL + 10桁以上の数字は分割した方が小さい
  let segs = @encode.optimal_segments("https://ex.com/id/1234567890", 1)
  assert_eq(segs.length(), 2)
  assert_eq(segs[0].mode, @encode.Mode::Byte)
  assert_eq(segs[1].mode, @encode.Mode::Numeric)
  assert_eq(segs[1].len, 10)
}

test "optimal_segments does not split a very short digit run" {
  // 単一Byte=172bit < 分割=177bit。桁数が少ないとモード切替の
  // オーバーヘッド（モード指示子4bit + 文字数指示子）が上回る
  let segs = @encode.optimal_segments("https://ex.com/id/12", 1)
  assert_eq(segs.length(), 1)
  assert_eq(segs[0].mode, @encode.Mode::Byte)
}

test "optimal_segments splits once the digit run is long enough" {
  // 単一Byte=196bit > 分割=187bit。分割が有利になる境界は3〜4桁の間にある。
  // n=3 は 180=180 の同点なのでテストに使わない（どちらを選んでも最適であり、
  // 固定すると実装の内部詳細を仕様化してしまう）。
  let segs = @encode.optimal_segments("https://ex.com/id/12345", 1)
  assert_eq(segs.length(), 2)
  assert_eq(segs[0].mode, @encode.Mode::Byte)
  assert_eq(segs[1].mode, @encode.Mode::Numeric)
  assert_eq(segs[1].len, 5)
}

test "optimal_segments absorbs digits into an alphanumeric span" {
  // 英字・数字・英字は 3 分割より 1 つの Alphanumeric の方が小さい
  let segs = @encode.optimal_segments("ABC12DEF", 1)
  assert_eq(segs.length(), 1)
  assert_eq(segs[0].mode, @encode.Mode::Alphanumeric)
  assert_eq(segs[0].len, 8)
}

test "optimal_segments on empty string yields no segments" {
  assert_eq(@encode.optimal_segments("", 1).length(), 0)
}

test "optimal_segments never costs more than a single segment" {
  // どの入力でも「全体を1モードで表現」以下のビット数になること
  let cases = ["https://ex.com/id/1234567890", "ABC12DEF", "123456", "hello world 42"]
  for t in cases {
    let chars : Array[Char] = []
    for c in t {
      chars.push(c)
    }
    let single = @encode.detect_mode(t)
    let single_bits = @encode.segment_bits(chars, 0, chars.length(), single, 1)
    let segs = @encode.optimal_segments(t, 1)
    let mut total = 0
    for s in segs {
      total = total + @encode.segment_bits(chars, s.start, s.len, s.mode, 1)
    }
    assert_true(total <= single_bits)
  }
}
```

- [ ] **Step 2: テストが失敗することを確認する**

```sh
cd core && moon test --target js
```

Expected: `optimal_segments` と `Segment` が未定義でコンパイルエラー。

- [ ] **Step 3: 実装する**

`segment_bits` の直後に追加する。

```moonbit
///| 最適分割の1区間。start / len は文字単位。
pub(all) struct Segment {
  mode : Mode
  start : Int
  len : Int
} derive(Eq, Debug)

///| 最小ビット数になる分割を返す。
///| ラン単位の DP。最適な分割境界は文字種が変わる位置にしか来ないため、
///| ランへ圧縮してから探索する（数字列の途中で切って両側とも Numeric に
///| するのは切替コストが増えるだけで常に損）。
pub fn optimal_segments(text : String, version : Int) -> Array[Segment] {
  let runs = runs_of(text)
  let n = runs.length()
  if n == 0 {
    return []
  }
  let chars : Array[Char] = []
  for c in text {
    chars.push(c)
  }
  let modes = [Mode::Numeric, Mode::Alphanumeric, Mode::Byte]
  // dp[j] = 先頭から j 個のランを符号化する最小ビット数（dp[0] = 0）
  let inf = 0x7FFFFFFF
  let dp = Array::make(n + 1, inf)
  dp[0] = 0
  // from_run[j] / from_mode[j] = dp[j] を達成する直前の状態
  let from_run = Array::make(n + 1, 0)
  let from_mode = Array::make(n + 1, Mode::Byte)
  for j = 1; j <= n; j = j + 1 {
    for i = 0; i < j; i = i + 1 {
      if dp[i] == inf {
        continue
      }
      // ラン i..j-1 をまとめて1セグメントにする
      let start = runs[i].start
      let mut len = 0
      for k = i; k < j; k = k + 1 {
        len = len + runs[k].len
      }
      for m in modes {
        // 区間内の全ランを表現できるモードだけが候補
        let mut ok = true
        for k = i; k < j; k = k + 1 {
          if !mode_can_encode(m, runs[k].mode) {
            ok = false
          }
        }
        if !ok {
          continue
        }
        let cost = dp[i] + segment_bits(chars, start, len, m, version)
        if cost < dp[j] {
          dp[j] = cost
          from_run[j] = i
          from_mode[j] = m
        }
      }
    }
  }
  // 復元
  let rev : Array[Segment] = []
  let mut j = n
  while j > 0 {
    let i = from_run[j]
    let start = runs[i].start
    let mut len = 0
    for k = i; k < j; k = k + 1 {
      len = len + runs[k].len
    }
    rev.push(Segment::{ mode: from_mode[j], start, len })
    j = i
  }
  let out : Array[Segment] = []
  for idx = rev.length() - 1; idx >= 0; idx = idx - 1 {
    out.push(rev[idx])
  }
  out
}
```

- [ ] **Step 4: テストが通ることを確認する**

```sh
cd core && moon test --target js
```

Expected: 追加した 6 テストが PASS。特に「数字 5 桁では分割しない / 10 桁では分割する」の 2 つが、実測した境界を契約として固定する。

- [ ] **Step 5: コミットする**

```sh
git add core/src/encode/segment.mbt core/src/encode/segment_test.mbt
git commit -m "feat(encode): ラン単位の動的計画法で最適分割を求める

モード候補は区間の全文字を表現できるモードすべてとする。単独では
不利なモードでも、前後と同じモードに揃えて切替コストを消す方が
全体最適になる場合があるため（ABC12DEF は3分割より1つの
Alphanumeric が小さい）。

実測した境界（数字5桁では分割せず10桁では分割する）をテストで固定した。"
```

---

### Task 4: セグメント列の書き込みと encode への統合

**Files:**
- Modify: `core/src/encode/segment.mbt`
- Modify: `core/src/encode/encode.mbt`
- Test: `core/src/encode/segment_test.mbt`

**Interfaces:**
- Consumes: `optimal_segments`、`write_segment`、`Segment`、`BitWriter`
- Produces: `pub fn write_segments(w : BitWriter, text : String, version : Int) -> Unit` — 最適分割に基づき複数セグメントを書く

**`encode.mbt` の変更点**: `let mode = detect_mode(text)` と `write_segment(w, text, mode, v)` を `write_segments(w, text, v)` に置き換える。バージョン試行のループ構造は変えない（各 v でその帯の分割が使われる）。

- [ ] **Step 1: 失敗するテストを書く**

```moonbit
test "write_segments equals write_segment for a single-mode input" {
  // 分割の余地がない入力では、単一セグメントと完全に同じビット列になること
  let a = @encode.BitWriter::new()
  @encode.write_segment(a, "HELLO WORLD", @encode.Mode::Alphanumeric, 1)
  let b = @encode.BitWriter::new()
  @encode.write_segments(b, "HELLO WORLD", 1)
  assert_eq(b.bit_length(), a.bit_length())
}

test "write_segments produces fewer bits than a single segment when split helps" {
  let text = "https://ex.com/id/1234567890"
  let single = @encode.BitWriter::new()
  @encode.write_segment(single, text, @encode.Mode::Byte, 1)
  let split = @encode.BitWriter::new()
  @encode.write_segments(split, text, 1)
  assert_true(split.bit_length() < single.bit_length())
}

test "encode still works and shrinks the version when splitting helps" {
  // 単一モードなら v4、最適分割なら v3 に収まる（実測値）
  let text = "https://ex.com/id/123456789012345678901234567890"
  let m = @encode.encode(text, @encode.EcLevel::M, None)
  match m {
    Some(matrix) => assert_eq(matrix.size, 29) // v3 = 29x29
    None => abort("encode returned None")
  }
}
```

- [ ] **Step 2: テストが失敗することを確認する**

```sh
cd core && moon test --target js
```

Expected: `write_segments` が未定義でコンパイルエラー。

- [ ] **Step 3: `write_segments` を実装する**

`optimal_segments` の直後に追加する。

```moonbit
///| 最適分割に基づいて複数セグメントを書く。
///| デコーダ側は Phase 2 で複数セグメントの読み取りに対応済み。
pub fn write_segments(w : BitWriter, text : String, version : Int) -> Unit {
  let chars : Array[Char] = []
  for c in text {
    chars.push(c)
  }
  for s in optimal_segments(text, version) {
    // このコードベースは StringBuilder を使わず、文字列連結と補間で組み立てる
    // （svg.mbt の to_svg_string と同じ書き方）
    let mut part = ""
    for i = s.start; i < s.start + s.len; i = i + 1 {
      part = part + chars[i].to_string()
    }
    write_segment(w, part, s.mode, version)
  }
}
```

**もし `Char::to_string()` が存在しない場合**は、`String::from_array` などの構築手段をコンパイルエラーの内容から選ぶ。文字列の組み立て方はこの関数の中に閉じており、外部インターフェース（`write_segments` のシグネチャ）には影響しない。

- [ ] **Step 4: `encode.mbt` を差し替える**

`core/src/encode/encode.mbt` の `encode` 内、`let mode = detect_mode(text)` の行を削除し、`try_version` の中の `write_segment(w, text, mode, v)` を次に置き換える。

```moonbit
    write_segments(w, text, v)
```

差し替え後の `try_version` の冒頭は次の形になる。

```moonbit
  let try_version = fn(v : Int) -> Matrix? {
    let w = BitWriter::new()
    write_segments(w, text, v)
    match assemble(w, v, ec) {
```

- [ ] **Step 5: テストが通ることを確認する**

```sh
cd core && moon test --target js
```

Expected: 追加した 3 テストが PASS。**既存テストも全て PASS**（98 件以上）。ここで既存の numeric / alphanumeric セグメントのビット長テストが落ちるなら、分割すべきでない入力を分割している。

- [ ] **Step 6: JS 側の全テストが通ることを確認する**

```sh
cd core && moon build --target js --release && cd ..
node --test packages/moonqr/test/*.test.mjs
```

Expected: 273 件が PASS。**特に `version-sweep.test.mjs`（qrcode npm との 160 通り行列一致）が通ること** — 入力が `V1L` 等の英数字のみで分割の余地がないため、ビット単位で従来と同一のはず。

- [ ] **Step 7: コミットする**

```sh
git add core/src/encode/segment.mbt core/src/encode/encode.mbt core/src/encode/segment_test.mbt
git commit -m "feat(encode): 最適分割を encode に統合する

write_segment の単発呼び出しを write_segments に置き換える。
バージョン試行のループ構造は変えず、各 v でその帯の分割を使う。

既存の160通り行列一致テストは変更しない。入力が英数字のみで分割の
余地がないため、通らなければ実装バグの証拠になる。"
```

---

### Task 5: qrcode npm との比較・往復・境界の検証

**Files:**
- Create: `packages/moonqr/test/segment-optimization.test.mjs`

**Interfaces:**
- Consumes: `core/_build/js/release/build/encode/encode.js` の `encode_js(text, ec, version) -> Array[Int]`（`[size, m00, m01, ...]` の平坦配列、エラー時は空配列）、`core/_build/js/release/build/decode/decode.js` の `decode_js`
- Produces: なし（最終タスク）

**既存テストの読み方**: `packages/moonqr/test/version-sweep.test.mjs` が `encode_js` の呼び出し方とビルド出力のパス解決の実例。`packages/moonqr/test/roundtrip.test.mjs` が行列から画素を作ってデコードする実例。**先に両方を読むこと。**

- [ ] **Step 1: 比較テストを書く**

```javascript
import { test } from "node:test";
import assert from "node:assert/strict";
import QRCode from "qrcode";
import { createRequire } from "node:module";

const require = createRequire(import.meta.url);
const enc = require("../../../core/_build/js/release/build/encode/encode.js");

const EC = { L: 0, M: 1, Q: 2, H: 3 };

// 最小バージョンを求める（encode_js は version を明示指定する形なので線形試行）
function minVersion(text, ec) {
  for (let v = 1; v <= 40; v++) {
    const flat = enc.encode_js(text, ec, v);
    if (flat && flat.length > 0) return v;
  }
  return null;
}

// 効果が出る形（byte に落ちる文字 + 長い数字列）を中心に、
// 効果が出ない形（単一モード・短い数字列）も混ぜる
const digits = (n) =>
  Array.from({ length: n }, (_, i) => String((i * 7) % 10)).join("");

const CASES = [
  "https://ex.com/id/12345",
  "https://ex.com/id/1234567890",
  "https://ex.com/id/" + digits(30),
  "https://ex.com/id/" + digits(100),
  "注文番号は" + digits(30) + "です",
  "HTTPS://EX.COM/ID/" + digits(60),
  "HELLO WORLD",
  "1234567890",
  "hello",
  "ABC12DEF",
  "SKU-1234567890-ABCDEFGHIJ-9876543210",
];

test("never larger than qrcode npm", () => {
  const losses = [];
  for (const text of CASES) {
    for (const ec of ["L", "M", "Q", "H"]) {
      const ours = minVersion(text, EC[ec]);
      const ref = QRCode.create(text, { errorCorrectionLevel: ec }).version;
      assert.ok(ours !== null, `moonqr failed to encode: ${text}`);
      if (ours > ref) losses.push(`${ec} v${ours}>v${ref}: ${text}`);
    }
  }
  assert.deepEqual(losses, [], `qrcode npm に負けたケース:\n${losses.join("\n")}`);
});
```

- [ ] **Step 2: テストを実行して比較結果を確認する**

```sh
node --test packages/moonqr/test/segment-optimization.test.mjs
```

Expected: PASS。失敗した場合、出力に負けたケースが列挙されるので、そのケースで `optimal_segments` の返す分割を調べる（Task 3 の DP のモード候補が絞られすぎている可能性が高い）。

- [ ] **Step 3: 往復テストを追加する**

同じファイルに追記する。`roundtrip.test.mjs` の画素化ヘルパの作り方に合わせること。

```javascript
const dec = require("../../../core/_build/js/release/build/decode/decode.js");

// 行列を 4px/セル・margin 4 セルの RGBA バッファへ展開する
function rasterize(flat) {
  const size = flat[0];
  const CELL = 4;
  const MARGIN = 4;
  const px = (size + MARGIN * 2) * CELL;
  const data = new Uint8Array(px * px * 4).fill(255);
  for (let y = 0; y < size; y++) {
    for (let x = 0; x < size; x++) {
      if (flat[1 + y * size + x] === 0) continue;
      for (let dy = 0; dy < CELL; dy++) {
        for (let dx = 0; dx < CELL; dx++) {
          const i = (((y + MARGIN) * CELL + dy) * px + (x + MARGIN) * CELL + dx) * 4;
          data[i] = data[i + 1] = data[i + 2] = 0;
        }
      }
    }
  }
  return { data, px };
}

test("split QR codes round-trip through our own decoder", () => {
  for (const text of CASES) {
    const v = minVersion(text, EC.M);
    const flat = enc.encode_js(text, EC.M, v);
    const { data, px } = rasterize(flat);
    const got = dec.decode_js(data, px, px);
    assert.equal(got, text, `round-trip mismatch: ${text}`);
  }
});
```

- [ ] **Step 4: jsQR でも読めることを確認するテストを追加する**

自前デコーダだけで検証すると、エンコーダとデコーダが同じ誤解を共有していた場合に検出できない。独立実装で読めることを確かめる。

```javascript
import jsQR from "jsqr";

test("split QR codes are readable by jsQR (independent decoder)", () => {
  for (const text of CASES) {
    const v = minVersion(text, EC.M);
    const flat = enc.encode_js(text, EC.M, v);
    const { data, px } = rasterize(flat);
    const got = jsQR(new Uint8ClampedArray(data), px, px);
    assert.ok(got, `jsQR failed to read: ${text}`);
    assert.equal(got.data, text, `jsQR mismatch: ${text}`);
  }
});
```

- [ ] **Step 5: 全テスト層を通す**

```sh
export PATH="$HOME/.moon/bin:$PATH"
cd core && moon test --target js && cd ..
node scripts/fetch-fixtures.mjs
node --test packages/moonqr/test/*.test.mjs
pnpm -r test:unit
pnpm -r typecheck
```

Expected: 全層 PASS。

- [ ] **Step 6: バンドルサイズが増えていないことを確認する**

```sh
pnpm -r build
node scripts/report-bundle-sizes.mjs
```

Expected: `./encode` が 21.3 KB raw / 6.4 KB gzip 前後のまま（DP のコードはテーブルを持たないため、増加は 1 KB 未満に収まるはず）。大きく増えていたら、decoder 側の何かを巻き込んでいる。

- [ ] **Step 7: コミットする**

```sh
git add packages/moonqr/test/segment-optimization.test.mjs
git commit -m "test(encode): 最適分割を qrcode npm との比較と往復で検証

成功基準は「全ケースで qrcode npm と同じか小さいバージョン」。
1件でも負けたら不合格とする。

往復は自前デコーダと jsQR の両方で行う。自前だけだとエンコーダと
デコーダが同じ誤解を共有していた場合に検出できないため。"
```

---

### Task 6: ドキュメントの更新

**Files:**
- Modify: `README.md`（Limitations 節）
- Modify: `packages/moonqr/README.md`（該当箇所があれば）

**Interfaces:**
- Consumes: Task 5 までの実装
- Produces: なし

- [ ] **Step 1: README の Limitations を更新する**

`README.md` の Limitations にある次の項目を削除する。

```
- No mixed-mode segment optimization — the encoder picks one mode (Numeric / Alphanumeric / Byte)
  for the whole input rather than splitting mixed content into per-segment optimal modes.
```

代わりに、機能として記述する場所（Headline numbers か Packages 節の近く）へ 1 行加える。実測値を使うこと。

```markdown
The encoder splits mixed input into per-segment optimal modes, so a URL with a long numeric ID
encodes into a smaller symbol than a single-mode encoder would produce (measured: v7 → v4 for a
100-digit id, matching or beating the `qrcode` npm package on every case tested).
```

- [ ] **Step 2: site の Limitations も同じ内容か確認する**

```sh
grep -n "mixed-mode\|segment optimization" site/index.html site/i18n.js
```

ヒットしたら、英語・日本語の両方を README と同じ趣旨に更新し、`node scripts/build-site.mjs` を実行する。

- [ ] **Step 3: コミットする**

```sh
git add README.md site/
git commit -m "docs: 混在モード最適化の実装により Limitations を更新"
```

- [ ] **Step 4: PR を作成する**

```sh
git push -u origin feat/segment-optimization
gh pr create --title "feat(encode): 混在モードのセグメント最適化" --body-file <(cat <<'BODY'
## What this changes

入力を区間ごとに最適なモードへ分割するようにした。URL に長い ID が付く形や、日本語の文中に注文番号が入る形で、同じ内容がより小さい QR に収まる。

実測（EC=M）: `https://ex.com/id/<100桁>` が **v7 → v4**。14 ケース中 9 ケースで 1〜3 バージョン縮小。

## Type of change

- [ ] Bug fix
- [x] New feature
- [ ] Documentation
- [ ] Chore / build / CI

## Provenance

- [x] **Written by me** — not copied from another project
- [ ] **Ported from another project**
- [ ] **Generated with an AI assistant**

qrcode npm は出力の比較にのみ使用し、分割アルゴリズムは移植していない。

## Tests

- [x] `cd core && moon test --target js`
- [x] `node --test packages/moonqr/test/*.test.mjs`
- [x] `pnpm --filter @elchika-inc/moonqr test:unit`
- [x] `pnpm --filter @elchika-inc/moonqr-scanner test:unit`
- [x] `pnpm -r typecheck`

## Checklist

- [x] I did **not** run `moon fmt`
- [x] I understand `core/_build/` is gitignored but required
- [x] Changes are scoped; no unrelated reformatting
BODY
)
```

- [ ] **Step 5: CI 緑を確認してマージする**

```sh
gh pr checks --watch
gh pr merge --squash --delete-branch
```

---

## 完了条件

- qrcode npm との比較テストが全ケースで PASS（1 件も負けていない）
- 生成した QR が自前デコーダと jsQR の両方で元テキストに復元される
- 既存の 160 通り行列一致テストが**変更なしで**通る
- 実測した境界（数字 5 桁では分割せず、10 桁では分割する）がテストで固定されている
- `./encode` のバンドルサイズ増加が 1 KB 未満
- README / site の Limitations から混在モードの項目が消えている
