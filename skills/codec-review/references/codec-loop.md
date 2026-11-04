# codec-loop — shared mechanics for `codec-review` and `codec-build`

Both skills drive OpenAI Codex in a bounded, logged, cross-model loop, from the PowerShell tool (Windows) or the Bash tool (macOS / Linux / Git Bash). This file is **normative**: where it disagrees with anything else, this wins.

Adapted from `chaseai-yt/claudex-loop` (its adversarial prompting, bounded iteration, and round reporting only; MIT — see the repository's `NOTICE`). Every claim is either verified on the author's machine (Windows) on 2026-09-01 or marked as an accepted risk. Several of Chase's details do not hold there.

> **Rewritten in one pass twice** — after round 3 and again after round 6 of its own adversarial review. Both rewrites settled multiple findings and regressed nothing; every *patch* round in between introduced new contradictions. **If you need to change more than one section, rewrite the file rather than patching it.** That is the most reliable lesson from six rounds.

**Which shell.** Every command is shown as a PowerShell block (Windows, PowerShell tool) and a bash block (macOS or Linux, Bash tool; Git Bash on Windows also works). Use one or the other, never both in one call; re-assign variables at the top of each call, because neither variables nor the working directory survive between tool calls. The bash blocks rely only on `bash`, POSIX tools that ship with macOS, `git` and `node`. They were tested under Git Bash on Windows; **macOS itself is untested**, and the process-table block in §6 could not be run under Git Bash. Advice marked **Windows-only** does not apply elsewhere.

## Contents

The skills cite sections by number (for example §5d, §8), and most of them sit well past the top of the file. Jump to the section instead of reading from the start.

- §1 The review/build asymmetry — read this first
- §2 Verified environment
- §3 Accepted risks (3a Codex's reads cannot be confined, 3b Elevated bypass)
- §4 Identifiers (and non-git snapshots)
- §5 Invoking Codex (5a data guard, 5b prepared-phase setup, 5c review rounds, 5d build rounds, 5e rules both templates depend on, 5f capturing `thread_id`)
- §6 State, recovery, and proving quiescence
- §7 Reading the result (verdict parse ladder, approval as a validated state)
- §8 Build completion is a different test
- §9 The run lock
- §10 Arbitration record
- §11 Failure playbook (output-schema constraints)

---

## 1. The review/build asymmetry — read this first

The two skills have **opposite** relationships to the project tree. A rule that is right for one is a bug in the other, so nothing below is "shared" unless it says so.

| | `codec-review` | `codec-build` |
|---|---|---|
| Codex's job | read and critique | **write working code** |
| Sandbox | `read-only` | `workspace-write` |
| `-C` and cwd (`cwd_root`) | `staging_dir` | `project_root` |
| Staging | mandatory | **does not apply** |
| `--output-schema` | yes — verdict object | **no** — diff + prose report |
| Completion test | §7 approval invariants | §8 build completion |
| Primary control | allowlist (scope hygiene, not a boundary — §3a) | clean-tree/snapshot gate, write sandbox, diff read, commit gate |

**Staging is a read-scope control and cannot be used for building.** A build launched with `-C` pointing at `.scope-<hex>` writes into the staged copy and leaves the project untouched — a build that reports success and changes nothing. There is deliberately no staging-diff-back-to-worktree step: applying a machine-generated patch into a tree Claude has not diffed would defeat the commit gate.

`codec-build` therefore runs against the real worktree and accepts wider read exposure than a review does. That is a conscious trade, justified by the write sandbox plus rollback, and it is why build has a hard clean-tree/snapshot gate that review does not need.

Sections are marked **[review]**, **[build]**, or **[both]**.

---

## 2. Verified environment — `codex-cli` 0.150.1 to 0.160.1

The rows below were first verified on 0.150.1; only the version and model rows were re-checked on later versions (0.156.1 on 2026-10-04, 0.160.1 on 2026-10-29).

| Fact | Consequence |
|---|---|
| `codex exec` has **no `--effort` flag** | Effort goes via `-c model_reasoning_effort="high"`. Verified accepted. |
| `codex exec resume` accepts **neither `-s` nor `-C`** | Force the sandbox with `-c sandbox_mode=...`; `Set-Location` / `cd` first. |
| `resume` filters recorded sessions **by cwd** | Round 1's cwd and every resume's cwd must both equal `cwd_root` — which differs per skill (§1). |
| `--skip-git-repo-check` on both | Required for staging (not a repo) and for non-git projects. |
| ChatGPT-account auth (`auth_mode = chatgpt`); the Codex default model changes over time | `-m gpt-6-sol` was accepted on 0.156.1; `-m gpt-6.1-sol` needs 0.160.1 (0.156.1 gave the ChatGPT-account 400, 2026-10-06), and `gpt-6-sol` was rejected on 0.150.1 — see `troubleshooting.md`. Chase's "never pin on ChatGPT auth" warning concerns `-codex` variants, absent from the author's account. |
| `--yolo` works but is a **hidden, undocumented** alias | Never use it. |
| A shell redirect `> "$file"` creates the file **at redirection time** (PowerShell and bash alike) | An empty `.jsonl` proves nothing about whether Codex ran (§6). |
| The shell tools **reset cwd between calls** | `Set-Location` / `cd` every round, never once. |
| On Windows the PowerShell tool is the better driver | No extra permission rule beyond `PowerShell(*)`, and the npm shim gives stdin EOF when un-piped. The bash blocks redirect stdin from `/dev/null` as the equivalent precaution. |

**Timing (measured):** 49–213 s per round at effort `high`, scaling with input size. Real codebases are slower — hence backgrounding.

---

## 3. Accepted risks

### 3a. Codex's reads cannot be confined [both] — design decision

**Measured.** Launched `-s read-only -C <staging>` and asked to read two files outside that directory, Codex spawned PowerShell and read **both**, including a global instruction file in the user's home config directory, in 689 ms:

```
exec powershell -NoProfile -Command "Get-Content -LiteralPath '<outside-staging>\readprobe.md' -Raw
     Get-Content -LiteralPath '<home>\.claude\CLAUDE.md' -Raw"   succeeded in 689ms
```

Retried with `-c windows.sandbox="unelevated"` — identical. `[windows] sandbox` accepts only `elevated`/`unelevated`; the restricted-token sandbox with `--sandbox-state-readable-root` exists **only** on the `codex sandbox` subcommand, not in `codex exec`.

**`read-only` sandboxes WRITES ONLY. No flag limits reads.** Codex can read `.credentials.json`, a service-account key, a database snapshot, or any personal data regardless of what a brief says.

The author accepted this risk rather than adding a low-privilege runner account. Anyone who cannot accept it should run the loop under such an account, or not point it at sensitive projects.

- **Never write that anything is "enforced", "prevented", "impossible", or "globally unique"** in this file unless it is provably so. The allowlist and staging reduce accidental discovery and keep the default working set small. That is all.
- Evidence of the limit is visible every round: the brief is passed as an absolute path *outside* staging and Codex reads it every time.

**Design decision — Codex may see whatever Claude can see.** An earlier version of this design made a confirm-on-sensitive-hits prompt the real control and forbade silencing it. That was withdrawn: a gate answered on every run gets answered by habit, and a Codex run can read credentials or personal data either way. Consequences:

- **No data-guard scan and no sensitive-hit confirmation.** Do not re-add either, and do not raise the read-exposure question per run. The repository README's Privacy section is where the user is told.
- **No "this pass must stay on Claude" carve-out** for secret or personal-data work. Any pass may run on Codex.
- Staging survives, but its remaining jobs are (a) giving the loop a working copy so the original is never edited mid-run and (b) keeping the working set small. It is **not** a data control.
- The §5a patterns stay as written — including `*.csv` and `*.xlsx` — as scope and cost hygiene. They are the default working set, not a boundary.

### 3b. Elevated bypass [build] — design decision

`codec-build` defaults to `workspace-write`. If Codex reports it was blocked, the skill may ask the user once and, on an explicit yes, re-run with `--dangerously-bypass-approvals-and-sandbox`.

Codex's review argued for removing this, soundly: on Windows with `[windows] sandbox = "elevated"` a bypass run can write **anywhere the user can**, and those writes appear in no project diff and are covered by neither `git restore` nor the snapshot — so the commit gate can show a clean, complete-looking change set while something outside the tree was already modified.

The hatch was kept. Non-negotiable: never the default; explicit per-run yes; explicit long flag only; and **the commit-gate summary must disclose that a bypass round ran**, so the diff is never presented as a complete account.

---

## 4. Identifiers [both]

| Form | Example | Used for |
|---|---|---|
| `run_id` | `2026-09-01 14-32-07 add-dark-mode a3f9` | the run-log filename **only** — always quote it / use `-LiteralPath`, never pass it as a native arg |
| `safe_id` | `20260901-143207-add-dark-mode-a3f9` | space-free stem for `raw/` paths |
| `attempt_id` | `r2-a2` | round + attempt; a retry gets a new one |
| `attempt_nonce` | `7c4f1e9b2a6d48f3b0e5c71d9a2f6b84` | **the only reliable identity.** 32 random hex chars (`[guid]::NewGuid().ToString('N')` / `crypto.randomBytes(16).toString('hex')`), per attempt |

`run_id` is a human-readable timestamped name (`YYYY-MM-DD HH-mm-ss <slug> <4-hex>`) on the artifact the user reads; machine-facing paths stay space-free. Not cosmetic: a spaced brief path passed to `codex exec` was re-split by PowerShell into separate native arguments — `error: unexpected argument '14-28-13' found`, round wasted.

**`safe_id-attempt_id` is only *probably* unique** — its 4-hex component collides roughly 1 in 65,536 within the same second. Never treat it as an identity. Use `attempt_nonce` for anything that must be exact, above all liveness matching (§6).

```
<project>/adversarial-review/
  2026-09-01 14-32-07 add-dark-mode a3f9 review.md    <- run log; this IS the state
  .scope-a3f9/                                        <- [review] staged allowlist
  .lock                                               <- transient run lock
  raw/
    20260901-143207-add-dark-mode-a3f9-r1-a1-7c4f1e9b...-brief.md
    20260901-143207-add-dark-mode-a3f9-r1-a1-7c4f1e9b...-last.json
    20260901-143207-add-dark-mode-a3f9-r1-a1-7c4f1e9b...-exit.txt
    20260901-143207-add-dark-mode-a3f9-r1-a1-7c4f1e9b....jsonl
```

Every `raw/` filename carries `safe_id`, `attempt_id`, **and `attempt_nonce`**. There is no `r1.last.json` form.

**[build] Snapshots live outside the project:** `$env:TEMP\codec-snap-<safe_id>\` (Windows) or `${TMPDIR:-/tmp}/codec-snap-<safe_id>/` (macOS/Linux). A snapshot inside the worktree lands inside its own comparison and can recurse while copying. Write a manifest of per-file SHA-256 and **verify a test restore** into a scratch directory before treating it as a rollback base. For a **non-git** project, bash (the manifest helper is reused by §8):

```bash
snap="${TMPDIR:-/tmp}/codec-snap-$safe_id"        # outside the project
project='<project_root>'

# "<sha256>  <relative path>" for every application file, sorted; run artifacts, .git and
# node_modules excluded (the same exclusions as the tar copy below).
manifest_of() {
  ( cd "$1" && find . -type f \
      -not -path '*/adversarial-review/*' -not -path '*/.git/*' -not -path '*/node_modules/*' \
      -print | LC_ALL=C sort | while IFS= read -r p; do shasum -a 256 -- "$p"; done )
}

mkdir -p "$snap/files" && manifest_of "$project" > "$snap/manifest.txt"
( cd "$project" && tar -cf - --exclude=adversarial-review --exclude=.git --exclude=node_modules . ) |
  ( cd "$snap/files" && tar -xf - )

# verify a test restore into a scratch directory before trusting the snapshot
mkdir -p "$snap/restore-test"
( cd "$snap/files" && tar -cf - . ) | ( cd "$snap/restore-test" && tar -xf - )
if [ "$(manifest_of "$snap/restore-test")" = "$(cat "$snap/manifest.txt")" ]; then
  echo "restore verified"
else
  echo "RESTORE MISMATCH - snapshot is not a rollback base"
fi
rm -rf "$snap/restore-test"
```

On Windows the same manifest comes from the `Get-FileHash` block in §8, writing `$snap\manifest.json`.

**[build] Git projects hard-gate on ignore status.** Confirm `git check-ignore adversarial-review` succeeds before running — not merely offer. Excluding the directory from a clean-tree pathspec does nothing to stop a later `git add .` staging briefs and raw model output containing source excerpts, and many Claude Code setups pre-allow `git add`.

---

## 5. Invoking Codex

### 5a. Data guard — staging is mandatory [review]

Codex runs under the user's own ChatGPT/OpenAI account, so anything it reads leaves the machine.

Build an explicit **allowlist**, copy it into `.scope-<hex>/`, and point `-C` and cwd there. Refuse to stage symlinks and Windows reparse points (PowerShell: `(Get-Item $p).LinkType` non-null; bash: `[ -L "$p" ]` — skip and report).

Backstop patterns when building the allowlist:

```
.env*  *.db  *.sqlite*  auth.json  .credentials.json
*sa-key*.json  service-account*.json
*.pem  *.key  *.pfx  id_rsa*  .npmrc
*token*  *secret*  *credential*
*.csv  *.xlsx                      # data exports are the usual personal-data carrier
.git/  node_modules/  .venv/  __pycache__/  dist/  build/
adversarial-review/
```

Apply the patterns and state the resulting scope in one line. **Do not scan for sensitive hits and do not ask before staging** — per the design decision in §3a, that gate is withdrawn. Excluding `adversarial-review/` keeps the run's own artifacts out of the staged working set — per §3a it does not stop Codex reading them.

### 5b. Prepared-phase setup [both]

PowerShell:

```powershell
$SKILL_DIR = '<the "Base directory for this skill" path of codec-review>'
$SCHEMA = Join-Path $SKILL_DIR 'references\review-output.schema.json'
$attempt_nonce = [guid]::NewGuid().ToString('N')      # persist to frontmatter NOW
$stem  = "$raw\$safe_id-$attempt_id-$attempt_nonce"
$brief = "$stem-brief.md"
$last  = "$stem-last.json"
$exit  = "$stem-exit.txt"
$jsonl = "$stem.jsonl"

# conditional: an unresolvable model or rejected effort must degrade, not fail
$tune = @()
if ($model)  { $tune += @('-m', $model) }
if ($effort) { $tune += @('-c', "model_reasoning_effort=`"$effort`"") }

# preconditions for leaving `prepared`
if (-not (Test-Path -LiteralPath $brief))        { throw "brief missing: $brief" }
if ((Get-Item -LiteralPath $brief).Length -eq 0) { throw "brief empty: $brief" }
if (Test-Path -LiteralPath $last)                { throw "output already exists: $last" }
```

bash:

```bash
SKILL_DIR='<the "Base directory for this skill" path of codec-review>'
SCHEMA="$SKILL_DIR/references/review-output.schema.json"
attempt_nonce=$(node -e 'process.stdout.write(require("crypto").randomBytes(16).toString("hex"))')  # persist to frontmatter NOW
stem="$raw/$safe_id-$attempt_id-$attempt_nonce"
brief="$stem-brief.md"
last="$stem-last.json"
exitf="$stem-exit.txt"
jsonl="$stem.jsonl"

# conditional: an unresolvable model or rejected effort must degrade, not fail
tune=()
if [ -n "$model" ];  then tune+=(-m "$model"); fi
if [ -n "$effort" ]; then tune+=(-c "model_reasoning_effort=\"$effort\""); fi

# preconditions for leaving `prepared`
die() { echo "$*" >&2; exit 1; }
[ -f "$brief" ] || die "brief missing: $brief"
[ -s "$brief" ] || die "brief empty: $brief"
[ ! -e "$last" ] || die "output already exists: $last"
```

(`codec-build` never passes `--output-schema`, so `$SCHEMA` is only used by review rounds.)

`$model` comes from a local file read, never a web search. PowerShell:

```powershell
$mc = Join-Path $env:USERPROFILE '.codex\models_cache.json'
$model = ((Get-Content -LiteralPath $mc -Raw -Encoding utf8 | ConvertFrom-Json).models |
          Where-Object { $_.visibility -eq 'list' -and $_.slug -match '^gpt-\d+(\.\d+)?-sol$' } |
          Sort-Object { [version](($_.slug -split '-')[1] + '.0') } -Descending |
          Select-Object -First 1).slug   # -> gpt-6.1-sol (2026-10-06)
```

bash (same allowlist and numeric version sort; prints nothing when the cache is missing or unreadable):

```bash
resolve_sol_model() {
  node -e '
    const fs = require("fs"), os = require("os"), path = require("path");
    try {
      const mc = path.join(os.homedir(), ".codex", "models_cache.json");
      const models = JSON.parse(fs.readFileSync(mc, "utf8").replace(/^\uFEFF/, "")).models || [];
      const rx = /^gpt-(\d+(?:\.\d+)?)-sol$/;
      const sol = models
        .filter(m => m.visibility === "list" && rx.test(m.slug))
        .map(m => ({ slug: m.slug, v: m.slug.match(rx)[1].split(".").map(Number) }));
      sol.sort((a, b) => {
        for (let i = 0; i < Math.max(a.v.length, b.v.length); i++) {
          const d = (b.v[i] || 0) - (a.v[i] || 0);
          if (d) return d;
        }
        return 0;
      });
      if (sol.length) process.stdout.write(sol[0].slug);
    } catch (e) {}
  '
}
model=$(resolve_sol_model)    # -> gpt-6.1-sol (2026-10-06)
```

Codex maintains that file itself, so the pick follows future releases with no edit. **Sol family only, newest version wins** (like the `opus`/`sonnet` aliases). Don't sort by Codex's `priority` and don't drop the slug filter: the unfiltered top-priority pick could float `gpt-6-astra` or another unrunnable model to the top (see `troubleshooting.md`). Missing or unparseable → leave `$model` empty and let Codex use its own default. Record resolved model, `codex --version`, and binary path in the log: a machine can have **two** Codex binaries (the npm install on PATH and the desktop app's), and `models_cache.json` may be written by the other one.

**Degraded retry.** On an unknown-model or unsupported-effort error, retry **once** with `$tune = @()` / `tune=()`, as a **new `attempt_id` and new nonce**, re-entering `prepared`. Reusing the failed attempt's paths would overwrite its evidence and violate approval invariant 1. It stays in the same logical round, and **stays on the same thread only if `thread.started` already produced a validated UUID** — a model or config rejection can occur *before* the thread exists, in which case start a new thread and record the failed pre-thread attempt.

Assert the brief because a missing input costs a real round: a command meant to write a round-2 brief was blocked by a harness guard, the brief never existed, the round launched anyway, and Codex spent a turn replying *"the round-two review cannot run because the specified brief does not exist."* It was right to refuse.

### 5c. Review rounds [review] — read-only, cwd = `staging_dir`

PowerShell:

```powershell
$ErrorActionPreference = 'Continue'      # native stderr must not abort the call
Set-Location -LiteralPath $cwd_root      # = staging_dir; SAME every round (resume filters by cwd)
$prompt = "Read the brief at '$brief' and follow it exactly."

if ($round -eq 1) {
  codex exec --skip-git-repo-check -s read-only -C "$cwd_root" `
    @tune --output-schema "$SCHEMA" --json -o "$last" $prompt > "$jsonl"
} else {
  codex exec resume $thread_id --skip-git-repo-check -c sandbox_mode="read-only" `
    @tune --output-schema "$SCHEMA" --json -o "$last" $prompt > "$jsonl"
}
$LASTEXITCODE | Set-Content -LiteralPath $exit -Encoding utf8   # persist BEFORE anything else
```

bash:

```bash
cd "$cwd_root" || exit 1                 # = staging_dir; SAME every round (resume filters by cwd)
prompt="Read the brief at '$brief' and follow it exactly."

if [ "$round" -eq 1 ]; then
  codex exec --skip-git-repo-check -s read-only -C "$cwd_root" \
    "${tune[@]}" --output-schema "$SCHEMA" --json -o "$last" "$prompt" > "$jsonl" < /dev/null
else
  codex exec resume "$thread_id" --skip-git-repo-check -c sandbox_mode="read-only" \
    "${tune[@]}" --output-schema "$SCHEMA" --json -o "$last" "$prompt" > "$jsonl" < /dev/null
fi
echo $? > "$exitf"                       # persist BEFORE anything else
```

### 5d. Build rounds [build] — workspace-write, cwd = `project_root`

PowerShell:

```powershell
$ErrorActionPreference = 'Continue'
Set-Location -LiteralPath $cwd_root      # = project_root, the REAL worktree
$prompt = "Read the work order at '$brief' and follow it exactly."
$gitCheck = if (Test-Path -LiteralPath (Join-Path $cwd_root '.git')) { @() } else { @('--skip-git-repo-check') }

if ($round -eq 1) {
  codex exec @gitCheck -s workspace-write -C "$cwd_root" `
    @tune --json -o "$last" $prompt > "$jsonl"
} else {
  codex exec resume $thread_id @gitCheck -c sandbox_mode="workspace-write" `
    @tune --json -o "$last" $prompt > "$jsonl"
}
$LASTEXITCODE | Set-Content -LiteralPath $exit -Encoding utf8
```

bash:

```bash
cd "$cwd_root" || exit 1                 # = project_root, the REAL worktree
prompt="Read the work order at '$brief' and follow it exactly."
git_check=()
if [ ! -e "$cwd_root/.git" ]; then git_check=(--skip-git-repo-check); fi

if [ "$round" -eq 1 ]; then
  codex exec "${git_check[@]}" -s workspace-write -C "$cwd_root" \
    "${tune[@]}" --json -o "$last" "$prompt" > "$jsonl" < /dev/null
else
  codex exec resume "$thread_id" "${git_check[@]}" -c sandbox_mode="workspace-write" \
    "${tune[@]}" --json -o "$last" "$prompt" > "$jsonl" < /dev/null
fi
echo $? > "$exitf"
```

No `--output-schema`: a build's deliverable is a diff plus a prose report (§8).

### 5e. Rules both templates depend on [both]

- **`-c sandbox_mode=...` on every resume.** `resume` rejects `-s`, so without it Codex inherits `~/.codex/config.toml` — which could let a *review* write files. Verified: a resume round told to create a file returned `patch rejected: writing is blocked by read-only sandbox`, and no file appeared.
- **Build `$prompt` as a variable with the path single-quoted.** Never embed doubled double-quotes; that is the form that broke.
- **Pass the thread UUID explicitly. Never `resume --last`** — it is cwd-scoped and will silently resume an unrelated session, which looks exactly like success.
- **Persist the exit code on the very next line** (`$LASTEXITCODE` / `$?`). Invariant 4 needs a proven exit code, and after a crash the in-memory value is gone.
- Launch with `run_in_background: true` and `timeout: 7200000`. Foreground ceiling is 10 min; a background command with no `timeout` stops at 30 min (max 2 h). If a round is stopped, Claude is notified: classify per §6 and resume the thread.

### 5f. Capturing `thread_id` — a hard gate [both]

```json
{"type":"thread.started","thread_id":"01a05cba-78f9-7b53-b3c4-c01891318661"}
```

PowerShell:

```powershell
$thread_id = ([regex]'"thread_id":"([^"]+)"').Match((Get-Content -LiteralPath $jsonl -Raw)).Groups[1].Value
```

bash:

```bash
thread_id=$(grep -o '"thread_id":"[^"]*"' "$jsonl" | head -1 | cut -d'"' -f4)
```

**No id → abort the loop after round 1.** A fresh thread per round destroys the premise: Codex loses its own prior critiques and re-litigates settled points forever, which reads like a working loop but converges on nothing. Verified: a correct resume reuses the identical `thread_id` and reports earlier findings in `settled`.

---

## 6. State, recovery, and proving quiescence [both]

The run log **is** the state. Frontmatter is rewritten at every phase transition, which is what lets a loop survive a compaction, a crash, or a killed round.

**[review] frontmatter**

```yaml
---
skill: codec-review
run_id: 2026-09-01 14-32-07 add-dark-mode a3f9
safe_id: 20260901-143207-add-dark-mode-a3f9
status: in-progress        # in-progress | approved | deadlock | aborted | error
phase: running             # prepared | running | result-written | parsed | adjudicated
attempt_id: r2-a2
attempt_nonce: 7c4f1e9b2a6d48f3b0e5c71d9a2f6b84
pid: 26676                 # written immediately AFTER process creation
pid_start: 2026-09-01T14:57:57Z
cwd_root: <project>/adversarial-review/.scope-a3f9     # = staging_dir for a review
staging_dir: <project>/adversarial-review/.scope-a3f9
target: <project>/plans/add-dark-mode.md
target_sha256: 9f2c...
working_copy: <project>/adversarial-review/.scope-a3f9/PLAN.md
thread_id: 01a05cba-78f9-7b53-b3c4-c01891318661
codex_version: 0.156.1
model: gpt-6-sol
effort: high
max_rounds: 5
rounds:
  - {n: 1, attempt: r1-a1, verdict: revise, findings: 9, accepted: 8, rejected: 0,
     raw: 'raw/20260901-143207-add-dark-mode-a3f9-r1-a1-7c4f1e9b...-last.json'}
---
```

**[build] frontmatter** — same fields except `skill: codec-build`, `mode: 1|2`, `cwd_root` = `project_root`, **no `staging_dir` and no `working_copy`**, plus:

```yaml
project_root: <project>
spec_file: <project>/adversarial-review/...-spec.md
snapshot_dir: <temp>/codec-snap-20260901-143207-...
snapshot_manifest: <temp>/codec-snap-.../manifest.json
base_sha: 4a91c0e                  # git projects only
max_fix_rounds: 2
rounds:
  - {n: 1, attempt: r1-a1, complete: true, files_touched: 6, tasks_completed: 6,
     proof: pass, raw: 'raw/...-last.json'}
```

**`cwd_root` is mandatory in both.** Recovery reads it rather than assuming staging.

### Proving quiescence — never infer "not running" from artifacts

A child's pid cannot be known before it exists, so `running` is written *after* creation. And **the shell creates the `.jsonl` at redirection time**, so an empty or absent `.jsonl` says nothing about whether Codex ran. `prepared` therefore means **"launch unconfirmed"**, never "nothing launched".

Match on `$attempt_nonce`, and **search the whole process table, not just `node`** — there is a window where the launching shell is alive but has not yet spawned node. PowerShell:

```powershell
$live = Get-CimInstance Win32_Process |
        Where-Object { $_.CommandLine -like "*$attempt_nonce*" -and $_.ProcessId -ne $PID }
```

bash (macOS / Linux; the process-table listing is not available in Git Bash, so this block was **not** run in testing):

```bash
live=$(ps -axww -o pid=,command= | grep -F -- "$attempt_nonce" | grep -v -F -- 'grep -F' |
       awk -v me="$$" '$1 != me')
if [ -n "$live" ]; then echo "LIVE - wait, never relaunch:"; echo "$live"; else echo "no live match"; fi
```

For this to work the nonce must appear **literally** in the launching command text — assign it as a literal string, not resolved from elsewhere — and it is part of `$stem`, so it also reaches node's argv. Verified on Windows: `Win32_Process` populates `CommandLine`, matches a live codex node process, and exposes `CreationDate`; compare that against `pid_start` to defend against pid reuse (macOS/Linux: `ps -o lstart= -p <pid>`).

Recovery order:

1. **Any live match → wait. Never relaunch.** Two turns on one thread corrupt its history and double-count findings.
2. No live match → the attempt is dead. Classify by artifact:

| Evidence for this attempt | Meaning | Action |
|---|---|---|
| `$jsonl` absent, or no `thread.started` | Never reached Codex | Relaunch as a new `attempt_id` + nonce |
| `thread.started`, no `turn.started` | Thread opened, no turn billed | Relaunch as a new attempt; record the orphan thread |
| `turn.started`, no `$last` | **A turn was consumed and its result lost** | Do not retry the round. Resume the thread asking it to resend its last response as JSON only. Log the lost turn |
| `$last` non-empty **and** `$exit` present | Round completed | Advance to `result-written` |
| `$last` non-empty, **`$exit` missing** | Crashed before the exit code was persisted | Exit status unproven → invariant 4 unmet. Treat as `revise`, or re-ask on the thread. **Never approve.** |

**Never advance to round N+1 while phase is `running`.**

**Step 1 of both skills:** scan `adversarial-review/*.md` for `status: in-progress` whose `target` matches; follow the order above. Never assume round N finished.

### Destructive changes need a compare-and-swap [both]

Before overwriting or annotating the original target at sign-off, **re-hash it and compare to `target_sha256`.** On mismatch it changed under us — another session, or the user editing directly. Stop and make the user choose. A `.bak` is not sufficient: it preserves the version being destroyed, not the one being lost.

---

## 7. Reading the result [review]

Three signals, and they disagree:

1. **Persisted exit code.** Non-zero is fatal. Verified: a run can exit **0 while printing `ERROR` to stderr**, so stderr alone never means failure.
2. **Top-level JSONL events.** `^\{"type":"(error|turn\.failed)"` is fatal.
3. **Cosmetic warnings to ignore** — Codex plugins can emit these every run as `item.completed` items whose `item.type` is `error`:
   - `clamping SessionEnd hook timeout to 3s in ...hooks.json`
   - `Skill descriptions were shortened to fit the skills context budget...`

### Verdict parse ladder — fail closed

1. Exit code ≠ 0 → hard stop, log the stderr tail, no verdict.
2. Parse this attempt's `$last` as JSON → read `verdict`.
3. Not JSON → strip code fences, then take the **last** match of `VERDICT: APPROVED|REVISE` on a line of its own, case-insensitive (PowerShell: `(?im)^\s*VERDICT:\s*(APPROVED|REVISE)\s*$`; bash: `grep -Eio '^[[:space:]]*VERDICT:[[:space:]]*(APPROVED|REVISE)[[:space:]]*$' "$last" | tail -1`).
4. Both tokens present → `revise`.
5. No match → `unparsed`; re-ask **once** on the same thread ("reply with only the JSON object"); still nothing → stop and surface it to the user.

**The regex fallback may only ever yield `revise` or `unparsed` — never `approved`.**

### Approval is a validated state, not a reported one

OpenAI strict mode ignores `description`, so the schema alone permits `approved` beside a full `findings` array. The model saying "approved" proves nothing. Reject it unless **all five** hold:

1. `$last` is **attempt-specific and never used before** — guaranteed by the nonce. A missing file is an error, never an approval. **Never delete and reuse an output path**: an earlier process may still be writing to it, and deletion destroys evidence.
2. `findings` is empty.
3. `next_steps` is empty.
4. Persisted exit code is `0` and no fatal JSONL event.
5. **The finding ledger reconciles** — every id raised in any earlier round has a terminal state: `accepted` (and addressed), `rejected` (with cited evidence), or present in Codex's `settled`.

Any failure → treat the round as `revise` and log which invariant broke. This is what stops the fake convergence the design exists to prevent.

---

## 8. Build completion is a different test [build]

A build round has **no output schema and no verdict object**. Running the §7 ladder against its prose would parse as `unparsed`, trigger a pointless re-ask, then halt a build that actually succeeded. Never apply §7 to a build round.

A build round is **complete** when all hold:

1. Persisted exit code `0`, no fatal JSONL event.
2. `$last` non-empty — Codex produced its report.
3. The report's closing manifest parses, with `files_touched` and `tasks_completed`.
4. **At least one changed *application* file**, where the spec implies changes.
5. Every spec task appears in `tasks_completed`, and every path in `files_touched` is inside `project_root`.

Condition 4 must **exclude the run's own artifacts**, or it passes trivially — briefs, JSONL, exit files and the run log all live inside the worktree and change on every attempt:

```powershell
# git project
git status --porcelain -- . ':(exclude)adversarial-review'

# non-git project: compare manifests, not trees
$now = Get-ChildItem -LiteralPath $cwd_root -Recurse -File |
       Where-Object { $_.FullName -notlike "*\adversarial-review\*" -and
                      $_.FullName -notlike "*\.git\*" -and
                      $_.FullName -notlike "*\node_modules\*" } |
       ForEach-Object { @{ p = $_.FullName.Substring($cwd_root.Length + 1)
                           h = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash } }
# diff $now against snapshot_manifest; require >= 1 changed application path
```

bash (`manifest_of` is defined in §4):

```bash
# git project
git status --porcelain -- . ':(exclude)adversarial-review'

# non-git project: compare manifests, not trees
manifest_of "$cwd_root" > "$snap/now.txt"
changed=$(diff "$snap/manifest.txt" "$snap/now.txt" | grep -c '^[<>]')
echo "changed application lines: $changed"      # require >= 1 changed application path
```

A bare `git diff --no-index <snapshot> <worktree>` is **not** a valid completion proof, for the same reason. An empty application diff is the exact symptom of the staging misconfiguration in §1.

**Completion is not acceptance.** It only means the round produced something reviewable: Opus then reads the full diff, runs the proof command, and the human commit gate decides. Commits are Claude's, never Codex's, and only after that gate.

---

## 9. The run lock [both]

A lock is **transient and released**. It stops two runs racing in one project, lives at `adversarial-review/.lock` for one run, and is released on **every** terminal path, including error and deadlock.

The run lock is not the plan-review record. The optional `plan-review` mod keeps a **persistent** record, `plans/.codec-reviewed.json`, keyed by the SHA-256 of the approved plan (a re-approved unchanged plan lands at a new timestamped path, so a path key would miss it). An entry is `reviewing` only while its lease is live: a lease, not a lock file or a log status, is the only evidence a review is still running, because both of those survive a crash. `codec-review` renews the lease every round, marks the entry `reviewed` at the end, and removes it on abort, using `scripts/plan-record.mjs` (SKILL.md Step 6). If `codec-review` never starts, the lease expires and the next approval asks again; that is the intended failure mode.

Use exclusive create, never check-then-write. The lock stores the owner `run_id`; liveness of a *round* is decided by the attempt nonce (§6), because the pid of a short-lived tool shell says nothing. PowerShell:

```powershell
$fs = [System.IO.File]::Open($lock, 'CreateNew', 'Write', 'None')   # throws if it exists
```

bash (`noclobber` makes `>` fail if the file exists):

```bash
if ( set -o noclobber; printf '%s\n' "$run_id" > "$lock" ) 2>/dev/null; then
  echo "lock acquired"
else
  echo "lock held"
fi
```

---

## 10. Arbitration record [both]

Claude writes the plan and then judges objections to it. "Do not fake convergence" is aspirational unless recorded, so every round's log entry carries:

| Finding | Verdict | Reason |
|---|---|---|
| F1 Read boundary not enforced | accepted | Confirmed empirically; staging reframed as mitigation. |
| F6 Bypass escapes rollback | escalated | Human decision — the hatch was kept. |

**A rejected finding must cite a `file:line` or a test result, not an assertion.** Claude keeps final say — Codex advises, it does not command — but a rejection without evidence is not a rejection.

Distinguish **`rejected`** (Claude judges it wrong) from **`escalated`** (a human decision, not a technical one). Recording an escalation as a rejection is how a real risk becomes invisible.

At deadlock, embed **Codex's raw final message verbatim** beside Claude's summary, so the user reads the unreconciled position in the critic's own words. State whether the deadlock is *cap-reached* or *irreconcilable* — they mean different things, and only the second implies disagreement.

### Hard rule: the arbiter never runs in a subagent

If your settings define `env.CLAUDE_CODE_SUBAGENT_MODEL` (for example `"sonnet"`), a subagent launched to "let Opus judge" may silently run as the smaller model — no error, no visible signal. The main session already runs the stronger model, so arbitrating inline is correct and free.

The only legitimate subagent here is a read-only `Explore` gatherer on a very large diff, which condenses and never decides.

---

## 11. Failure playbook [both]

| Symptom | Cause | Action |
|---|---|---|
| `Codex CLI is not installed...` | `codex --version` or `codex app-server --help` failing | Stop. Point at `/codex:setup` (Codex plugin) or `npm install -g @openai/codex`, and make the skill's Step 0a same-family offer. Never switch to a Claude critic silently. |
| HTTP 400 `invalid_json_schema` | A schema property missing from `required` | Fix the schema (below); retry as a new attempt. |
| Exit 0 but empty `$last` | Turn failed after `thread.started` | Read the top-level JSONL `error`/`turn.failed` message and surface it. |
| No `thread_id` in round 1 | Failed before the thread opened | Abort the loop. Never continue with a fresh thread per round. |
| `No previous ... thread was found` | cwd is not the `cwd_root` round 1 used, or a bad UUID | `Set-Location` / `cd` to the frontmatter `cwd_root` — staging for review, project for build — and pass the logged UUID. |
| Codex refuses, citing a missing brief | `prepared` preconditions not asserted | Write and assert the brief; retry as a new attempt. Codex refusing is correct behaviour. |
| Round killed at 10 minutes | Tool ceiling on a foreground call | Classify per §6, then resume; switch to `run_in_background: true`. |
| Build reports success, empty diff | `-C`/cwd pointed at staging instead of `project_root` (§1) | Re-run the build round with `cwd_root = project_root`. |
| Build report says the Vite/client build failed with `Error: spawn EPERM` in `esbuild\lib\main.js` (`ensureServiceIsRunning`) | Codex's `workspace-write` sandbox blocks esbuild from spawning its native service binary. Not a code bug — the same build passed first try from Claude's own shell (observed 2026-10-11). | Don't send a fix round for it. Run the build half of `PROOF_CMD` yourself; treat Codex's "build blocked" deviation as expected for any Vite/esbuild project. |
| Review comes back terse and non-technical | Style rules in an instruction file Codex loads into every run (for example "plain English", "5 lines max") | Remove or scope them away from Codex's instruction files before debugging anything else. |
| `.lock` present | A run is already active for this project | Report it. Offer to resume, or break the lock after proving no process matches its nonce. |
| `bash: -c: unexpected EOF while looking for matching` when writing a brief **(Windows, Git Bash via the Bash tool)** | A `cat > f <<'EOF'` heredoc whose body contains an apostrophe — the Bash tool mangles it. Cost two turns in a real run, and it also silently corrupts non-ASCII characters. | Write long content with the **Write tool**, or write it to a scratch file and `cat` it into place. The per-round brief is the largest artifact in the loop, so this hits the most common operation. Same failure for `python - <<'PY'` bodies; prefer the Edit tool for surgical changes. |
| `SyntaxError: (unicode error) 'unicodeescape' codec can't decode` in inline Python **(Windows)** | A Windows path in a normal Python string: `C:\Users\...` reads `\U` as an escape. | Use a raw string or forward slashes. Applies to any path you paste into a one-off script, including the run log's own frontmatter values. |
| Round N's findings are all fixes from round N-1 | Patch-style revision across sections | Expected, not a malfunction — it dominated four consecutive rounds in the run that produced this note. Run the skill's phrase sweep after every revision, prefer whole-subsection rewrites, and name your least-certain fixes in the next brief so the critic attacks those first. |
| `The 'gpt-…-sol' model is not supported when using Codex with a ChatGPT account`, native `Access is denied`, or a stale model after upgrading | Old CLI, Windows sandbox ACL, or a stale broker process | See `troubleshooting.md`. |

### Output-schema constraints (OpenAI strict mode)

`review-output.schema.json` obeys rules that are easy to violate:

- **Every key in `properties` must also appear in `required`.** A genuinely optional field is `required` with a nullable type: `"type": ["integer", "null"]`. Omitting a key returns HTTP 400 and wastes the round.
- `minLength` / `minimum` / `maximum` are ignored — put constraints in `description`.
- `additionalProperties: false` at every object level.
