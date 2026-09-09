# risk-registry — 明示的に受容したリスク

直さないと決めたものを記録する。判断の日付と理由を残し、前提が変わったら再検討する。

## 記法

- ID は再利用しない。解決したエントリも番号を残したまま `Status` を更新する。新規エントリは未使用の最大値 + 1 を使う。
- `Status` は `open` / `accepted` / `resolved` / `withdrawn` の 4 語だけを使う（standards DOCS_OPS §3）。
- `accepted` のエントリには `anchor`（受容が破れたことを、受容した本人以外の何が検知するか）を必ず書く。レビュー結果や計画の再記述は anchor にしない。
- 新規エントリは templates の `_base/risk-registry.md.template` のフィールドで書く。2026-09-08 以前のエントリは旧書式の段落（内容／影響／受容理由／再検討の条件）を維持している。

---

## RISK-001: MoonBit ツールチェインの版を固定できない

- **Status**: accepted
- **Date**: 2026-07-14
- **anchor**: CI（`.github/workflows/ci.yml`）と Pages（`pages.yml`）の `Install MoonBit toolchain` step は cache miss 時に `latest` を取得するため、上流の `latest` が既存コードを壊すと `moon test` が失敗し、PR の required check `test` が赤になる。cache key `moonbit-toolchain-<os>-0.1.20260713` の変更は workflow の diff として PR に現れる

**内容**: MoonBit の配布 CDN は `latest` / `nightly` チャンネルのみを配信しており、日付やバージョンを指定した過去ビルドを保持していない。CI でツールチェインの版を文字列で固定することができない。

**影響**: 上流の `latest` が更新されると、CI が使うコンパイラが変わる。破壊的変更が入れば CI が壊れる。

**受容理由**: 上流の制約であり回避手段がない。キャッシュキーに検証済みの版番号を含めることで、`latest` が進んでも自動では切り替わらないようにしている（キャッシュヒットが続く限り同じ版が使われる）。新しい `latest` で検証・移行したときに、キーを手動で更新する運用とする。

**対応方針**: `latest` が既存コードを壊した場合は、コードを `latest` に追従させる（pre-1.0 言語のトレードオフ）。詳細と手順は [`docs/TOOLCHAIN.md`](../docs/TOOLCHAIN.md)。

**再検討の条件**: MoonBit が版指定のインストールに対応した場合。

---

## RISK-002: 明示 version 指定時に未使用の 2 帯も分割計画を行う

- **Status**: accepted
- **Date**: 2026-07-29
- **anchor**: `packages/moonqr/test/segment-optimization.test.mjs` の 5,000ms 検査は auto 経路（`encode_js(text, EC.M, 0)`）だけを計測しており、明示 version 経路の遅延を固定するテストは無い。明示 version 経路は `packages/moonqr/test/version-sweep.test.mjs`（version 1〜40 × EC 4 の 160 ケースを明示 version で CI `test` check ごとに実行）が毎 PR 通過しており、極端な退化は CI の所要時間増加（job の `timeout-minutes: 20`）として現れる。3 帯を無条件に計算する箇所は `core/src/encode/encode.mbt` 16〜28 行で、その変更は PR diff に現れる。利用者からの性能報告は GitHub Issue に届く

**内容**: セグメント最適化の DP は文字数指示子のバージョン帯（1-9 / 10-26 / 27-40）ごとに計算する。`encode(text, ec, Some(v))` のように version を明示した呼び出しでは、実際に使う 1 帯だけで足りるが、現状は 3 帯すべてを計算している。

**影響**: 明示 version 指定の経路でわずかな無駄な計算が発生する。auto 選択（既定の使い方）では 3 帯すべてを使うため無駄はない。

**受容理由**: 正しさに影響しない。auto 経路が主たる用途であり、そこでは無駄がない。分岐を足すとコード経路が増え、帯ごとの再利用ロジックが読みにくくなる。実測で問題が出ていない。

**再検討の条件**: 明示 version 指定が性能上の問題として報告された場合。

---

## RISK-003: セグメント最適化のテスト専用ヘルパ 2 個（2026-08-28 解消済み）

- **Status**: resolved
- **Date**: 2026-07-29
- **Resolved**: 2026-08-28 PR #22（`61a5bbe`）で `segment_bits` / `write_segments` を `core/src/encode/segment_wbtest.mbt` へ移した

**内容**: 実装計画が指定したヘルパのうち 2 個は、whitebox テストからのみ使われている。本体の経路からは呼ばれない。

**影響**: 削除できる余地がある（コード量がわずかに多い）。

**受容理由**: correctness・security・明示要件のいずれにも影響しない。テストの可読性に寄与している。今回のスコープでは変更しない。

**解消**: 再検討条件が発火したため、本 PR で `segment_bits` と `write_segments` を `segment_wbtest.mbt` へ移した。O(n) DP 化で production 経路から外れた関連ヘルパも同じ whitebox 側へ集約し、production build の `unused_value` 警告を解消した。

---

## RISK-004: standards バッジを README に置かない（SHOULD からの逸脱）

- **Status**: accepted
- **Date**: 2026-07-29
- **anchor**: standards リポジトリの公開状態。`gh repo view elchika-inc/standards --json visibility` が `PUBLIC` を返した時点で再検討条件が成立する

**内容**: standards は README に `standards` バッジを置くことを SHOULD としているが、moonqr では省いている。

**影響**: 参照している standards の版が README から一目で分からない。

**受容理由**: standards リポジトリが private であり、公開 OSS である本リポジトリからリンクすると、外部の利用者には壊れたリンクとして見える。版は [`AGENTS.md`](../AGENTS.md) の `standards_version` に記録している。

**再検討の条件**: standards リポジトリが公開された場合。

---

## RISK-005: 帯 DP 再利用の性能比率による回帰検知を外す

- **Status**: accepted
- **Date**: 2026-08-28
- **anchor**: `packages/moonqr/test/segment-optimization.test.mjs` の `auto version selection stays below 1000ms for 7,088 alternating byte/numeric runs` と `... for 5,356 alternating numeric/alphanumeric runs`（1,000ms 上限。旧 O(n^2) 実装は CI で 3,000ms 以上になる設計）、および `auto version selection matches forced search within 5 seconds`（5,000ms 上限と auto / forced の version 一致）が CI `test` check で毎 PR 実行される。帯 DP を version 試行間で再利用する実装は `core/src/encode/encode.mbt` 16〜38 行（`segments_low` / `segments_mid` / `segments_high`）にあり、`optimal_segments` 本体は `core/src/encode/segment.mbt` にある。いずれの変更も PR diff に現れる

**内容**: auto version 選択が帯ごとの DP を version 試行間で再利用する性質を検知していた `autoElapsed * 2 < forcedElapsed` の比率アサーションを、O(n) DP 化に伴って削除した。絶対時間 5,000ms と auto / forced の version 一致検査は維持している。

**影響**: 帯 DP の再利用を外す変更が入っても、現在のテストでは性能比率から直接検知できない。

**受容理由**: O(n) 化後は行列生成など DP 以外のコストが支配的となり、旧 O(n^2) 実装の性能特性を前提にした比率が成立しなくなった。収まらない 7,088 run 入力で auto 1回と明示 version 1〜40を比較する代替測定も、5回の `forced / auto` 比が 2.9 / 3.5 / 3.4 / 3.2 / 3.5 で、採用条件の最小10倍に届かなかった。実装側へ不要な処理を足して比率を作る方が有害なため、測定不能として明示受容する。

**再検討の条件**: 帯 DP の再利用を外す変更が提案された場合、または DP コストが再び支配的になる変更が入った場合。

---

## RISK-006: デコーダの入力上限内でのピークメモリ

- **Status**: accepted
- **Date**: 2026-08-29
- **anchor**: `core/src/decode/decode.mbt` の `let max_pixels : Int = 16 * 1024 * 1024` の変更は PR diff に現れる。対応環境での OOM・遅延は利用者から GitHub Issue として届く

**内容**: `decode` は `max_pixels` で入力画素数を制限しているが、上限付近ではグレースケール配列1枚と `BitMatrix` 2枚を同時に保持するため、ピークメモリが大きい。`invert=false` でも反転行列を作る現行構造を維持する。

**影響**: メモリ制約の厳しいモバイルブラウザ等で、上限付近の画像を `decode()` へ直接渡すと OOM や大きな遅延に至る可能性がある。

**受容理由**: 上限値と行列表現は、受け入れる画像サイズ、デコード性能、`bench/RESULT.md` の計測主張を一体で検討すべき設計判断である。現時点で実害の報告はなく、データ構造や上限値だけを局所的に変える根拠が足りないため、今回は変更しない。

**再検討の条件**: 対応環境で OOM や実用上の遅延が報告された場合、入力上限を変更する場合、または行列表現を見直す性能改善を行う場合。

---

## RISK-007: SVG 出力の `margin` / `cell` を検証しない

- **Status**: accepted
- **Date**: 2026-08-29
- **anchor**: `core/src/encode/encode_test.mbt` の `to_svg_string_js produces svg or empty on failure` が現行契約（`String` を返す）を CI で固定しており、契約変更はこのテストの diff として PR に現れる。無効 SVG の実害は GitHub Issue として届く

**内容**: MoonBit 公開 API の `to_svg_string` / `to_svg_string_js` は `margin` や `cell` の範囲を検証せず、負値等の不正な指定に対しても `String` を返す現行契約を維持する。

**影響**: 不正な値を渡すと、負の `viewBox` や path 寸法を持つ無効な SVG 文字列が返り得る。`encode` が `Matrix?` で失敗を表す方針とも一貫しない。

**受容理由**: 失敗を呼び出し側に返すには公開 API を `String?` へ変更する必要があり、既存利用者への破壊的変更になる。一方、暗黙のクランプは入力誤りを隠す別の契約変更となる。現時点で実害の報告がないため、独立した破壊的変更として設計できるまで現行契約を保つ。

**再検討の条件**: 無効な SVG による実害が報告された場合、次の破壊的リリースを計画する場合、または MoonBit で互換性を保ちながら失敗を表現できる API を追加する場合。

---

## RISK-008: npm パッケージの `prepack` で build しない

- **Status**: accepted
- **Date**: 2026-08-29
- **anchor**: `RELEASING.md` §6「Verify from outside the repository」で、publish 後に npm から install した実体に対して core の `encode("HELLO")` を ESM 経路で実行し、CJS 経路では `encode` export が `function` であること、および `npx moonqr --version` が公開版を返すことを確認する。core と CLI の stale な bundle はここで露見しうるが、scanner は install の成否までしか観測されない。`packages/*/package.json` の `prepack` 行の変更は PR diff に現れる。stale な bundle による実害は利用者からの GitHub Issue として届く

**内容**: `@elchika-inc/moonqr`、`@elchika-inc/moonqr-scanner`、`@elchika-inc/moonqr-cli` の `prepack` は legal files の複製だけを行い、`build` を実行しない現行のリリース契約を維持する。

**影響**: build 前または古い `dist/` が残った状態で pack / publish しても失敗せず、stale な bundle を出荷し得る。`RELEASING.md` の tarball 内ファイル名検査だけでは内容の鮮度を判定できない。

**受容理由**: core の release build を先に行う必要があり、各パッケージの `prepack` に単純に `build` を足すだけでは、必要なビルド順と発行手順全体を保証できない。これはリリースフローの設計変更であり、次回のリリースで実際の pack / publish 前後を通して検証すべきため、今回は文書修正と切り離す。

**再検討の条件**: 次回の npm リリース手順を実行する場合、stale な生成物の混入が発生または報告された場合、または core から全 npm パッケージまでのクリーン build を単一コマンドで保証できるようにする場合。

---

## RISK-009: 検証済み MoonBit ツールチェイン版の文字列を複数箇所で管理する

- **Status**: accepted
- **Date**: 2026-08-29
- **anchor**: `rg -n '0\.1\.20260713' .github/workflows CONTRIBUTING.md docs/TOOLCHAIN.md` の実行結果。`ci.yml:42`・`pages.yml:37`・`CONTRIBUTING.md:9`・`docs/TOOLCHAIN.md:6` の 4 箇所が同じ値でなければ同期漏れ。移行 PR では 4 ファイルすべてが diff に現れる

**内容**: 検証済み MoonBit ツールチェイン版の文字列は、CI / Pages の workflow の cache key と、`CONTRIBUTING.md` / `docs/TOOLCHAIN.md` の利用者向け記録に重複している。現行の手動同期を維持する。

**影響**: 移行時に一部だけ更新すると、CI と Pages が異なるツールチェインの cache を使う、または文書の検証済み版表示が実態とずれる可能性がある。

**受容理由**: MoonBit の配布元が過去版の固定インストールを提供しない制約は、既存エントリ「MoonBit ツールチェインの版を固定できない」で受容済みである。workflow の cache key と人間向け文書では値の役割が異なり、共通 workflow や外部設定に移しても、未固定の `latest` を検証して全参照先を移行する手動判断は残る。同期不備の実例がない現時点で追加の間接層を持ち込まない。

**再検討の条件**: 版文字列の同期漏れが発生した場合、MoonBit が過去版の指定インストールを提供した場合、または workflow と文書が共通の追跡可能な正本を参照できる機構を導入する場合。

---

## RISK-010: 完了済み CLI 実装計画に生成物の全文を残す

- **Status**: accepted
- **Date**: 2026-08-29
- **anchor**: `packages/cli/package.json` と `packages/cli/tsup.config.ts` への変更は PR diff に現れ、計画文書 `.docs/plans/2026-07-29-terminal-qr-cli-plan.md` は `git log` で変更が無いことを確認できる。計画を正本と誤認した変更は、計画文書側への diff として現れる

**内容**: `.docs/plans/2026-07-29-terminal-qr-cli-plan.md` は、実装時に作成する `packages/cli/package.json` と `packages/cli/tsup.config.ts` の全文を含み、現在の実ファイルとドリフトしている。この完了済み計画を当時の記録として現状のまま保存する。

**影響**: 実装計画内の複製を現行仕様と誤認すると、`packages/cli/` 配下の実ファイルとの差分に迷い、2つ目の正本として扱う可能性がある。

**受容理由**: この文書は実装前の判断と作業手順を保存する完了済み計画である。完成物に追従させるために書き換えると、当時どの内容を前提に実装したかという履歴が失われる。現行の正本は実ファイルであり、完了済み計画の追従更新は行わない。

**再検討の条件**: 計画を現行仕様として誤用した事例が発生した場合、完了済み計画の保存・アーカイブ方針を変更する場合、または歴史を保ったまま正本へのポインタを追加する場合。

---

## RISK-011: デモページに `og:image` を置かない（SHOULD からの逸脱）

- **Status**: accepted
- **Date**: 2026-09-09
- **anchor**: [Issue #41](https://github.com/elchika-inc/moonqr/issues/41) の open / closed 状態。受容が破れた（対応した）ときは Issue が閉じられ、`site/index.html` に `og:image` を足す PR の diff として現れる。逸脱が続いている限り Issue は open のまま残り、標準への未対応が外から見える

**内容**: standards `PRODUCT_PLAYBOOK.md` §2 は landing / docs の head に `og:image` を置くことを SHOULD としているが、デモページ `site/index.html` には OGP 系のタグが 1 つも無い。2026-09-08 の standards 監査（rev.89 参照）で検出した。

**影響**: デモページの URL を Slack・X・GitHub へ貼ったとき、リンクプレビューに画像が出ず、タイトルと説明文だけのカードになる。

**受容理由**: タグの追加自体は小さいが、`og:image` が参照する画像のデザインを決める必要があり、その判断がまだ済んでいない。候補（既存 favicon の QR 図案を 1200×630 に起こす案と、moonqr 自身でデモ URL をエンコードした QR を使う案）と確認方法は Issue #41 に整理した。デザイン判断を伴う作業を `standards_version` の更新に巻き込まず、独立した変更として扱う。

**再検討の条件**: 画像のデザイン方針が決まった場合、デモページの共有が実際に必要になった場合、または OGP を要求する SHOULD が MUST へ格上げされた場合。
