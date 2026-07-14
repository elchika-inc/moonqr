// getUserMedia起動 → video要素へアタッチ → 再生開始、の一連の手続き。
//
// 失敗（権限拒否・対応デバイスなし・play()失敗）は握りつぶさず Error として throw する
// （呼び出し元の QrScanner#start() が Promise を reject するのはこの throw に委ねている）。

export interface CameraOptions {
  facingMode: "environment" | "user";
}

function toError(cause: unknown, prefix: string): Error {
  const message = cause instanceof Error ? cause.message : String(cause);
  return new Error(`${prefix}: ${message}`, { cause });
}

/**
 * カメラストリームを取得し、`video` にアタッチして再生を開始する。
 * 戻り値の `MediaStream` は呼び出し元（QrScanner）が `stop()` 時に解放する責務を持つ。
 */
export async function startCamera(
  video: HTMLVideoElement,
  options: CameraOptions,
): Promise<MediaStream> {
  if (typeof navigator === "undefined" || !navigator.mediaDevices?.getUserMedia) {
    throw new Error("getUserMedia is not available in this environment");
  }

  let stream: MediaStream;
  try {
    stream = await navigator.mediaDevices.getUserMedia({
      video: { facingMode: options.facingMode },
    });
  } catch (cause) {
    throw toError(cause, "Failed to access camera");
  }

  video.srcObject = stream;
  try {
    await video.play();
  } catch (cause) {
    // play() 失敗時は取得済みストリームをリークさせない（呼び出し元は例外経路のため
    // stop() を通らずここで解放する必要がある）。
    for (const track of stream.getTracks()) track.stop();
    throw toError(cause, "Failed to start video playback");
  }

  return stream;
}
