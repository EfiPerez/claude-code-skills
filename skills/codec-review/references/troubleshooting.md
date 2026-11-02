# Codex troubleshooting — four failures that look alike

Read this when a Codex call fails **before any review or build work starts** and Step 0's checks (`codex --version`, `codex login status`) already pass. These failures all surface as an identical hard error from Codex's stderr; the section titles below tell them apart. Mechanics of the loop itself are in [codec-loop.md](codec-loop.md).

Commands are shown for the PowerShell tool (Windows) and the Bash tool (macOS/Linux). Sections marked **Windows-only** do not apply elsewhere. The macOS/Linux commands were not run on macOS.

## 1. Windows-only: `[windows] sandbox = "unelevated"` — keep it

Root-caused and verified 2026-09-15. Do **not** "fix" a native-executable failure by switching to `elevated`, and do **not** reach for `danger-full-access`.

Symptom: a command the model runs inside Codex's sandbox fails with Windows error 5 (`Access is denied`) on a user-installed program such as `python.exe`, while the model can read that same program's files.

Cause: the `elevated` implementation runs shell commands as a dedicated sandbox account (`CodexSandboxOffline`), while the Codex broker and the model's file access run as the signed-in user. A user-level install (for example Python) often grants access only to `SYSTEM`, `Administrators` and the user — unlike machine-wide Node or Docker binaries, which grant `BUILTIN\Users:(RX)`. So the model can inspect `python.exe`, but the sandbox account's `CreateProcessAsUserW` fails. This is a Windows account/ACL mismatch — not quoting, and not a Codex executable allowlist.

Fix, in `~/.codex/config.toml` (create the file if it does not exist):

```toml
[windows]
sandbox = "unelevated"
```

`unelevated` uses a restricted token derived from the signed-in user, which keeps access to user-installed interpreters while still enforcing the requested read-only / workspace-write filesystem boundaries. Measured before and after through the Codex plugin's companion script: the exact absolute `python.exe --version` command failed under `elevated` and returned `Python 3.11.9` under `unelevated`; read-only sandbox probes also passed for Node `v24.14.1`, npm `11.11.0`, and Docker `29.4.3`.

If a tool is absent from Codex's PATH, give its absolute executable or shim path. The earlier failure was not quoting.

This setting only changes Codex's sandbox implementation. It does not alter Claude Code's own permission rules.

## 2. The model slug: newest Sol, never Astra

`codec-review` and `codec-build` pick the model from the top of the **Sol family** in `~/.codex/models_cache.json`: entries with `visibility: "list"` whose slug matches `gpt-<N>-sol` or `gpt-<N.M>-sol`, newest version wins (`6.10` beats `6.9`). A new Sol release is picked up with no edit. If the file is missing or unreadable, no `-m` is passed and Codex uses its own default.

Why the allowlist is load-bearing: Codex writes and overwrites `models_cache.json` itself (editing it is pointless), and a Codex update can float an unrunnable model to the top. On 2026-09-15 `gpt-6-astra` surfaced as top priority, a review round launched with `-m gpt-6-astra`, and every call died on `The 'gpt-6-astra' model requires a newer version of Codex`. The same error also arrives when `model = "gpt-6-astra"` is set in `config.toml` by a Codex desktop update. Do not widen the resolver to "anything gpt-6" or to Codex's own priority order; the loop deliberately takes Sol only.

PowerShell — which model would be picked right now:

```powershell
$mc = Join-Path $env:USERPROFILE '.codex\models_cache.json'
((Get-Content -LiteralPath $mc -Raw -Encoding utf8 | ConvertFrom-Json).models |
  Where-Object { $_.visibility -eq 'list' -and $_.slug -match '^gpt-\d+(\.\d+)?-sol$' } |
  Sort-Object { [version](($_.slug -split '-')[1] + '.0') } -Descending |
  Select-Object -First 1).slug
```

bash — the same, using `node` (always present, because the Codex CLI installs through npm):

```bash
node -e '
  const fs = require("fs"), os = require("os"), path = require("path");
  const models = JSON.parse(fs.readFileSync(path.join(os.homedir(), ".codex", "models_cache.json"), "utf8").replace(/^\uFEFF/, "")).models || [];
  const rx = /^gpt-(\d+(?:\.\d+)?)-sol$/;
  const sol = models.filter(m => m.visibility === "list" && rx.test(m.slug))
    .map(m => ({ slug: m.slug, v: m.slug.match(rx)[1].split(".").map(Number) }));
  sol.sort((a, b) => { for (let i = 0; i < Math.max(a.v.length, b.v.length); i++) { const d = (b.v[i] || 0) - (a.v[i] || 0); if (d) return d; } return 0; });
  console.log(sol.length ? sol[0].slug : "(none - Codex default will be used)");
'
```

## 3. `400 The 'gpt-…-sol' model is not supported when using Codex with a ChatGPT account`

This reads like an account-plan restriction but is really an **old-client** rejection. Seen 2026-09-23 on Codex CLI 0.150.1 with `gpt-6-sol`: the same account worked from the Codex desktop app's newer binary and after `npm i -g @openai/codex@0.156.1`. Likewise `gpt-6.1-sol` was rejected on 0.156.1 and accepted on 0.160.1.

Fix: upgrade the CLI, then retry.

```
npm install -g @openai/codex@latest
codex --version
```

Because the resolver always takes the newest Sol, a brand-new Sol that fails with this error means the CLI is behind — upgrade it rather than narrowing the resolver. If you have more than one Codex binary (the npm install on PATH and the desktop app's), check that `codex --version` reports the one you just upgraded.

## 4. Upgraded the CLI, but the old one still runs: a stale app-server broker

Only relevant if you also use the Codex plugin for Claude Code (`/codex:*` commands). The plugin's `app-server-broker.mjs` process outlives each call and keeps the `codex app-server` child it spawned **before** the upgrade, so the plugin keeps running the old CLI. The loop in these skills calls `codex exec` directly and is not affected.

Kill that broker by PID. Never kill by process name (`node.exe`, `pkill node`) — that stops every Node program on the machine. Codex desktop's own `codex app-server` is a separate process; leave it.

PowerShell (Windows):

```powershell
Get-CimInstance Win32_Process |
  Where-Object { $_.CommandLine -like '*app-server-broker*' } |
  Select-Object ProcessId, CommandLine
# then, for the PID you identified:
Stop-Process -Id <pid>
```

bash (macOS/Linux):

```bash
ps -axww -o pid=,command= | grep -F 'app-server-broker' | grep -v -F 'grep -F'
# then, for the PID you identified:
kill <pid>
```

After killing it, run the plugin command again; it starts a fresh broker with the upgraded CLI.
