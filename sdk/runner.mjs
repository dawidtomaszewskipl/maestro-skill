// maestro-sdk runner — one Claude worker turn through the Claude Agent SDK, billed to an API key
// (docs/workers.md, "Claude through the Agent SDK"). Called by bin/maestro-sdk; see its --help.
//
// Every SDK message is written to stdout as one JSON line — the same events as `claude -p
// --output-format stream-json` (system/init first, result last), so maestro-run, maestro-wait,
// maestro-validate --envelope claude and maestro-ledger --cli claude-sdk read it unchanged.
// The key is read from a file (mode 600) and handed to the SDK's child process only; it never
// appears in argv, stdout or .maestro/.
import { readFileSync, statSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

const ROLE_MODES = new Set(["dontAsk", "acceptEdits", "plan"]);   // never bypassPermissions or auto
const EFFORTS = new Set(["low", "medium", "high", "xhigh", "max"]);
// Variables that would change where the child authenticates or what it loads: dropped, then
// ANTHROPIC_API_KEY is set from the key file (it outranks every login in -p mode).
const DROP = /^(ANTHROPIC_|CLAUDE_CODE_OAUTH_TOKEN$|CLAUDE_CODE_USE_|CLAUDE_CODE_PLUGIN|CLAUDECODE$)/;

function die(msg, code = 2) {
  process.stderr.write(`maestro-sdk: ${msg}\n`);
  process.exit(code);
}

function parse(argv) {
  const o = { tools: null, allowedTools: [], dryRun: false };
  const val = (i) => {
    if (i + 1 >= argv.length) die(`${argv[i]} needs a value`);
    return argv[i + 1];
  };
  const list = (s) => s.split(",").map((t) => t.trim()).filter(Boolean);
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    switch (a) {
      case "--model": o.model = val(i); i++; break;
      case "--effort": o.effort = val(i); i++; break;
      case "--tools": o.tools = list(val(i)); i++; break;
      case "--allowed-tools": o.allowedTools = list(val(i)); i++; break;
      case "--permission-mode": o.permissionMode = val(i); i++; break;
      case "--json-schema": o.schemaFile = val(i); i++; break;
      case "--resume": o.resume = val(i); i++; break;
      case "--max-budget-usd": o.budget = val(i); i++; break;
      case "--cwd": o.cwd = val(i); i++; break;
      case "--prompt-file": o.promptFile = val(i); i++; break;
      case "--key-file": o.keyFile = val(i); i++; break;
      case "--dry-run": o.dryRun = true; break;
      default: die(`unknown option ${a}`);
    }
  }
  if (!o.model) die("--model is required (pin the full id after the probe)");
  if (!o.effort || !EFFORTS.has(o.effort)) die("--effort is required: low|medium|high|xhigh|max");
  if (o.tools === null) die('--tools is required (the exclusive tool set; "" for none)');
  if (!o.permissionMode || !ROLE_MODES.has(o.permissionMode))
    die("--permission-mode is required: dontAsk|acceptEdits|plan");
  if (o.budget === undefined) die("--max-budget-usd is required (policy api.max_usd_per_run minus what the run spent)");
  o.budget = Number(o.budget);
  if (!Number.isFinite(o.budget) || o.budget < 0) die("--max-budget-usd must be a number ≥ 0");
  if (!o.promptFile) die("--prompt-file is required (briefs are files)");
  o.keyFile ??= process.env.MAESTRO_API_KEY_FILE || join(homedir(), ".config", "maestro", "anthropic-api-key");
  return o;
}

function readKey(file) {
  let st;
  try { st = statSync(file); } catch { die(`no API key file at ${file} (README, "API credit")`, 3); }
  if (!st.isFile()) die(`${file} is not a regular file`, 3);
  if ((st.mode & 0o077) !== 0) die(`${file} is readable by others (mode ${(st.mode & 0o777).toString(8)}); chmod 600 it`, 3);
  if (typeof process.getuid === "function" && st.uid !== process.getuid()) die(`${file} is not owned by you`, 3);
  const key = readFileSync(file, "utf8").trim();
  if (!key) die(`${file} is empty`, 3);
  return key;
}

const out = (m) => process.stdout.write(JSON.stringify(m) + "\n");

// --resolve <slot>: the newest model of a Claude line this key can use, from the Models API (no
// model turn, no cost). The SDK's bundled CLI resolves aliases from its own table, which lags
// (measured: `haiku` → claude-haiku-4-5-20251001 on 0.3.286), so the api transport takes full ids only.
const argv = process.argv.slice(2);
if (argv[0] === "--resolve") {
  const slot = argv[1];
  if (!["opus", "fable", "sonnet", "haiku"].includes(slot ?? "")) die("--resolve opus|fable|sonnet|haiku");
  const ki = argv.indexOf("--key-file");
  const key = readKey(ki > 0 ? argv[ki + 1] : process.env.MAESTRO_API_KEY_FILE || join(homedir(), ".config", "maestro", "anthropic-api-key"));
  const ids = [];
  let after = null;
  for (;;) {
    const url = new URL("https://api.anthropic.com/v1/models");
    url.searchParams.set("limit", "1000");
    if (after) url.searchParams.set("after_id", after);
    let r;
    try {
      r = await fetch(url, { headers: { "x-api-key": key, "anthropic-version": "2023-06-01" } });
    } catch (e) { die(`Models API unreachable: ${e?.message ?? e}`, 4); }
    if (!r.ok) {
      const body = await r.text();
      if (/not scoped to a workspace/.test(body))
        die("the key is not scoped to a workspace: create the key inside a Console workspace (Settings → Workspaces), which also gives it a spend limit", 3);
      die(`Models API: HTTP ${r.status} ${body.slice(0, 200)}`, r.status === 401 || r.status === 403 ? 3 : 4);
    }
    const page = await r.json();
    ids.push(...page.data.map((m) => ({ id: m.id, created_at: m.created_at })));
    if (!page.has_more) break;
    after = page.last_id;
  }
  const line = ids.filter((m) => m.id.startsWith(`claude-${slot}-`))
    .sort((a, b) => (a.created_at < b.created_at ? 1 : a.created_at > b.created_at ? -1 : 0));
  out({ slot, id: line[0]?.id ?? null, candidates: line.map((m) => m.id) });
  process.exit(line.length ? 0 : 1);
}

const o = parse(argv);
if (!/^claude-[a-z]+-[0-9]/.test(o.model)) die(`--model must be a full id (claude-<line>-<version>), not ${o.model}: resolve it with --resolve <slot>`);
const key = readKey(o.keyFile);
const prompt = readFileSync(o.promptFile, "utf8");
const schema = o.schemaFile ? JSON.parse(readFileSync(o.schemaFile, "utf8")) : undefined;

const env = {};
const dropped = [];
for (const [k, v] of Object.entries(process.env)) {
  if (DROP.test(k)) dropped.push(k); else env[k] = v;
}
env.ANTHROPIC_API_KEY = key;
env.CLAUDE_AGENT_SDK_CLIENT_APP = "maestro/1.4.0";

const options = {
  model: o.model,
  effort: o.effort,
  tools: o.tools,
  allowedTools: o.allowedTools,
  permissionMode: o.permissionMode,
  settingSources: [],          // no user, project or local settings: no hooks, no CLAUDE.md
  mcpServers: {},
  strictMcpConfig: true,       // no MCP server from anywhere
  maxBudgetUsd: o.budget,
  cwd: o.cwd ?? process.cwd(),
  env,
  stderr: (d) => process.stderr.write(d),
};
if (o.resume) options.resume = o.resume;
if (schema) options.outputFormat = { type: "json_schema", schema };

if (o.dryRun) {
  const { env: _e, stderr: _s, ...shown } = options;
  out({ dry_run: true, options: { ...shown, outputFormat: schema ? "json_schema" : null },
        key_file: o.keyFile, env_dropped: dropped.sort(), env_set: ["ANTHROPIC_API_KEY", "CLAUDE_AGENT_SDK_CLIENT_APP"],
        prompt_bytes: Buffer.byteLength(prompt) });
  process.exit(0);
}

// The run's budget is spent: no model turn. Same shape as the SDK's own budget stop, so the
// director classifies both the same way (quota on the api transport).
if (o.budget === 0) {
  out({ type: "result", subtype: "error_max_budget_usd", is_error: true, total_cost_usd: 0,
        result: "maestro: api budget for this run is spent (policy api.max_usd_per_run)" });
  process.exit(1);
}

const { query } = await import("@anthropic-ai/claude-agent-sdk");
const abort = new AbortController();
options.abortController = abort;
let result = null;
try {
  for await (const m of query({ prompt, options })) {
    out(m);
    // Fail closed: a worker on this transport must bill the key, never a login.
    if (m.type === "system" && m.subtype === "init" && m.apiKeySource !== "ANTHROPIC_API_KEY") {
      process.stderr.write(`maestro-sdk: init.apiKeySource is ${JSON.stringify(m.apiKeySource)}, not ANTHROPIC_API_KEY — stopped\n`);
      abort.abort();
      process.exit(3);
    }
    if (m.type === "result") result = m;
  }
} catch (e) {
  // A one-shot query throws after yielding an error result; that result is already on stdout.
  if (!result) process.stderr.write(`maestro-sdk: ${e?.message ?? e}\n`);
}
process.exit(result && result.subtype === "success" && result.is_error === false ? 0 : 1);
