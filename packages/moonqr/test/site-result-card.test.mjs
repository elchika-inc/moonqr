import assert from "node:assert/strict";
import test from "node:test";
import { JSDOM } from "jsdom";
import { buildCameraResult, buildResultCard } from "../../../site/result-card.js";

function withDocument(run) {
  const previousDocument = globalThis.document;
  const dom = new JSDOM();
  globalThis.document = dom.window.document;
  try {
    run();
  } finally {
    globalThis.document = previousDocument;
    dom.window.close();
  }
}

const translate = (key, vars) => (vars ? `${key}:${JSON.stringify(vars)}` : key);

test("site result card keeps a quote-bearing file name inside the alt attribute", () => {
  withDocument(() => {
    const fileName = 'x" onerror="alert(1)  .png';
    const card = buildResultCard(
      { kind: "fail", fileName, thumbUrl: "blob:demo" },
      translate,
    );
    const image = card.querySelector("img");

    assert.ok(image);
    assert.equal(image.alt, fileName);
    assert.equal(image.getAttribute("onerror"), null);
    assert.doesNotMatch(image.outerHTML, /\sonerror="/);
    assert.match(
      image.outerHTML,
      /alt="x&quot; onerror=&quot;alert\(1\)  \.png"/,
    );
  });
});

test("site camera result renders decoded text as text rather than markup", () => {
  withDocument(() => {
    const text = '<img src=x onerror="alert(1)">';
    const card = buildCameraResult({ text, version: 1, ecLevel: "M" }, translate);

    assert.equal(card.querySelectorAll("img").length, 0);
    assert.equal(card.querySelector("dd")?.textContent, text);
  });
});
