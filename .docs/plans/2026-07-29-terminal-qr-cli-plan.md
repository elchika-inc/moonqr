# ターミナル QR 表示 CLI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 端末に QR コードを描く CLI を `packages/cli/` として新設し、`moonqr <text>` でスマートフォンから読み取れる QR を表示できるようにする。

**Architecture:** モジュール行列を端末文字列へ変換する純粋関数（`render.ts`）と、引数解析・出力だけを行う薄い層（`cli.ts`）に分ける。半角ブロック文字で縦 2 モジュールを 1 セルに詰め、ANSI で白背景・黒前景を常に明示する。

**Tech Stack:** TypeScript + tsup（既存 2 パッケージと同じ）。依存は `@elchika-inc/moonqr` のみで、引数解析ライブラリは追加しない。テストは vitest（既存パッケージと同じ）。

## Global Constraints

- 設計の正本は `.docs/plans/2026-07-29-terminal-qr-cli-design.md`。
- **色は常に付ける。`process.stdout.isTTY` による自動判定を実装してはならない。** 逃げ道は `--no-color` フラグと `NO_COLOR` 環境変数のみ。
- 白背景は **`\x1b[107m`（bright white）**、前景は `\x1b[30m`（黒）。`47m` は端末でグレーになるため使わない。
- 静穏帯は **4 モジュール**（上下左右）。
- 依存に追加してよいのは `@elchika-inc/moonqr` のみ。引数解析ライブラリを足さない。
- パッケージ名は `@elchika-inc/moonqr-cli`、コマンド名は `moonqr`、初版は `0.1.0`（既存パッケージの 0.2.0 に合わせない）。
- QR は stdout、エラーは stderr。
- **`moon fmt` を実行しない。**
- `main` は保護されている。作業ブランチ `feat/terminal-qr-cli` を切り、PR 経由でマージする。
- コミットメッセージは日本語。公開ドキュメント（README）は英語。

## File Structure

| ファイル | 責務 |
|---|---|
| `packages/cli/src/render.ts`（新規） | モジュール行列 → 端末文字列。純粋関数のみ。ANSI の有無を引数で受ける |
| `packages/cli/src/cli.ts`（新規） | 引数解析、`encode` 呼び出し、`render` 呼び出し、stdout/stderr への出力、終了コード |
| `packages/cli/bin/moonqr.js`（新規） | shebang 付きエントリ。`dist/cli.js` を呼ぶだけ |
| `packages/cli/test/render.test.ts`（新規） | `render` の単体テスト |
| `packages/cli/test/roundtrip.test.ts`（新規） | 描画文字列 → 行列復元 → デコードの往復テスト |
| `packages/cli/package.json`・`tsconfig.json`・`tsup.config.ts`・`vitest.config.ts`・`README.md`（新規） | パッケージ定義 |
| `pnpm-workspace.yaml`（確認のみ） | `packages/*` で既に含まれるはず。含まれていなければ追加 |
| `RELEASING.md`（変更） | 公開順序に新パッケージを追加 |

**既存 2 パッケージとの違い**: CLI はライブラリではないため、`exports` マップ・`types`・`dts` 生成は不要。`bin` フィールドが主役で、`format` は ESM のみ。既存の `package.json` をそのままコピーしないこと。

---

### Task 1: パッケージの骨組みと render の最小実装

**Files:**
- Create: `packages/cli/package.json`, `packages/cli/tsconfig.json`, `packages/cli/tsup.config.ts`, `packages/cli/vitest.config.ts`
- Create: `packages/cli/src/render.ts`
- Test: `packages/cli/test/render.test.ts`

**Interfaces:**
- Consumes: `@elchika-inc/moonqr/encode` の `encode(text, options) -> QrMatrix | null`。`QrMatrix` は `{ size: number; get(x, y): boolean }`（配列ではない）
- Produces: `export function render(matrix: QrMatrix, options?: RenderOptions): string`、`export interface RenderOptions { color?: boolean }`（既定 `color: true`）

- [ ] **Step 1: パッケージ定義を作る**

`packages/cli/package.json`:

```json
{
  "name": "@elchika-inc/moonqr-cli",
  "version": "0.1.0",
  "type": "module",
  "description": "Print a QR code to your terminal. Hand a URL from your CLI to your phone by pointing a camera at it.",
  "license": "Apache-2.0",
  "engines": {
    "node": ">=18.18.0"
  },
  "repository": {
    "type": "git",
    "url": "git+https://github.com/elchika-inc/moonqr.git",
    "directory": "packages/cli"
  },
  "homepage": "https://github.com/elchika-inc/moonqr/tree/main/packages/cli#readme",
  "bugs": {
    "url": "https://github.com/elchika-inc/moonqr/issues"
  },
  "publishConfig": {
    "access": "public"
  },
  "keywords": ["qrcode", "qr", "cli", "terminal", "moonbit"],
  "files": ["dist", "bin", "README.md", "LICENSE", "NOTICE", "THIRD_PARTY_LICENSES"],
  "bin": {
    "moonqr": "./bin/moonqr.js"
  },
  "scripts": {
    "build": "tsup",
    "test:unit": "vitest run",
    "typecheck": "tsc --noEmit -p tsconfig.json",
    "prepack": "node ../../scripts/copy-legal-files.mjs"
  },
  "dependencies": {
    "@elchika-inc/moonqr": "workspace:^"
  },
  "devDependencies": {
    "tsup": "^8.5.1",
    "typescript": "^6.0.3",
    "vitest": "^4.1.10"
  }
}
```

`packages/cli/tsup.config.ts`（ライブラリではないので `dts` なし・ESM のみ）:

```typescript
import { defineConfig } from "tsup";

export default defineConfig({
  // 実行ファイルであり誰も import しないため、型定義（dts）は生成しない。
  // Node が直接実行するので CJS も不要。
  entry: ["src/cli.ts"],
  format: ["esm"],
  dts: false,
  minify: false,
  clean: true,
});
```

`packages/cli/tsconfig.json` は `packages/scanner/tsconfig.json` をそのままコピーする（同じ TS 設定でよい）。

`packages/cli/vitest.config.ts`:

```typescript
import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    include: ["test/**/*.test.ts"],
  },
});
```

- [ ] **Step 2: 失敗するテストを書く**

`packages/cli/test/render.test.ts`:

```typescript
import { describe, it, expect } from "vitest";
import { encode } from "@elchika-inc/moonqr/encode";
import { render } from "../src/render.js";

const matrix = () => {
  const m = encode("HELLO", { ecLevel: "M" });
  if (!m) throw new Error("encode failed");
  return m;
};

describe("render", () => {
  it("packs two module rows into one character cell", () => {
    const m = matrix();          // v1 = 21x21
    const out = render(m, { color: false });
    const lines = out.split("\n").filter((l) => l.length > 0);
    // 静穏帯 4 モジュール x 2 辺 = 8 を足し、縦は 2 行で 1 セル
    expect(lines.length).toBe(Math.ceil((m.size + 8) / 2));
  });

  it("adds a 4-module quiet zone on every side", () => {
    const m = matrix();
    const out = render(m, { color: false });
    const lines = out.split("\n").filter((l) => l.length > 0);
    // 上 4 モジュール = 2 行分が空白のみ
    expect(lines[0].trim()).toBe("");
    expect(lines[1].trim()).toBe("");
    // 各行の左端 4 文字が空白（左の静穏帯）
    for (const line of lines) {
      expect(line.slice(0, 4)).toBe("    ");
    }
  });

  it("emits no ANSI escapes when color is disabled", () => {
    const out = render(matrix(), { color: false });
    expect(out).not.toContain("[");
  });

  it("wraps every line with bright-white background and black foreground when color is enabled", () => {
    const out = render(matrix(), { color: true });
    // 47m ではなく 107m（bright white）を使う。47m は端末でグレーになる
    expect(out).toContain("[107m");
    expect(out).toContain("[30m");
    expect(out).toContain("[0m");
    expect(out).not.toContain("[47m");
  });

  it("defaults to color enabled", () => {
    expect(render(matrix())).toContain("[107m");
  });

  it("uses the half-block mapping for module pairs", () => {
    const m = matrix();
    const out = render(m, { color: false });
    // ファインダパターン左上の角は暗いモジュールなので、
    // 静穏帯を除いた最初のセルは上下とも暗い = 全ブロック
    const lines = out.split("\n").filter((l) => l.length > 0);
    const firstContentLine = lines[2]; // 静穏帯 4 モジュール = 2 行の後
    expect(firstContentLine[4]).toBe("█");
  });
});
```

- [ ] **Step 3: テストが失敗することを確認する**

```sh
pnpm --filter @elchika-inc/moonqr-cli test:unit
```

Expected: `render` が存在せず import エラー。

- [ ] **Step 4: render を実装する**

`packages/cli/src/render.ts`:

```typescript
/**
 * QR のモジュール行列を端末に描ける文字列へ変換する。
 *
 * 端末の文字セルは縦長（おおむね 1:2）なので、1 セルに 1 モジュールを対応
 * させると QR が縦に伸びて読み取れない。半角ブロック文字は 1 セルの上下を
 * 独立に塗れるため、縦に並ぶ 2 モジュールを 1 セルで表現する。
 */
import type { QrMatrix } from "@elchika-inc/moonqr/encode";

export interface RenderOptions {
  /** ANSI で白背景・黒前景を指定するか（既定 true） */
  color?: boolean;
}

/** QR 仕様が要求する静穏帯（これを省くとファインダパターンを検出できない） */
const QUIET = 4;

const BG_WHITE = "[107m"; // bright white。47m は端末でグレーになる
const FG_BLACK = "[30m";
const RESET = "[0m";

export function render(matrix: QrMatrix, options: RenderOptions = {}): string {
  const color = options.color ?? true;
  const n = matrix.size;
  const size = n + QUIET * 2;

  // 静穏帯の外側は常に明るいモジュール
  const dark = (x: number, y: number): boolean => {
    const mx = x - QUIET;
    const my = y - QUIET;
    if (mx < 0 || my < 0 || mx >= n || my >= n) return false;
    return matrix.get(mx, my);
  };

  const lines: string[] = [];
  for (let y = 0; y < size; y += 2) {
    let line = "";
    for (let x = 0; x < size; x++) {
      const top = dark(x, y);
      const bottom = y + 1 < size ? dark(x, y + 1) : false;
      // 前景色が黒なので「塗られている = 暗いモジュール」になる
      line += top && bottom ? "█" : top ? "▀" : bottom ? "▄" : " ";
    }
    lines.push(color ? BG_WHITE + FG_BLACK + line + RESET : line);
  }
  return lines.join("\n") + "\n";
}
```

- [ ] **Step 5: テストが通ることを確認する**

```sh
pnpm --filter @elchika-inc/moonqr-cli test:unit
```

Expected: 6 テストすべて PASS。

- [ ] **Step 6: コミットする**

```sh
git add packages/cli
git commit -m "feat(cli): モジュール行列を端末文字列へ変換する render を追加

端末の文字セルは縦長のため、1セル1モジュールだとQRが縦に伸びて読めない。
半角ブロック文字で縦2モジュールを1セルに詰める。

白背景は 107m（bright white）を使う。47m は多くの端末で明るいグレーに
マップされ、コントラストの余裕が減るため。"
```

---

### Task 2: CLI 本体（引数解析・出力・終了コード）

**Files:**
- Create: `packages/cli/src/cli.ts`, `packages/cli/bin/moonqr.js`
- Test: `packages/cli/test/cli.test.ts`

**Interfaces:**
- Consumes: `render(matrix, { color }) -> string`（Task 1）、`encode(text, { ecLevel }) -> QrMatrix | null`
- Produces: `export function run(argv: string[], env: NodeJS.ProcessEnv): { stdout: string; stderr: string; code: number }` — 実際の出力は行わず結果を返す純粋関数。`bin/moonqr.js` から呼ぶ

**なぜ `run` が出力しないか**: 標準出力へ直接書くとテストで捕まえにくい。文字列と終了コードを返す形にすれば、プロセスを起動せずに全分岐をテストできる。

- [ ] **Step 1: 失敗するテストを書く**

`packages/cli/test/cli.test.ts`:

```typescript
import { describe, it, expect } from "vitest";
import { run } from "../src/cli.js";

const noEnv = {} as NodeJS.ProcessEnv;

describe("run", () => {
  it("prints a QR to stdout and exits 0", () => {
    const r = run(["https://example.com"], noEnv);
    expect(r.code).toBe(0);
    expect(r.stderr).toBe("");
    expect(r.stdout).toContain("█");
  });

  it("colors output by default", () => {
    expect(run(["hi"], noEnv).stdout).toContain("[107m");
  });

  it("drops color with --no-color", () => {
    const r = run(["--no-color", "hi"], noEnv);
    expect(r.stdout).not.toContain("[");
    expect(r.code).toBe(0);
  });

  it("drops color when NO_COLOR is set", () => {
    const r = run(["hi"], { NO_COLOR: "1" } as NodeJS.ProcessEnv);
    expect(r.stdout).not.toContain("[");
  });

  it("does not consult isTTY", () => {
    // 設計上の決定: 端末かどうかで色を変えない。
    // Claude Code 等から呼ぶと isTTY が undefined になり、
    // 自動判定を入れると主用途で必ず色が落ちるため。
    const src = String(run);
    expect(src).not.toContain("isTTY");
  });

  it("accepts an error-correction level", () => {
    const r = run(["-e", "H", "hi"], noEnv);
    expect(r.code).toBe(0);
    expect(r.stdout).toContain("█");
  });

  it("rejects an invalid error-correction level", () => {
    const r = run(["-e", "Z", "hi"], noEnv);
    expect(r.code).toBe(1);
    expect(r.stderr).toContain("Z");
    expect(r.stdout).toBe("");
  });

  it("shows usage and exits 1 when given no text", () => {
    const r = run([], noEnv);
    expect(r.code).toBe(1);
    expect(r.stderr).toContain("Usage");
    expect(r.stdout).toBe("");
  });

  it("shows help on --help and exits 0", () => {
    const r = run(["--help"], noEnv);
    expect(r.code).toBe(0);
    expect(r.stdout).toContain("Usage");
  });

  it("reports input that does not fit in a QR code", () => {
    // Model 2 の byte モード最大は 2953 バイト。確実に超える長さを渡す
    const r = run(["x".repeat(5000)], noEnv);
    expect(r.code).toBe(1);
    expect(r.stderr).toContain("too long");
    expect(r.stdout).toBe("");
  });
});
```

- [ ] **Step 2: テストが失敗することを確認する**

```sh
pnpm --filter @elchika-inc/moonqr-cli test:unit
```

Expected: `run` が存在せず import エラー。

- [ ] **Step 3: cli.ts を実装する**

```typescript
import { encode } from "@elchika-inc/moonqr/encode";
import type { EcLevel } from "@elchika-inc/moonqr/encode";
import { render } from "./render.js";

export interface RunResult {
  stdout: string;
  stderr: string;
  code: number;
}

const USAGE = `Usage: moonqr <text>

Print a QR code to your terminal.

Options:
  -e, --ec <L|M|Q|H>   Error correction level (default: M)
      --no-color       Do not emit ANSI colors
  -h, --help           Show this help
  -v, --version        Show the version

The output is always colored unless you opt out. A QR code needs a light
background to be readable, and terminal themes vary, so the background is
declared explicitly rather than guessed from the environment.
`;

const EC_LEVELS = ["L", "M", "Q", "H"] as const;

function isEcLevel(v: string): v is EcLevel {
  return (EC_LEVELS as readonly string[]).includes(v);
}

export function run(argv: string[], env: NodeJS.ProcessEnv): RunResult {
  let color = env.NO_COLOR === undefined;
  let ec: EcLevel = "M";
  const rest: string[] = [];

  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === "--help" || a === "-h") {
      return { stdout: USAGE, stderr: "", code: 0 };
    }
    if (a === "--version" || a === "-v") {
      return { stdout: `${VERSION}\n`, stderr: "", code: 0 };
    }
    if (a === "--no-color") {
      color = false;
      continue;
    }
    if (a === "-e" || a === "--ec") {
      const v = argv[++i];
      if (v === undefined || !isEcLevel(v)) {
        return {
          stdout: "",
          stderr: `moonqr: invalid error correction level: ${v ?? "(missing)"}\n`,
          code: 1,
        };
      }
      ec = v;
      continue;
    }
    rest.push(a);
  }

  const text = rest.join(" ");
  if (text.length === 0) {
    return { stdout: "", stderr: USAGE, code: 1 };
  }

  const matrix = encode(text, { ecLevel: ec });
  if (matrix === null) {
    return {
      stdout: "",
      stderr: "moonqr: input is too long to fit in a QR code\n",
      code: 1,
    };
  }

  return { stdout: render(matrix, { color }), stderr: "", code: 0 };
}
```

`VERSION` は定数として持つ。次の 1 行をファイル冒頭（import の直後）に置く。

```typescript
// package.json の version と手動で揃える。リリース手順（RELEASING.md）で確認する。
const VERSION = "0.1.0";
```

**なぜ `package.json` を読まないか**: 実行時に読むとパス解決が bundle の配置に依存し、`bin` から呼ぶときと dist から import するときで壊れ方が変わる。tsup の `define` でビルド時に注入することもできるが、設定とビルド時の値の流れが増える。二重管理は `RELEASING.md` の手順で担保する方が、この規模では読みやすい。

- [ ] **Step 4: bin エントリを作る**

`packages/cli/bin/moonqr.js`:

```javascript
#!/usr/bin/env node
import { run } from "../dist/cli.js";

const { stdout, stderr, code } = run(process.argv.slice(2), process.env);
if (stdout) process.stdout.write(stdout);
if (stderr) process.stderr.write(stderr);
process.exit(code);
```

実行権限を付ける。

```sh
chmod +x packages/cli/bin/moonqr.js
```

- [ ] **Step 5: テストが通ることを確認する**

```sh
pnpm --filter @elchika-inc/moonqr-cli test:unit
```

Expected: Task 1 の 6 件と合わせて全件 PASS。

- [ ] **Step 6: 実際に動かす**

```sh
cd packages/cli && pnpm build && cd ../..
node packages/cli/bin/moonqr.js "https://example.com"
```

Expected: 端末に QR が表示される。白背景・黒モジュールで、上下左右に余白がある。

- [ ] **Step 7: コミットする**

```sh
git add packages/cli
chmod +x packages/cli/bin/moonqr.js
git commit -m "feat(cli): 引数解析と出力を行う CLI 本体を追加

run() は出力せず {stdout, stderr, code} を返す純粋関数にした。
プロセスを起動せずに全分岐をテストできるため。

isTTY による色の自動判定は実装しない。QRにおける背景色は装飾ではなく
機能であり、落とすと端末テーマ次第で反転する。Claude Code 経由では
isTTY が undefined になることも実測しており、自動判定は主用途で
必ず裏目に出る。"
```

---

### Task 3: 往復テスト（描画が正しいことの機械的検証）

**Files:**
- Create: `packages/cli/test/roundtrip.test.ts`

**Interfaces:**
- Consumes: `render`（Task 1）、`@elchika-inc/moonqr/decode` の `decode(data, width, height, options?) -> DecodeResult | null`
- Produces: なし

**考え方**: ブロック文字と上下 2 モジュールの対応規則が決まっているため、出力文字列から論理行列を復元できる。復元した行列を画素へ展開してデコーダに通せば、「見た目は QR に見えるが 1 モジュールずれている」類の不具合を機械的に検出できる。

- [ ] **Step 1: 往復テストを書く**

```typescript
import { describe, it, expect } from "vitest";
import { encode } from "@elchika-inc/moonqr/encode";
import { decode } from "@elchika-inc/moonqr/decode";
import { render } from "../src/render.js";

/** render の出力（色なし）から論理行列を復元する */
function parse(rendered: string): boolean[][] {
  const lines = rendered.split("\n").filter((l) => l.length > 0);
  const width = lines[0].length;
  const rows: boolean[][] = [];
  for (const line of lines) {
    const top: boolean[] = [];
    const bottom: boolean[] = [];
    for (let x = 0; x < width; x++) {
      const c = line[x];
      top.push(c === "█" || c === "▀");
      bottom.push(c === "█" || c === "▄");
    }
    rows.push(top, bottom);
  }
  return rows;
}

/** 論理行列を 4px/セルの RGBA へ展開する */
function rasterize(rows: boolean[][]): { data: Uint8ClampedArray; size: number } {
  const CELL = 4;
  const h = rows.length;
  const w = rows[0].length;
  const px = Math.max(w, h) * CELL;
  const data = new Uint8ClampedArray(px * px * 4).fill(255);
  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      if (!rows[y][x]) continue;
      for (let dy = 0; dy < CELL; dy++) {
        for (let dx = 0; dx < CELL; dx++) {
          const i = ((y * CELL + dy) * px + x * CELL + dx) * 4;
          data[i] = data[i + 1] = data[i + 2] = 0;
        }
      }
    }
  }
  return { data, size: px };
}

const CASES = [
  "https://example.com",
  "https://elchika-inc.github.io/moonqr/",
  "HELLO WORLD",
  "1234567890",
  "https://github.com/elchika-inc/moonqr/pull/10",
];

describe("rendered output is a readable QR code", () => {
  for (const text of CASES) {
    it(`round-trips: ${text}`, () => {
      const m = encode(text, { ecLevel: "M" });
      if (!m) throw new Error("encode failed");
      const { data, size } = rasterize(parse(render(m, { color: false })));
      const result = decode(data, size, size);
      expect(result?.text).toBe(text);
    });
  }

  it("round-trips at every error correction level", () => {
    for (const ec of ["L", "M", "Q", "H"] as const) {
      const text = "https://example.com/ec-" + ec;
      const m = encode(text, { ecLevel: ec });
      if (!m) throw new Error("encode failed");
      const { data, size } = rasterize(parse(render(m, { color: false })));
      expect(decode(data, size, size)?.text).toBe(text);
    }
  });
});
```

- [ ] **Step 2: テストを実行する**

```sh
pnpm --filter @elchika-inc/moonqr-cli test:unit
```

Expected: 全件 PASS。

失敗した場合、`parse` のブロック文字対応か `render` のどちらかがずれている。`render` の出力を目視して、静穏帯の行数と左端の空白数を確認する。

- [ ] **Step 3: コミットする**

```sh
git add packages/cli/test/roundtrip.test.ts
git commit -m "test(cli): 描画文字列を行列へ復元してデコードする往復テスト

端末出力は目視でしか確認できないと思われがちだが、ブロック文字と
上下2モジュールの対応規則が決まっているため文字列から論理行列を
復元できる。デコーダに通すことで、見た目はQRに見えるが1モジュール
ずれている類の不具合をCIで検出できる。"
```

---

### Task 4: README・ワークスペース確認・リリース手順の更新

**Files:**
- Create: `packages/cli/README.md`
- Modify: `RELEASING.md`
- Modify: `README.md`（Packages 表に 1 行追加）
- Verify: `pnpm-workspace.yaml`

**Interfaces:**
- Consumes: Task 1〜3 の成果
- Produces: なし（最終タスク）

- [ ] **Step 1: ワークスペースに含まれることを確認する**

```sh
cat pnpm-workspace.yaml
pnpm --filter @elchika-inc/moonqr-cli exec node -e 'console.log("in workspace")'
```

Expected: `packages/*` が含まれており、フィルタが解決できる。解決できなければ `pnpm-workspace.yaml` に `packages/cli` を追加する。

- [ ] **Step 2: パッケージ README を書く**

`packages/cli/README.md`:

````markdown
# @elchika-inc/moonqr-cli

Print a QR code to your terminal.

Useful when something in your terminal produces a URL — a dev server address, a preview
deployment, a pull request — and you want it on your phone. Point a camera at the screen instead
of retyping it.

```sh
npx @elchika-inc/moonqr-cli "https://example.com"
```

Or install it:

```sh
npm install -g @elchika-inc/moonqr-cli
moonqr "https://example.com"
```

## Options

| Option | Default | |
|---|---|---|
| `-e, --ec <L\|M\|Q\|H>` | `M` | Error correction level |
| `--no-color` | | Do not emit ANSI colors |
| `-h, --help` | | Show usage |
| `-v, --version` | | Show the version |

`NO_COLOR` is honoured as well.

## Why the output is always colored

Most CLI tools drop color when their output is not a terminal. This one does not, because the
output here is not text to be read — it is an image to be photographed. A QR code needs a light
background and dark modules; if the colors are left to the terminal theme, a dark theme inverts
them and readability becomes a matter of luck.

The background is therefore declared explicitly, always. Use `--no-color` or `NO_COLOR` if you
need the raw block characters.

## How it fits on screen

Two module rows are packed into each character cell using half-block characters, because terminal
cells are roughly twice as tall as they are wide. A URL typically renders in about 19 rows by 37
columns, which fits an 80×24 terminal without scrolling.

## License

Apache-2.0. See [LICENSE](LICENSE), [NOTICE](NOTICE), and
[THIRD_PARTY_LICENSES](THIRD_PARTY_LICENSES).
````

- [ ] **Step 3: ルート README の Packages 表に追加する**

`README.md` の Packages の表に次の行を足す（既存 2 行の下）。

```markdown
| [`@elchika-inc/moonqr-cli`](packages/cli) | Command-line tool that prints a QR code to your terminal — hand a URL from your shell to your phone. | [README](packages/cli/README.md) |
```

- [ ] **Step 4: RELEASING.md に新パッケージを追加する**

`RELEASING.md` の冒頭にあるレジストリ一覧を次のように書き換える。

```markdown
Four artifacts are involved, published in this order:

1. `@elchika-inc/moonqr` (npm)
2. `@elchika-inc/moonqr-scanner` (npm) — depends on the above, so the order is not optional
3. `@elchika-inc/moonqr-cli` (npm) — also depends on the core
4. `naoto24kawa/moonqr` (mooncakes.io) — the MoonBit source module
```

「2. Bump versions」の節に、CLI がバージョンを独立させている旨を追記する。

```markdown
`@elchika-inc/moonqr-cli` is versioned independently — it does not have to match the core. Its
version is also duplicated in `packages/cli/src/cli.ts` as `VERSION`; update both.
```

- [ ] **Step 5: 全テスト層を通す**

```sh
export PATH="$HOME/.moon/bin:$PATH"
cd core && moon test --target js && cd ..
pnpm -r build
pnpm -r typecheck
pnpm -r test:unit
node --test packages/moonqr/test/*.test.mjs
```

Expected: 全層 PASS。既存パッケージのテストが壊れていないことも確認する。

- [ ] **Step 6: tarball の中身を検証する**

```sh
pnpm --filter @elchika-inc/moonqr-cli pack --pack-destination /tmp
tar tzf /tmp/elchika-inc-moonqr-cli-0.1.0.tgz | sort
```

Expected: `dist/`、`bin/moonqr.js`、`README.md`、`LICENSE`、`NOTICE`、`THIRD_PARTY_LICENSES` のみ。ソースやテストが混ざっていないこと。内部依存が `workspace:^` ではなく実バージョンに書き換わっていること。

```sh
tar xzOf /tmp/elchika-inc-moonqr-cli-0.1.0.tgz package/package.json | grep -A3 '"dependencies"'
```

- [ ] **Step 7: コミットして PR を作る**

```sh
git add packages/cli/README.md README.md RELEASING.md
git commit -m "docs(cli): READMEとリリース手順を追加

公開順序にCLIを加えた。CLIはコアとバージョンを独立させるため、その旨も
RELEASING.mdに明記した。VERSION定数とpackage.jsonの二重管理になるので
リリース手順で両方更新することを書いた。"
git push -u origin feat/terminal-qr-cli
gh pr create --title "feat(cli): ターミナルにQRを表示するCLI" --body-file <(cat <<'BODY'
## What this changes

Adds `@elchika-inc/moonqr-cli`, a command that prints a QR code to the terminal.

The motivation is handing URLs from a CLI session to a phone. When an agent or a dev server prints
a URL, retyping it is the slow part; pointing a camera at the screen is not.

```sh
npx @elchika-inc/moonqr-cli "https://example.com"
```

Feasibility was measured before designing: a rendered QR was read successfully by a phone camera,
and a URL fits in roughly 19 rows × 37 columns — inside a standard 80×24 terminal, no scrolling.

## Deliberate deviation: color is always on

Most CLI tools drop ANSI color when stdout is not a TTY. This one does not.

For a normal tool, color is decoration. Here the background color is *function*: a QR code needs a
light background, and leaving it to the terminal theme means a dark theme inverts the image.
Readability would depend on the reader's settings.

Measured additionally: running through an agent's shell reports `process.stdout.isTTY` as
`undefined`, so an automatic check would strip color in exactly the situation this tool exists for.
`--no-color` and `NO_COLOR` remain as opt-outs.

## Verification

Rendering is checked mechanically, not just by eye. The half-block characters map to module pairs
by a fixed rule, so the rendered string can be parsed back into a matrix, rasterized, and fed to
the decoder — catching "looks like a QR code but is off by one module" in CI.

## Type of change

- [ ] Bug fix
- [x] New feature
- [ ] Documentation
- [ ] Chore / build / CI

## Provenance

- [x] **Not copied from another project**
- [ ] **Ported from another project**
- [x] **Written or generated with an AI assistant** — and it has been reviewed line by line

## Tests

- [x] `cd core && moon test --target js`
- [x] `node --test packages/moonqr/test/*.test.mjs`
- [x] `pnpm -r test:unit`
- [x] `pnpm -r typecheck`

## Checklist

- [x] I did **not** run `moon fmt`
- [x] I understand `core/_build/` is gitignored but required
- [x] Changes are scoped; no unrelated reformatting
BODY
)
```

---

## 完了条件

- `node packages/cli/bin/moonqr.js "https://example.com"` が端末に QR を表示する
- 往復テストが全ケースで PASS（描画から復元した行列がデコードでき、元テキストと一致）
- `isTTY` を参照するコードが存在しない（テストで固定済み）
- 既存パッケージのテストが壊れていない
- tarball に `dist` / `bin` / 法務 3 点のみが含まれる
- **実機のスマートフォンで読み取れる**（人力ゲート）
