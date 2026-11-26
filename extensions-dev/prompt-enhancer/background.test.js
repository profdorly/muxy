const assert = require("node:assert/strict");
const test = require("node:test");
const api = require("./background.js");

const GOLDEN = [
  [
    "claude",
    "claude",
    ["--print", "--output-format", "text", "--permission-mode", "dontAsk", "--no-session-persistence", "--tools="],
    "--model",
    0,
    [],
  ],
  [
    "codex",
    "codex",
    ["exec", "--ephemeral", "--sandbox", "read-only", "--color", "never"],
    "--model",
    0,
    [],
  ],
  ["opencode", "opencode", ["run"], "--model", 0, [["OPENCODE_PERMISSION", "{\"*\":\"deny\"}"]]],
  [
    "copilot",
    "copilot",
    ["--silent", "--no-ask-user", "--available-tools=", "-p"],
    "--model",
    1,
    [],
  ],
  ["cursor", "cursor-agent", ["--print", "--output-format", "text"], "--model", 0, []],
  ["droid", "droid", ["exec", "--output-format", "text"], "--model", 0, []],
  [
    "grok",
    "grok",
    [
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
    "--model",
    1,
    [],
  ],
  ["kiro", "kiro-cli", ["chat", "--no-interactive", "--trust-tools="], "--model", 0, []],
  ["pi", "pi", ["--print", "--no-session", "--no-tools"], "--model", 0, []],
  ["xal", "xal", ["run", "--format", "text"], null, 0, []],
  ["antigravity", "agy", ["--print", "--output-format", "text", "--mode=plan"], "--model", 0, []],
  ["omp", "omp", ["--print", "--no-session", "--no-tools"], "--model", 0, []],
];

function provider(id) {
  return api.PROVIDERS.find(item => item.id === id);
}

function ok(stdout) {
  return { stdout, stderr: "", exitCode: 0, timedOut: false, truncated: false };
}

function harness(overrides = {}) {
  const state = overrides.state || { running: false };
  const notes = [];
  const calls = [];
  let draft = Object.prototype.hasOwnProperty.call(overrides, "draft") ? overrides.draft : "fix the login bug";
  const io = {
    state,
    getDraft: () => draft,
    setDraft: text => {
      draft = text;
    },
    notify: body => notes.push(body),
    settings: () => overrides.settings || { cli: "", model: "", instructions: "" },
    installed: () => overrides.installed || ["claude"],
    exec: (argv, options) => {
      calls.push({ argv, options });
      if (overrides.exec) return overrides.exec(argv, options, () => draft, value => {
        draft = value;
      });
      return ok("Rewritten prompt.");
    },
  };
  return {
    io,
    notes,
    calls,
    state,
    read: () => draft,
  };
}

test("providers stay in the automatic install order", () => {
  assert.deepEqual(
    api.PROVIDERS.map(item => item.id),
    ["claude", "codex", "opencode", "copilot", "cursor", "droid", "grok", "kiro", "pi", "xal", "antigravity", "omp"],
  );
  assert.deepEqual(
    api.PROVIDERS.map(item => item.executable),
    ["claude", "codex", "opencode", "copilot", "cursor-agent", "droid", "grok", "kiro-cli", "pi", "xal", "agy", "omp"],
  );
});

test("one-shot argv copies generate and adds a confirmed model flag before the prompt", () => {
  assert.equal(GOLDEN.length, api.PROVIDERS.length);
  for (const [id, executable, args, modelFlag, promptTail, environment] of GOLDEN) {
    const item = provider(id);
    assert.equal(item.executable, executable);
    assert.deepEqual([...item.arguments], args);
    assert.equal(item.modelFlag, modelFlag);
    assert.equal(item.promptTail, promptTail);
    assert.deepEqual(item.environment.map(pair => [...pair]), environment);
    const prompt = "fix the login bug";
    assert.deepEqual(api.buildArgv(item, prompt, []), [executable, ...args, prompt]);
    const planned = api.plan({ cli: id, model: "", instructions: "" }, [executable], prompt);
    assert.equal(planned.status, "ready");
    assert.deepEqual(planned.argv.slice(0, -1), [executable, ...args]);
    assert.equal(planned.argv.at(-1).endsWith(`Original prompt:\n${prompt}`), true);
    assert.deepEqual(planned.env, api.buildEnv(item));
  }
});

test("a model flag is inserted without taking the prompt away from -p", () => {
  const copilot = api.buildArgv(provider("copilot"), "hello", ["--model", "gpt-5.4"]);
  assert.deepEqual(copilot.slice(-4), ["--model", "gpt-5.4", "-p", "hello"]);
  const grok = api.buildArgv(provider("grok"), "hello", ["--model", "grok-3"]);
  assert.deepEqual(grok.slice(-4), ["--model", "grok-3", "-p", "hello"]);
  const codex = api.buildArgv(provider("codex"), "hello", ["--model", "gpt-5.4"]);
  assert.ok(codex.indexOf("exec") < codex.indexOf("--model"));
  assert.deepEqual(codex.slice(-3), ["--model", "gpt-5.4", "hello"]);
});

test("a prompt that starts with a dash is passed as text", () => {
  assert.equal(api.buildArgv(provider("claude"), "-n", []).at(-1), " -n");
});

test("xal keeps its default unless a model is set", () => {
  const open = api.plan({ cli: "xal", model: "   ", instructions: "" }, ["xal"], "hello");
  assert.equal(open.status, "ready");
  assert.deepEqual(open.argv.slice(0, -1), ["xal", "run", "--format", "text"]);
  const blocked = api.plan({ cli: "xal", model: "big", instructions: "" }, ["xal"], "hello");
  assert.equal(blocked.status, "error");
  assert.equal(blocked.error, "Xal has no confirmed model flag. Clear the model to use its default.");
});

test("automatic uses the first installed CLI and an explicit missing CLI does not fall through", () => {
  assert.equal(api.chooseProvider("", ["omp", "codex"]).provider.id, "codex");
  assert.equal(api.chooseProvider("   ", ["droid"]).provider.id, "droid");
  assert.equal(api.chooseProvider("omp", ["codex", "omp"]).provider.id, "omp");
  assert.equal(api.chooseProvider("claude", ["codex"]).error, "Claude Code CLI is not installed.");
  assert.equal(api.chooseProvider("nope", ["claude"]).error, 'Unknown CLI "nope".');
  assert.equal(api.chooseProvider("", []).error, "No agent CLI is installed.");
});

test("extra instructions are appended to the rubric, ahead of the original prompt", () => {
  const prompt = api.composePrompt("ship it", " Keep it short. ");
  const extra = prompt.indexOf("Keep it short.");
  const original = prompt.indexOf("Original prompt:\nship it");
  assert.ok(prompt.indexOf("objective") > 0);
  assert.ok(prompt.indexOf("context") > 0);
  assert.ok(prompt.indexOf("constraints") > 0);
  assert.ok(prompt.indexOf("format") > 0);
  assert.ok(prompt.indexOf("Do not invent") > 0);
  assert.ok(prompt.indexOf("only the rewritten prompt") > 0);
  assert.ok(prompt.indexOf("Do not invent") < extra);
  assert.ok(extra < original);
  assert.equal(api.composePrompt("ship it", "  "), `${api.RUBRIC}\n\nOriginal prompt:\nship it`);
});

test("an empty draft stops before a CLI is launched", () => {
  for (const draft of ["", "   \n"]) {
    let looked = false;
    const run = harness({
      draft,
      installed: () => {
        looked = true;
        return ["claude"];
      },
    });
    run.io.installed = () => {
      looked = true;
      return ["claude"];
    };
    const outcome = api.run(run.io);
    assert.equal(outcome.status, "empty");
    assert.equal(looked, false);
    assert.equal(run.calls.length, 0);
    assert.deepEqual(run.notes, ["The composer is empty. Write a prompt, then try again."]);
  }
});

test("a changed draft is not replaced", () => {
  const run = harness({
    exec: (_argv, _options, _read, write) => {
      write("hello!");
      return ok("better");
    },
  });
  const outcome = api.run(run.io);
  assert.equal(outcome.status, "stale");
  assert.equal(run.read(), "hello!");
  assert.equal(run.notes[0], "The draft changed while it was being rewritten, so it was left as you wrote it.");
});

test("a successful reply replaces only the draft text", () => {
  const run = harness({
    exec: () => ok("  better\n"),
  });
  const outcome = api.run(run.io);
  assert.equal(outcome.status, "replaced");
  assert.equal(outcome.provider, "claude");
  assert.equal(run.read(), "better");
  assert.equal(run.calls[0].options.timeoutMs, api.TIMEOUT_MS);
  assert.equal(run.calls[0].options.env.MUXY_PANE_ID, "");
  assert.equal(run.notes.length, 0);
});

test("a failed, empty, timed out, or oversized reply does not replace the draft", () => {
  const cases = [
    [{ stdout: "hidden", stderr: "boom", exitCode: 2, timedOut: false, truncated: false }, "Claude Code failed: boom"],
    [{ stdout: "\n  ", stderr: "silent", exitCode: 0, timedOut: false, truncated: false }, "Claude Code returned an empty response: silent"],
    [{ stdout: "", stderr: "", exitCode: 0, timedOut: false, truncated: false }, "Claude Code returned an empty response."],
    [{ stdout: "", stderr: "", exitCode: 0, timedOut: true, truncated: false }, "Claude Code did not respond within five minutes."],
    [{ stdout: "too much", stderr: "", exitCode: 0, timedOut: false, truncated: true }, "Claude Code's response exceeded the 256 KB output limit."],
    [{ stdout: "x".repeat(api.OUTPUT_LIMIT + 1), stderr: "", exitCode: 0, timedOut: false, truncated: false }, "Claude Code's response exceeded the 256 KB output limit."],
  ];
  for (const [result, expected] of cases) {
    const run = harness({ exec: () => result });
    const outcome = api.run(run.io);
    assert.equal(outcome.status, "error");
    assert.equal(outcome.error, expected);
    assert.equal(run.read(), "fix the login bug");
  }
});

test("a prompt over 256 KB is refused before exec", () => {
  const run = harness({ draft: "x".repeat(api.PROMPT_LIMIT) });
  const outcome = api.run(run.io);
  assert.equal(outcome.status, "error");
  assert.equal(outcome.error, "The prompt exceeds the 256 KB limit.");
  assert.equal(run.calls.length, 0);
  assert.equal(run.read(), "x".repeat(api.PROMPT_LIMIT));
});

test("a second request waits until the first CLI returns", () => {
  const state = { running: false };
  let calls = 0;
  const io = {
    state,
    getDraft: () => "hello",
    setDraft: () => {},
    notify: () => {},
    settings: () => ({ cli: "claude", model: "", instructions: "" }),
    installed: () => ["claude"],
    exec: () => {
      calls += 1;
      const nested = api.run(io);
      assert.equal(nested.status, "busy");
      return ok("better");
    },
  };
  const outcome = api.run(io);
  assert.equal(calls, 1);
  assert.equal(outcome.status, "replaced");
  assert.equal(state.running, false);
});

test("an exec failure clears the in-flight guard", () => {
  const run = harness({
    exec: () => {
      throw new Error("denied");
    },
  });
  const outcome = api.run(run.io);
  assert.equal(outcome.error, "denied");
  assert.equal(run.state.running, false);
  const again = api.run(run.io);
  assert.equal(again.error, "denied");
  assert.equal(run.calls.length, 2);
});

test("discovery reports installed executables in the order the shell prints them", () => {
  const script = api.discoveryScript("macos");
  let cursor = -1;
  for (const provider of api.PROVIDERS) {
    const at = script.indexOf(provider.executable, cursor + 1);
    assert.ok(at > cursor);
    cursor = at;
  }
  assert.equal(script.endsWith("true\n"), true);
  const windows = api.discoveryScript("windows");
  assert.equal(windows.includes("where claude"), true);
  assert.equal(windows.endsWith("exit /b 0"), true);
  assert.deepEqual(api.parseInstalled("claude\n/usr/bin/claude\ncodex\nclaude\n"), ["claude", "codex"]);
  const rows = api.catalog(["agy", "claude"]);
  assert.equal(rows[0].installed, true);
  assert.equal(rows.find(row => row.id === "codex").installed, false);
  assert.equal(rows.find(row => row.id === "antigravity").installed, true);
  assert.equal(rows.find(row => row.id === "xal").modelFlag, false);
  assert.equal(rows.find(row => row.id === "claude").modelFlag, true);
});

test("a denied program prompt tells the person to allow it", () => {
  assert.equal(
    api.explain(new Error("exec: user denied consent for exec")),
    "Muxy needs permission to run a program for Prompt Enhancer. Allow it, then try again.",
  );
  assert.equal(api.explain(new Error("codex: boom")), "codex: boom");
});

test("settings that are missing come back blank", () => {
  assert.deepEqual(api.readSettings(null), { cli: "", model: "", instructions: "" });
  assert.deepEqual(api.readSettings({ cli: "pi", model: 1, instructions: null }), {
    cli: "pi",
    model: "",
    instructions: "",
  });
});
