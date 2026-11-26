const status = document.getElementById("status");
const list = document.getElementById("list");
const modelInput = document.getElementById("model");
const note = document.getElementById("model-note");
const refresh = document.getElementById("refresh");
const state = { settings: { cli: "", model: "", instructions: "" }, providers: null, unchecked: false };
let attempts = 0;
let modelTimer = 0;

function textSetting(values, key) {
  return values && typeof values[key] === "string" ? values[key] : "";
}

function normalize(values) {
  return {
    cli: textSetting(values, "cli"),
    model: textSetting(values, "model"),
    instructions: textSetting(values, "instructions"),
  };
}

function row(value, title, detail, disabled) {
  const label = document.createElement("label");
  label.className = "row";
  const input = document.createElement("input");
  input.type = "radio";
  input.name = "cli";
  input.value = value;
  input.disabled = disabled;
  const name = document.createElement("span");
  name.className = "name";
  name.textContent = title;
  const meta = document.createElement("span");
  meta.className = "meta";
  meta.textContent = detail;
  label.append(input, name, meta);
  return label;
}

function selectedId() {
  return state.settings.cli.trim();
}

function updateNote() {
  const providers = state.providers;
  const selected = selectedId();
  const model = modelInput.value.trim();
  note.classList.remove("error");
  if (!providers) {
    note.textContent = "";
    return;
  }
  if (selected && !providers.some(provider => provider.id === selected)) {
    note.textContent = `Unknown CLI "${selected}". Choose one from the list.`;
    note.classList.add("error");
    return;
  }
  const chosen = selected
    ? providers.find(provider => provider.id === selected)
    : providers.find(provider => provider.installed);
  if (!state.unchecked && selected && chosen && !chosen.installed) {
    note.textContent = `${chosen.name} is not installed. Choose Automatic or an installed CLI.`;
    note.classList.add("error");
    return;
  }
  if (!chosen) {
    note.textContent = state.unchecked ? "" : "No CLI is installed. Automatic uses the first one you install.";
    if (!state.unchecked) note.classList.add("error");
    return;
  }
  if (!chosen.modelFlag) {
    note.textContent = `${chosen.name} has no confirmed model flag. Leave the model blank to use its default.`;
    if (model) note.classList.add("error");
    return;
  }
  note.textContent = "Leave blank to use this CLI's default.";
}

function syncSelection() {
  const selected = selectedId() || "automatic";
  for (const input of list.querySelectorAll("input")) input.checked = input.value === selected;
  updateNote();
}

function renderList(providers) {
  const first = providers.find(provider => provider.installed);
  const selected = selectedId();
  const automaticDetail = state.unchecked
    ? "Install state unknown"
    : first
      ? `Uses ${first.name}`
      : "Nothing installed";
  list.replaceChildren(row("automatic", "Automatic", automaticDetail, false));
  for (const provider of providers) {
    const stuck = !provider.installed && provider.id === selected;
    const detail = provider.installed
      ? provider.executable
      : state.unchecked
        ? provider.executable
        : `${provider.executable} · Not installed`;
    list.append(row(provider.id, provider.name, detail, !state.unchecked && !provider.installed && !stuck));
  }
  syncSelection();
}

function applyCatalog(payload) {
  refresh.disabled = false;
  const data = payload || {};
  if (Array.isArray(data.providers)) {
    state.unchecked = data.unchecked === true;
    state.providers = data.providers;
    renderList(state.providers);
  }
  status.textContent = data.error || (data.pending ? "Looking for installed CLIs…" : "");
}

async function requestDetect() {
  status.textContent = "Looking for installed CLIs…";
  refresh.disabled = true;
  try {
    await muxy.events.emit("extension.detect", {});
  } catch (error) {
    refresh.disabled = false;
    attempts += 1;
    if (attempts < 8) {
      status.textContent = "Waiting for the extension to start…";
      setTimeout(requestDetect, 400);
      return;
    }
    status.textContent = error.message || String(error);
  }
}

async function saveModel() {
  clearTimeout(modelTimer);
  const value = modelInput.value;
  if (value === state.settings.model) {
    updateNote();
    return;
  }
  try {
    await muxy.settings.set("model", value);
    state.settings.model = value;
  } catch (error) {
    status.textContent = error.message || String(error);
  }
  updateNote();
}

async function start() {
  state.settings = normalize(await muxy.settings.all());
  modelInput.value = state.settings.model;
  muxy.events.subscribe("settings.changed", async () => {
    state.settings = normalize(await muxy.settings.all());
    if (document.activeElement !== modelInput) modelInput.value = state.settings.model;
    if (state.providers) renderList(state.providers);
    else updateNote();
  });
  muxy.events.subscribe("extension.detected", applyCatalog);
  list.addEventListener("change", async event => {
    const value = event.target.value;
    const cli = value === "automatic" ? "" : value;
    try {
      await muxy.settings.set("cli", cli);
      state.settings.cli = cli;
    } catch (error) {
      status.textContent = error.message || String(error);
    }
    updateNote();
  });
  modelInput.addEventListener("input", () => {
    clearTimeout(modelTimer);
    modelTimer = setTimeout(saveModel, 200);
    updateNote();
  });
  modelInput.addEventListener("change", saveModel);
  refresh.addEventListener("click", () => {
    attempts = 0;
    requestDetect();
  });
  requestDetect();
}

start().catch(error => {
  status.textContent = error.message || String(error);
});
