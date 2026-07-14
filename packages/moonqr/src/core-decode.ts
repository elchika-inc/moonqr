// MoonBit デコーダ（core/_build/js/release/build/decode/decode.js）への内部バインディング層。
//
// **重要（サブパス分割の要）**: このファイルは encode.js を import してはならない。
// また、encode 側のコード（src/encode.ts / core-encode.ts）からこのモジュールを import しても
// ならない。理由は core-encode.ts の冒頭コメントを参照（共有チャンク経由で decode.js が
// encode 消費者に流れ込むのを防ぐため）。
import { decode_js } from "../../../core/_build/js/release/build/decode/decode.js";

/**
 * QR をデコードする（MoonBit `decode_js` の薄いラッパ）。Task 4 で公開 API に配線する。
 * data: 2値化済みの1バイト/px（0=白 それ以外=黒）想定 / width, height: 画像サイズ / invert: 反転読取
 * 戻り値: デコードされたテキスト。失敗時は空文字列。
 */
export const decodeJs: (
  data: Uint8Array,
  width: number,
  height: number,
  invert: boolean,
) => string = decode_js;
