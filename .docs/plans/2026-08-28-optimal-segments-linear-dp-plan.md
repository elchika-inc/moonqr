# optimal_segments 線形 DP 実装計画

**Goal:** `optimal_segments` を run 数に対する O(n^2) DP から O(n) DP へ置き換え、分割互換性・容量超過の失敗表現・性能をテストで固定する。

**Architecture:** `runs_of` が作る隣接異モード run の構造を利用し、Byte は全開始点の変換済み最小値、Alphanumeric は Byte run 間の偶奇別最小値、Numeric は直前 run 固定で遷移する。コストは 6 倍整数で保持し、現行 O(n^2) 実装は whitebox 参照実装として残して完全一致を検証する。設計根拠と性能実測の正本は [`bench/RESULT.md`](../../bench/RESULT.md) の「計算量回帰（2026-08-28: O(n) DP）」節とする。

**Tech Stack:** MoonBit、Node.js `node:test`、pnpm workspace。

**Spec:** 本 PR の「optimal_segments の DP を O(n^2) -> O(n) へ書き換える」委任仕様。

## Global Constraints

- `core/src/decode/`、`core/src/gf256/`、`packages/scanner/`、`site/`、`.github/workflows/`、生成物 `core/_build/` は変更しない。
- `moon fmt` は実行しない。
- 明示 version 指定時に未使用の2帯も計算する既存方針は変えない。
- 既存テストの期待値を維持する。実装変更で測定前提が失効した場合は裁定を記録し、同じ意図を検査する条件へ置き換える。
- main へ直接 push せず、feature branch の PR まで作成する。

---

### Task 1: 失敗契約と参照差分テスト

**Files:**
- Modify: `core/src/encode/segment_wbtest.mbt`
- Modify: `core/src/encode/segment.mbt`
- Modify: `core/src/encode/encode.mbt`

**Interfaces:**
- Consumes: 現行 `optimal_segments(String, Int) -> Array[Segment]` と `encode` の3帯再利用。
- Produces: `optimal_segments(String, Int) -> Array[Segment]?`、`optimal_segments_reference(String, Int) -> Array[Segment]`。

- [x] `optimal_segments` が空入力と7,090文字を `None`、有効入力を `Some` で返すことを whitebox テストで固定する。
- [x] 現行 O(n^2) 本体を `optimal_segments_reference` として whitebox ファイルへ移す準備をし、version 1/10/27、固定ケース、単一モード、交互、非BMP・CJK、固定 seed 200件以上の完全一致テストを追加する。
- [x] `moon test --target js` を実行し、Option の失敗契約と参照実装を含めて GREEN になることを確認する。

### Task 2: O(n) DP と production 呼び出し追随

**Files:**
- Modify: `core/src/encode/segment.mbt`
- Modify: `core/src/encode/encode.mbt`

**Interfaces:**
- Consumes: `runs_of`、`cci_bits`、UTF-8 byte prefix、3帯の version 代表値。
- Produces: 6倍整数コストの線形 DP と既存 tie-break に一致する `Array[Segment]?`。

- [x] Numeric の len=1/2/3 が 24/42/60、Alphanumeric の len=1/2/3 が 36/66/102 になる数式をコメントとテスト入力で固定する。
- [x] `best_byte`、偶奇別 `best_alnum`、直前 Numeric run の3候補を実装し、`INF` 候補を加算前に除外する。
- [x] 候補更新は `(from_run, mode priority)` の辞書順で比較し、同点時に開始 run が小さく、同一開始なら Numeric、Alphanumeric、Byte の順になるよう復元情報を保存する。
- [x] `encode` で3帯の `Some(segments)` を取り出し、いずれかが `None` なら `None` を返す。
- [x] targeted `moon test --target js` を実行し、差分コーパスを含め GREEN にする。

### Task 3: test-only helper の移設と警告除去

**Files:**
- Modify: `core/src/encode/segment.mbt`
- Modify: `core/src/encode/segment_wbtest.mbt`
- Modify: `.docs/risk-registry.md`

**Interfaces:**
- Consumes: whitebox テストが同 package の private API を検証できる仕組み。
- Produces: production から `segment_bits` と `write_segments` を除去した警告0の build/test。

- [x] `segment_bits` と `write_segments` を whitebox ファイルへ移し、既存 helper テストを維持する。
- [x] リスク台帳の該当エントリを「本 PR で解消済み」へ更新し、明示 version の3帯エントリは変更しない。
- [x] `moon test --target js` と `moon build --target js --release` の出力をファイルへ保存し、`grep -c unused_value` が両方0であることを確認する。

### Task 4: JS 性能回帰と実測記録

**Files:**
- Modify: `packages/moonqr/test/segment-optimization.test.mjs`
- Modify: `bench/RESULT.md`

**Interfaces:**
- Consumes: release build の `encode_js(text, 0, 0)`。
- Produces: 7,088 run と5,356 run の100ms未満ゲート、before/after の中央値記録。

- [x] 既存1,000文字/5,000msテストを残し、`"a1".repeat(3544)` と `"1A".repeat(2678)` が各100ms未満で空配列を返すテストを追加して、旧 O(n^2) 実装で RED を確認する。
- [x] release build 後、JIT warmup を行い、指定6入力を複数回計測して中央値・Node・OS・CPUを記録する。
- [x] `bench/RESULT.md` に計測方法と同じマシンで測った before / after を追記する。

### Task 5: 完了検証・レビュー・PR

**Files:**
- Verify: 変更ファイル一式

**Interfaces:**
- Consumes: 委任仕様の rubric と lens-review-cycle。
- Produces: 全コマンド exit 0、flag 0、検証値を記載した PR。

- [ ] 指定5コマンドを pipe なしで個別実行し、exit code、件数、警告数を採取する。
- [x] read-only reviewer 1名に fresh-eyes / security / core-logic / tests / domain を順に適用させ、最大3ラウンドで確信度80%以上の flag を0にする。
- [ ] diff、対象外ファイル、PR provenance、review結果を自己確認して commit・push・PR作成を行う。
- [ ] PR の head/body/checks を read-back し、main へマージせず司令塔へ `worker_done` を1回送る。
