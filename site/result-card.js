function createStatus(className, text) {
  const status = document.createElement("p");
  status.className = className;
  status.textContent = text;
  return status;
}

function createDefinitionList(rows) {
  const list = document.createElement("dl");
  for (const [label, value] of rows) {
    const term = document.createElement("dt");
    term.textContent = label;
    const description = document.createElement("dd");
    description.textContent = String(value);
    list.append(term, description);
  }
  return list;
}

export function buildResultCard(desc, translate) {
  const card = document.createElement("div");
  card.className = "result-card";

  const image = document.createElement("img");
  image.src = desc.thumbUrl;
  image.alt = desc.fileName;

  const content = document.createElement("div");
  const title = document.createElement("strong");
  title.textContent = desc.fileName;
  content.append(title);

  if (desc.kind === "ok") {
    const scaleNote =
      desc.scale === 1
        ? translate("read.scaleNative")
        : translate("read.scaleN", { scale: desc.scale });
    const attemptsNote = desc.attemptedScales.map((scale) => `1/${scale}`).join(" → ");
    content.append(
      createStatus("status-ok", translate("read.success", { scaleNote })),
      createDefinitionList([
        [translate("read.text"), desc.text],
        [translate("read.version"), desc.version],
        [translate("read.ecLevel"), desc.ecLevel],
        [translate("read.attempts"), attemptsNote],
      ]),
    );
  } else if (desc.kind === "fail") {
    content.append(createStatus("status-err", translate("read.fail")));
  } else {
    content.append(
      createStatus("status-err", translate("read.error", { message: desc.message })),
    );
  }
  card.append(image, content);
  return card;
}

export function buildCameraResult({ text, version, ecLevel }, translate) {
  const card = document.createElement("div");
  card.className = "result-card";
  card.style.border = "none";
  card.style.padding = "0";
  card.style.marginTop = "10px";

  const content = document.createElement("div");
  content.append(
    createStatus("status-ok", translate("camera.detected")),
    createDefinitionList([
      [translate("read.text"), text],
      [translate("read.version"), version],
      [translate("read.ecLevel"), ecLevel],
    ]),
  );
  card.append(content);
  return card;
}
