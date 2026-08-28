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

it("returns result:null when the inline fallback decoder throws", async () => {
  decoders.native.mockImplementation(() => {
    throw new Error("decoder panic");
  });
  vi.stubGlobal("Worker", undefined);
  const { createWorkerHandle } = await import("./worker-handle.js");
  const handle = createWorkerHandle();
  const onmessage = vi.fn();
  const onerror = vi.fn();
  handle.onmessage = onmessage;
  handle.onerror = onerror;

  handle.postMessage(
    { id: 23, buffer: new ArrayBuffer(4), width: 1, height: 1 },
    [],
  );
  await Promise.resolve();

  expect(onmessage).toHaveBeenCalledWith({ data: { id: 23, result: null } });
  expect(onerror).not.toHaveBeenCalled();
});

it("does not reinterpret an inline fallback consumer error as a decode failure", async () => {
  decoders.native.mockReturnValue(null);
  vi.stubGlobal("Worker", undefined);
  vi.stubGlobal("queueMicrotask", (callback: VoidFunction) => callback());
  const { createWorkerHandle } = await import("./worker-handle.js");
  const handle = createWorkerHandle();
  const onmessage = vi.fn(() => {
    throw new Error("consumer failure");
  });
  handle.onmessage = onmessage;

  expect(() =>
    handle.postMessage(
      { id: 29, buffer: new ArrayBuffer(4), width: 1, height: 1 },
      [],
    ),
  ).toThrow("consumer failure");
  expect(onmessage).toHaveBeenCalledTimes(1);
});
