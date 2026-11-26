const PROMPT_LIMIT = 256 * 1024;
const OUTPUT_LIMIT = 256 * 1024;
const TIMEOUT_MS = 300000;
const RUBRIC = [
  "Rewrite the prompt below so it is clearer.",
  "Keep the user's goal.",
  "State the objective, the context, the constraints, and the expected format when the original text supports them.",
  "Do not invent requirements, files, technologies, or constraints that were not in the original text.",
  "Reply with only the rewritten prompt, without explanation, a title, or quotation marks.",
].join(" ");

const PROVIDERS = Object.freeze(
  [
    {
      id: "claude",
      name: "Claude Code",
      executable: "claude",
      arguments: [
        "--print",
        "--output-format",
        "text",
        "--permission-mode",
        "dontAsk",
        "--no-session-persistence",
        "--tools=",
      ],
      environment: [],
      modelFlag: "--model",
      promptTail: 0,
    },
    {
      id: "codex",
      name: "Codex",
      executable: "codex",
      arguments: ["exec", "--ephemeral", "--sandbox", "read-only", "--color", "never"],
      environment: [],
      modelFlag: "--model",
      promptTail: 0,
    },
    {
      id: "opencode",
      name: "OpenCode",
      executable: "opencode",
      arguments: ["run"],
      environment: [["OPENCODE_PERMISSION", "{\"*\":\"deny\"}"]],
      modelFlag: "--model",
      promptTail: 0,
    },
    {
      id: "copilot",
      name: "GitHub Copilot",
      executable: "copilot",
      arguments: ["--silent", "--no-ask-user", "--available-tools=", "-p"],
      environment: [],
      modelFlag: "--model",
      promptTail: 1,
    },
    {
      id: "cursor",
      name: "Cursor",
      executable: "cursor-agent",
      arguments: ["--print", "--output-format", "text"],
      environment: [],
      modelFlag: "--model",
      promptTail: 0,
    },
    {
      id: "droid",
      name: "Droid",
      executable: "droid",
      arguments: ["exec", "--output-format", "text"],
      environment: [],
      modelFlag: "--model",
      promptTail: 0,
    },
    {
      id: "grok",
      name: "Grok",
      executable: "grok",
      arguments: [
        "--no-auto-update",
        "--sandbox",
        "workspace",
        "--permission-mode",
        "dontAsk",
        "--no-subagents",
        "--disable-web-search",
        "--output-format",
        "plain",
        "-p",
      ],
      environment: [],
      modelFlag: "--model",
      promptTail: 1,
    },
    {
      id: "kiro",
      name: "Kiro CLI",
      executable: "kiro-cli",
      arguments: ["chat", "--no-interactive", "--trust-tools="],
      environment: [],
      modelFlag: "--model",
      promptTail: 0,
    },
    {
      id: "pi",
      name: "Pi",
      executable: "pi",
      arguments: ["--print", "--no-session", "--no-tools"],
      environment: [],
      modelFlag: "--model",
      promptTail: 0,
    },
    {
      id: "xal",
      name: "Xal",
      executable: "xal",
      arguments: ["run", "--format", "text"],
      environment: [],
      modelFlag: null,
      promptTail: 0,
    },
    {
      id: "antigravity",
      name: "Antigravity",
      executable: "agy",
      arguments: ["--print", "--output-format", "text", "--mode=plan"],
      environment: [],
      modelFlag: "--model",
      promptTail: 0,
    },
    {
      id: "omp",
      name: "Oh My Pi",
      executable: "omp",
      arguments: ["--print", "--no-session", "--no-tools"],
      environment: [],
      modelFlag: "--model",
      promptTail: 0,
    },
  ].map(provider =>
    Object.freeze({
      ...provider,
      arguments: Object.freeze(provider.arguments.slice()),
      environment: Object.freeze(provider.environment.map(pair => Object.freeze(pair.slice()))),
    }),
  ),
);

function byteLength(text) {
  let bytes = 0;
  for (const character of String(text)) {
    const code = character.codePointAt(0);
    if (code < 0x80) bytes += 1;
    else if (code < 0x800) bytes += 2;
    else if (code < 0x10000) bytes += 3;
    else bytes += 4;
  }
  return bytes;
}

function composePrompt(draft, instructions) {
  const extra = String(instructions || "").trim();
  const rubric = extra ? `${RUBRIC}\n\n${extra}` : RUBRIC;
  return `${rubric}\n\nOriginal prompt:\n${draft}`;
}

function chooseProvider(cli, installedExecutables) {
  const installed = new Set(installedExecutables);
  const requested = String(cli || "").trim();
  if (requested) {
    const provider = PROVIDERS.find(item => item.id === requested);
    if (!provider) return { error: `Unknown CLI "${requested}".` };
    if (!installed.has(provider.executable)) {
      return { error: `${provider.name} CLI is not installed.` };
    }
    return { provider };
  }
  const provider = PROVIDERS.find(item => installed.has(item.executable));
  if (!provider) return { error: "No agent CLI is installed." };
  return { provider, automatic: true };
}

function modelArguments(provider, model) {
  const value = String(model || "").trim();
  if (!value) return { args: [] };
  if (!provider.modelFlag) {
    return {
      error: `${provider.name} has no confirmed model flag. Clear the model to use its default.`,
    };
  }
  return { args: [provider.modelFlag, value] };
}

function buildArgv(provider, prompt, modelArgs) {
  const argv = [provider.executable, ...provider.arguments];
  argv.splice(argv.length - provider.promptTail, 0, ...modelArgs);
  const text = String(prompt);
  argv.push(text.startsWith("-") ? ` ${text}` : text);
  return argv;
}

function buildEnv(provider) {
  const env = { MUXY_PANE_ID: "" };
  for (const [key, value] of provider.environment) env[key] = value;
  return env;
}

function plan(settings, installed, draft) {
  const text = String(draft ?? "");
  if (text.trim() === "") return { status: "empty" };
  const values = settings || {};
  const choice = chooseProvider(values.cli, installed || []);
  if (choice.error) return { status: "error", error: choice.error };
  const model = modelArguments(choice.provider, values.model);
  if (model.error) return { status: "error", error: model.error };
  const prompt = composePrompt(text, values.instructions);
  if (byteLength(prompt) > PROMPT_LIMIT) {
    return { status: "error", error: "The prompt exceeds the 256 KB limit." };
  }
  return {
    status: "ready",
    provider: choice.provider,
    argv: buildArgv(choice.provider, prompt, model.args),
    env: buildEnv(choice.provider),
    draft: text,
  };
}

function resultFailure(provider, result) {
  if (!result || typeof result.stdout !== "string") {
    return `${provider.name} returned an unreadable response.`;
  }
  if (result.timedOut) return `${provider.name} did not respond within five minutes.`;
  if (result.truncated || byteLength(result.stdout) > OUTPUT_LIMIT) {
    return `${provider.name}'s response exceeded the 256 KB output limit.`;
  }
  if (result.exitCode !== 0) {
    const detail = String(result.stderr || "").trim().slice(0, 1000) || `exit ${result.exitCode}`;
    return `${provider.name} failed: ${detail}`;
  }
  if (result.stdout.trim() === "") {
    const detail = String(result.stderr || "").trim().slice(0, 1000);
    return detail
      ? `${provider.name} returned an empty response: ${detail}`
      : `${provider.name} returned an empty response.`;
  }
  return null;
}

function discoveryScript(platform) {
  const lines = PROVIDERS.map(provider =>
    platform === "windows"
      ? `where ${provider.executable} >nul 2>&1 && echo ${provider.executable}`
      : `command -v ${provider.executable} >/dev/null 2>&1 && printf '%s\\n' ${provider.executable}`,
  );
  if (platform === "windows") return `${lines.join(" & ")} & exit /b 0`;
  return `${lines.join("\n")}\ntrue\n`;
}

function parseInstalled(stdout) {
  const known = new Set(PROVIDERS.map(provider => provider.executable));
  const found = [];
  for (const line of String(stdout || "").split(/\r?\n/)) {
    const name = line.trim();
    if (known.has(name) && !found.includes(name)) found.push(name);
  }
  return found;
}

function catalog(installedExecutables) {
  const installed = new Set(installedExecutables);
  return PROVIDERS.map(provider => ({
    id: provider.id,
    name: provider.name,
    executable: provider.executable,
    installed: installed.has(provider.executable),
    modelFlag: provider.modelFlag != null,
  }));
}

function readSettings(all) {
  const values = all || {};
  const text = key => (typeof values[key] === "string" ? values[key] : "");
  return { cli: text("cli"), model: text("model"), instructions: text("instructions") };
}

function message(error) {
  return error && error.message ? error.message : String(error);
}

function explain(error) {
  const text = message(error);
  if (text.includes("user denied consent") || text.includes("nobody answered the prompt")) {
    return "Muxy needs permission to run a program for Prompt Enhancer. Allow it, then try again.";
  }
  return text;
}

function run(io) {
  if (io.state.running) {
    io.notify("A prompt is already being rewritten.");
    return { status: "busy" };
  }
  const draft = String(io.getDraft() ?? "");
  if (draft.trim() === "") {
    io.notify("The composer is empty. Write a prompt, then try again.");
    return { status: "empty" };
  }
  let installed;
  try {
    installed = io.installed();
  } catch (error) {
    const text = explain(error);
    io.notify(text);
    return { status: "error", error: text };
  }
  const ready = plan(io.settings(), installed, draft);
  if (ready.status !== "ready") {
    if (ready.error) io.notify(ready.error);
    return ready;
  }
  io.state.running = true;
  try {
    let result;
    try {
      result = io.exec(ready.argv, { env: ready.env, timeoutMs: TIMEOUT_MS });
    } catch (error) {
      const text = explain(error);
      io.notify(text);
      return { status: "error", error: text };
    }
    const failure = resultFailure(ready.provider, result);
    if (failure) {
      io.notify(failure);
      return { status: "error", error: failure };
    }
    if (String(io.getDraft() ?? "") !== draft) {
      const text = "The draft changed while it was being rewritten, so it was left as you wrote it.";
      io.notify(text);
      return { status: "stale" };
    }
    io.setDraft(result.stdout.trim());
    return { status: "replaced", provider: ready.provider.id };
  } finally {
    io.state.running = false;
  }
}

function discover(muxy) {
  const info = muxy.app.info() || {};
  const result = muxy.exec({ shell: discoveryScript(info.platform), timeoutMs: 10000 });
  if (!result || result.timedOut) throw new Error("Looking for CLIs timed out.");
  if (result.exitCode !== 0) {
    const detail = String(result.stderr || result.stdout || "").trim();
    throw new Error(detail || "Could not look for installed CLIs.");
  }
  return parseInstalled(result.stdout);
}

function wire(muxy) {
  const state = { running: false };
  const notify = body => muxy.notifications.notify({ title: "Prompt Enhancer", body });
  muxy.events.subscribe("command.enhance", () => {
    try {
      const outcome = run({
        state,
        getDraft: () => muxy.composer.getDraft(),
        setDraft: text => muxy.composer.setDraft(text),
        notify,
        settings: () => readSettings(muxy.settings.all()),
        installed: () => discover(muxy),
        exec: (argv, options) => muxy.exec(argv, options),
      });
      if (outcome.status === "replaced") console.log(`enhance replaced the draft with ${outcome.provider}`);
      else if (outcome.error) console.log(`enhance ${outcome.status}: ${outcome.error}`);
      else console.log(`enhance ${outcome.status}`);
    } catch (error) {
      const text = explain(error);
      try {
        notify(text);
      } catch (_) {
        console.error(error);
      }
      console.error(text);
    }
  });
  let detecting = false;
  muxy.events.subscribe("extension.detect", () => {
    if (detecting) return;
    detecting = true;
    try {
      muxy.events.emit("extension.detected", { providers: catalog([]), unchecked: true, pending: true });
      const providers = catalog(discover(muxy));
      const installed = providers.filter(provider => provider.installed).map(provider => provider.executable);
      console.log(installed.length ? `found ${installed.join(", ")}` : "found no CLIs");
      muxy.events.emit("extension.detected", { providers });
    } catch (error) {
      const text = explain(error);
      console.log(`detect failed: ${text}`);
      muxy.events.emit("extension.detected", { error: text, providers: catalog([]), unchecked: true });
    } finally {
      detecting = false;
    }
  });
}

const api = {
  PROVIDERS,
  RUBRIC,
  PROMPT_LIMIT,
  OUTPUT_LIMIT,
  TIMEOUT_MS,
  byteLength,
  composePrompt,
  chooseProvider,
  modelArguments,
  buildArgv,
  buildEnv,
  plan,
  resultFailure,
  discoveryScript,
  parseInstalled,
  catalog,
  readSettings,
  explain,
  run,
};

if (typeof module !== "undefined" && module.exports) module.exports = api;
if (typeof muxy !== "undefined") wire(muxy);
