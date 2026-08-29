import { encode } from "@elchika-inc/moonqr/encode";
import type { EcLevel } from "@elchika-inc/moonqr/encode";
import { render } from "./render.js";

// package.json の version と手動で揃える。cli.test.ts が一致を検証する。
// 実行時に package.json を読むとパス解決が bundle の配置に依存し、bin から
// 呼ぶときと dist から読むときで壊れ方が変わるため、定数として持つ。
const VERSION = "0.1.0";

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

/**
 * 引数を解釈して結果を返す。出力は行わない。
 *
 * 標準出力へ直接書くとテストでプロセス起動かモックが要る。文字列と終了
 * コードを返す形にすることで、全分岐を通常の関数呼び出しで検証できる。
 */
export function run(argv: string[], env: NodeJS.ProcessEnv): RunResult {
  let color = env.NO_COLOR === undefined;
  let ec: EcLevel = "M";
  const rest: string[] = [];

  for (let i = 0; i < argv.length; i++) {
    const a = argv[i]!;
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
