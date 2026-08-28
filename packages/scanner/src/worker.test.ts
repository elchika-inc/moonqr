import { afterEach, expect, it, vi } from "vitest";

const decoders = vi.hoisted(() => ({
  native: vi.fn(),
  multiscale: vi.fn(),
}));

vi.mock("./decode-core.js", () => ({
  decodeNative: decoders.native,
  decodeMultiScale: decoders.multiscale,
}));

afterEach(() => {
  vi.resetModules();
  vi.unstubAllGlobals();
  decoders.native.mockReset();
  decoders.multiscale.mockReset();
});

it.each([
  [false, "native", decoders.native],
  [true, "multiscale", decoders.multiscale],
] as const)("returns result:null when the %s=%s decoder throws", async (multiscale, _name, decoder) => {
  decoder.mockImplementation(() => {
    throw new Error("decoder panic");
  });
  const postMessage = vi.fn();
  const workerGlobal = {
    onmessage: null as ((event: { data: unknown }) => void) | null,
    postMessage,
  };
  vi.stubGlobal("self", workerGlobal);
  await import("./worker.js");

  expect(() =>
    workerGlobal.onmessage?.({
      data: {
        id: 17,
        buffer: new ArrayBuffer(4),
        width: 1,
        height: 1,
        multiscale,
      },
    }),
  ).not.toThrow();
  expect(postMessage).toHaveBeenCalledWith({ id: 17, result: null });
});
