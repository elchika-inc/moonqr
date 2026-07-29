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

/** QR 仕様が要求する静穏帯。これを省くとファインダパターンを検出できない。 */
const QUIET = 4;

// 47m（通常輝度の白）は多くの端末で明るいグレーにマップされる。
// 107m（bright white）の方がコントラストに余裕が出る。
const BG_WHITE = "\x1b[107m";
const FG_BLACK = "\x1b[30m";
const RESET = "\x1b[0m";

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
