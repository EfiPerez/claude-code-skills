---
name: codec-review
description: >-
  Runs a bounded adversarial review loop between Claude (builder and arbiter) and OpenAI Codex (newest GPT Sol model, read-only critic) over a document or codebase. Codex attacks the work and returns a structured verdict; Claude judges each finding, rewrites the target, and re-submits to the SAME Codex thread until Codex approves or the round cap is hit (5 by default). Runs silently: the only question the user is asked is whether to spend more rounds at the cap. Output: one report file. Use when the user says "/codec-review", "codec review this", "adversarial review", "have Codex review this", "stress-test this plan", "argue this with Codex", "get a second model to check this", or is about to build something expensive to get wrong (auth, schema, migrations, concurrency, payments, personal data). Reviews only; never writes implementation code. To have Codex BUILD a frozen spec, use codec-build. For a fast one-shot critique of a git diff with no loop, the Codex plugin's /codex:adversarial-review is cheaper.
---

# codec-review — adversarial review loop

**If a Codex call fails before any review work starts, re-run Step 0's checks, then read
`references/troubleshooting.md`.** The Windows sandbox/ACL failure and the two model-slug
failures all surface as an identical hard error from Codex's stderr, and that file is the only
place the three are told apart. It does not load by itself.

Claude is builder **and** arbiter. Codex is a read-only critic that can read files but cannot
write one. They argue through a working copy plus one persistent Codex thread.

**The user is asked exactly one question, and only if the loop hits its cap** (plus, only when
Codex can't be reached, the Step 0a same-family offer before the run starts). Nothing else is
escalated, confirmed, or reported mid-run. The user does not want to referee the debate — they
want the converged artifact and a one-page table of what changed.

This file is self-contained: every command the loop needs is below.
[codec-loop.md](references/codec-loop.md) is **reference for when something breaks** — the
failure playbook, recovery order, and the reasoning behind each command form. Read it on
failure or when changing this skill, not on every run.

Adapted from `chaseai-yt/claudex-loop`'s `codex-review` (MIT — see the repository's `NOTICE`).
Chase's `grill-me-codex` / `grill-with-docs-codex` / `claudex-loop` skills are out of scope.

## Which shell

Every command block below comes in two forms. In the **PowerShell tool (Windows)** use the
PowerShell block. In the **Bash tool (macOS or Linux; Git Bash on Windows also works)** use the
bash block. Never mix the two in one call, and run each block as a whole — the `$`-variables
and the shell's working directory do not survive between tool calls, so re-assign them at the
top of every call. The bash blocks use only `bash`, POSIX tools that ship with macOS, `git` and
`node`. They were tested under Git Bash on Windows; macOS itself is untested. Advice marked
**Windows-only** does not apply on macOS or Linux.

`SKILL_DIR` below means the folder of this skill: the path the skill loader printed as
"Base directory for this skill" when it loaded `SKILL.md`. Never guess it.

## Hard rules

- **Rewrite the target. Never annotate it.** This is the rule that decides whether the loop is
  cheap or ruinous — see "Why rewriting is the whole trick" below.
- **Run silent.** No per-round status in the conversation. One line at the end with the report
  path. A round that found nothing new is not news.
- **Never write implementation code.**
- **Never approve on Claude's own judgement.** Approval comes only from Codex (or, in
  same-family mode, the critic subagent — Step 0a), and only when all five invariants below hold.
- **Arbitrate in the main session, never a subagent.** If you set
  `CLAUDE_CODE_SUBAGENT_MODEL` (for example to `sonnet`), an "Opus" subagent may silently be a
  smaller model. The only legitimate subagent is a read-only `Explore` gatherer on a very large
  diff, which condenses and never decides.
- **No per-run exposure prompt — but know what this does.** Codex sends whatever it reads to
  OpenAI, under the user's own account. `-s read-only` restricts **writes only**; it does not
  confine reads to the project. Codex can read any file the user's account can read: the
  project's `.env` and data files, and also files elsewhere such as home-directory credentials
  and global config. Do not raise the topic on every run — the repository README carries the
  warning — and never describe scope exclusions as enforced: they are cost and noise hygiene,
  not a boundary. The user should run this skill only on projects and machines where that
  exposure is acceptable.

## Tunables

| Var | Default | Meaning |
|---|---|---|
| `MAX_ROUNDS` | `5` | Hard cap. Raising it is the user's decision, asked once at the cap. |
| `EFFORT` | `high` | Codex reasoning effort. |
| `MODEL` | resolved | Newest-version listed `gpt-<N>-sol` / `gpt-<N.M>-sol` model in `~/.codex/models_cache.json` (Sol family only — never Astra/Luna/Terra or `-mini` variants). Like `opus`/`sonnet` aliases: a new Sol release is picked up with no edit. Missing or unreadable cache → pass no `-m` and let Codex use its own default. |

Honour `rounds=N` if passed. Do not echo the resolved values — log them.

---

## Step 0 — Can this app reach Codex?

A one-time setup check per computer, shared with `codec-build`. Stop at the first check that
fails: tell the user in two or three plain sentences what you found and what to do next. Check 1
failing ends the run. Checks 2–3 failing end it too, unless the user takes the same-family offer
in Step 0a.

- **Check 1 is free and always applies** — it only looks at this session's tool list.
- **Checks 2–3 run only when `~/.claude/state/codec/codex-ready.json` is absent.** When both
  pass, write that file (`{"codex_version": "...", "checked": "<ISO date>"}`, creating the
  folder if needed) and continue silently. When it exists, skip them.
- **If any later Codex call fails before review work starts, delete the marker and re-run
  checks 2–3** before reading `references/troubleshooting.md` — a since-logged-out or
  uninstalled Codex must get this plain explanation, not a raw error.
- **Any failed check 2–3 deletes the marker — no exceptions**, even when the cause looks
  temporary or session-specific (a probe kept it once, reasoning "the real setup is probably
  fine"). The marker means "verified working", never "probably fine".

1. **Shell access.** No Bash or PowerShell tool in this session (Claude Desktop's Chat tab,
   claude.ai, mobile) → this skill cannot run here: it drives the Codex command-line program
   on this computer and reads and writes project files, and this app can reach neither. Next
   step: open the project in Claude Code — the Claude Desktop **Code** tab with a **Local**
   session, a terminal, or VS Code — and run the skill again. If a Codex-looking MCP tool is
   connected, say it isn't used: OpenAI removed the official `codex mcp-server`, and the loop
   needs local files anyway.
2. **`codex --version`.** Fails → Codex isn't installed or isn't on PATH. Next step:
   `npm install -g @openai/codex` (needs Node.js), then `codex login`. With the Codex plugin
   for Claude Code installed, `/codex:setup` checks the same things.
3. **`codex login status`.** Non-zero exit / `Not logged in` → Next step: the user runs
   `codex login` in a terminal (it opens a browser; a ChatGPT plan or an API key works). Never
   run `codex login` yourself — it is interactive.

## Step 0a — No Codex connection: offer same-family mode

When check 2 or 3 fails (or a re-run after a pre-work Codex failure still fails), first look for
any other working route to Codex: a connected MCP tool or plugin that can run a Codex review
on local files. None of the known ones can drive this loop (OpenAI removed `codex mcp-server`;
the loop needs `--output-schema`, thread resume and local file reads) — so in practice the
answer is "no connection found". Then, in the same message as the fix-it steps, offer:

> No connection to Codex was found (no working Codex command-line program, and no other Codex
> connection this skill can use). You can fix that with the steps above and run the skill again.
> Or reply **"use Claude"** and I'll run the review with a *different Claude model* as the
> critic instead of a different AI company's model. That is weaker — models from the same
> family share more blind spots and agree more easily — but it is still a valid, independent
> review: the critic sees only the target, never my reasoning.

This is the one extra question this skill may ask. No answer, a headless run, or anything but
a clear yes → end the run. **Never switch silently**, and never offer it while Codex works.
Same-family mode never writes the `codex-ready.json` marker. It also sends nothing to OpenAI:
the critic runs on the same Claude account as the session.

**What changes in same-family mode** (everything else — staging, working copy, rewriting,
arbitration, the five approval invariants, the cap question — is unchanged):

- **Critic** = an `Agent` call with `subagent_type: "Plan"` (read-only: no Edit/Write) and a
  `model` different from the main session's (session on Opus → `sonnet`; on Sonnet → `opus`).
  `CLAUDE_CODE_SUBAGENT_MODEL` can override the requested model — so the critic's brief asks it
  to state its exact model id in `summary`'s first line, and the report records what it said.
  If it turns out to be the main session's own model, the run is still valid (fresh context,
  no shared reasoning) but the report says so.
- **Brief** = the same `references/review-prompt.md` charge, pointing at the working copy's
  absolute path, plus: "End with ONLY a JSON object matching the schema at
  `<SKILL_DIR>/references/review-output.schema.json`" (give its absolute path). No
  `codex exec`, no model resolver, no `tune`.
- **Rounds** = round 1 starts the critic; later rounds continue **the same agent** with
  `SendMessage` (its own earlier critiques stay in its context — the thread rule). If the agent
  can't be continued, start a fresh one with the previous findings and `settled` ids in the
  brief, and log it.
- **Parse** = the critic's final message, with the same fail-closed ladder (JSON → regex
  fallback that never yields `approved` → `unparsed`). Approval still comes only from the
  critic, never the main session.
- **Report** header line: `· Critic: Claude <model id> (same-family mode — no Codex connection;
  weaker than a cross-vendor review, still independent)` in place of `· Codex <model>`. Log
  `critic: claude-<model>` in the run log frontmatter.

## Step 1 — Preflight

1. **Resume check.** Scan `<project>/adversarial-review/*.md` for `status: in-progress` with a
   matching `target`. Found → recover per codec-loop.md §6 and continue from its `thread_id`.
   Never assume the last round finished.
2. **Lock.** Create `<project>/adversarial-review/.lock` exclusively — never check-then-write.
   Held → prove no live process matches its nonce before breaking it (§6).

   PowerShell:

   ```powershell
   $lock = '<project>\adversarial-review\.lock'
   New-Item -ItemType Directory -Force -Path (Split-Path $lock) | Out-Null
   $fs = [System.IO.File]::Open($lock, 'CreateNew', 'Write', 'None')   # throws if it exists
   $b = [Text.Encoding]::UTF8.GetBytes($run_id); $fs.Write($b, 0, $b.Length); $fs.Dispose()
   ```

   bash (`noclobber` makes `>` fail if the file exists):

   ```bash
   lock='<project>/adversarial-review/.lock'
   mkdir -p "$(dirname "$lock")"
   if ( set -o noclobber; printf '%s\n' "$run_id" > "$lock" ) 2>/dev/null; then
     echo "lock acquired"
   else
     echo "lock held: $lock"
   fi
   ```

   Release it (`Remove-Item -LiteralPath $lock -Force` / `rm -f "$lock"`) on **every** terminal
   path, including error and deadlock.
3. **Create the run:** `run_id`, `safe_id`, `.scope-<hex>/`, `raw/`. Log the resolved model,
   version and binary path.

## Step 2 — Resolve the input

- **Absolute path** → verbatim. **Relative** → against the project root.
- **Bare filename** → search the project. One hit → use it. Several → list and ask. **None →
  stop; never substitute a similarly-named file.**
- **A codebase** → ask **once**: whole project / uncommitted only / specific paths. In a
  non-git folder "uncommitted" is unavailable — say so and re-ask; never silently widen to
  whole-project. Untracked files count: check `git status --short --untracked-files=all` *and*
  `git diff --shortstat` *and* `--shortstat --cached`, or a new feature in new files reads as
  "nothing to review".

Copy the target into the staging dir as the **working copy**. The original is untouched until
Step 5. Record `target`, `target_sha256`, `working_copy`.

## Step 3 — The loop

Round 1 opens the thread; later rounds resume it. Per round:

**1. Write the brief.** Round 1: the adversarial charge in `references/review-prompt.md`.
Later rounds: what changed, plus your per-finding verdicts in one line each, and ask Codex to
put resolved ids in `settled`. **Do not restate the target in the brief** — Codex re-reads it
from disk, so pasting it doubles the round's cost for nothing.

When the target is a plan, instruct Codex to **verify each claim against the repository** and
flag any step assuming a file, function or behaviour that does not exist. A plan reviewed in
isolation yields only generic objections.

**2. Prepare.** Assert the preconditions — a missing brief costs a real round.

PowerShell:

```powershell
$SKILL_DIR = '<the "Base directory for this skill" path>'
$SCHEMA = Join-Path $SKILL_DIR 'references\review-output.schema.json'
$attempt_nonce = [guid]::NewGuid().ToString('N')      # persist to frontmatter NOW
$stem  = "$raw\$safe_id-$attempt_id-$attempt_nonce"
$brief = "$stem-brief.md"; $last = "$stem-last.json"
$exit  = "$stem-exit.txt"; $jsonl = "$stem.jsonl"

$mc = Join-Path $env:USERPROFILE '.codex\models_cache.json'
# The slug allowlist is load-bearing - do not widen it to take whatever is
# top-priority. models_cache.json is written and overwritten by Codex itself, so
# a Codex update can float an unrunnable model to the top: on 2026-09-15
# gpt-6-astra surfaced here and a review round launched with -m gpt-6-astra,
# dying on "requires a newer version of Codex" even with config.toml on sol.
# Allowlisting means the next such model also can't be auto-selected. Always
# the NEWEST Sol by version number, not by Codex's priority - so gpt-6.1-sol
# beats gpt-6-sol, and a future gpt-6.2-sol/gpt-7-sol is taken automatically.
# Version is parsed, so 6.10 > 6.9. Full incident: references/troubleshooting.md.
$model = ((Get-Content -LiteralPath $mc -Raw -Encoding utf8 | ConvertFrom-Json).models |
          Where-Object { $_.visibility -eq 'list' -and $_.slug -match '^gpt-\d+(\.\d+)?-sol$' } |
          Sort-Object { [version](($_.slug -split '-')[1] + '.0') } -Descending |
          Select-Object -First 1).slug
$tune = @(); if ($model) { $tune += @('-m',$model) }
if ($effort) { $tune += @('-c', "model_reasoning_effort=`"$effort`"") }

if (-not (Test-Path -LiteralPath $brief))        { throw "brief missing: $brief" }
if ((Get-Item -LiteralPath $brief).Length -eq 0) { throw "brief empty: $brief" }
if (Test-Path -LiteralPath $last)                { throw "output exists: $last" }
```

bash:

```bash
SKILL_DIR='<the "Base directory for this skill" path>'
SCHEMA="$SKILL_DIR/references/review-output.schema.json"
attempt_nonce=$(node -e 'process.stdout.write(require("crypto").randomBytes(16).toString("hex"))')  # persist to frontmatter NOW
stem="$raw/$safe_id-$attempt_id-$attempt_nonce"
brief="$stem-brief.md"; last="$stem-last.json"
exitf="$stem-exit.txt"; jsonl="$stem.jsonl"

# Newest Sol model by version number (same allowlist and numeric sort as the PowerShell
# resolver above; 6.10 > 6.9). Prints nothing when the cache is missing or unreadable.
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
model=$(resolve_sol_model)
tune=()
if [ -n "$model" ];  then tune+=(-m "$model"); fi
if [ -n "$effort" ]; then tune+=(-c "model_reasoning_effort=\"$effort\""); fi

die() { echo "$*" >&2; exit 1; }
[ -f "$brief" ] || die "brief missing: $brief"
[ -s "$brief" ] || die "brief empty: $brief"
[ ! -e "$last" ] || die "output exists: $last"
```

**3. Launch** with `run_in_background: true` and `timeout: 7200000` (rounds exceed the 10-minute foreground ceiling, and a background command stops at 30 min unless `timeout` is set; max 2 h). Re-assign `$cwd_root`, `$brief`, `$last`, `$exit`, `$jsonl`, `$SCHEMA`, `$tune` at the top of this call (or paste the block above in front of it) — variables do not carry over from the Prepare call.

PowerShell:

```powershell
$ErrorActionPreference = 'Continue'      # native stderr must not abort the call
Set-Location -LiteralPath $cwd_root      # = staging_dir; SAME every round
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
cd "$cwd_root" || exit 1                 # = staging_dir; SAME every round
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

- **`-c sandbox_mode=` on every resume.** `resume` rejects `-s`, so without it Codex inherits
  `~/.codex/config.toml`, which could let a *review* write files.
- **Pass the thread UUID explicitly. Never `resume --last`** — cwd-scoped, and it will silently
  resume an unrelated session, which looks exactly like success.
- **Capture `thread_id` from `{"type":"thread.started",...}`. No id → abort after round 1.** A
  fresh thread per round loses Codex's own prior critiques and re-litigates settled points
  forever — a loop that converges on nothing while looking like it works.
- On an unknown-model or unsupported-effort error, retry **once** with no `-m`/effort override
  (`$tune = @()` / `tune=()`) as a **new `attempt_id` and nonce** (never reuse an output path;
  it destroys evidence).

**4. Parse — fail closed.**

1. Exit code ≠ 0 → hard stop, log the stderr tail, no verdict. (A run can exit 0 while printing
   `ERROR` to stderr, so stderr alone never means failure.)
2. Parse `$last` as JSON → read `verdict`.
3. Not JSON → strip fences, then take the **last** match of `VERDICT: APPROVED|REVISE` on a
   line of its own (case-insensitive). PowerShell: `(?im)^\s*VERDICT:\s*(APPROVED|REVISE)\s*$`.
   bash: `grep -Eio '^[[:space:]]*VERDICT:[[:space:]]*(APPROVED|REVISE)[[:space:]]*$' "$last" | tail -1`.
4. Both tokens → `revise`. No match → `unparsed`; re-ask once on the same thread, then stop.
5. **The regex fallback may only yield `revise` or `unparsed` — never `approved`.**

**Take the last `agent_message`, never the first.** Codex sometimes emits a schema-valid
envelope carrying a *statement of intent* before reading anything — observed as
`{"verdict":"approved","summary":"I'll verify … then re-read …","findings":[]}` as message one
of a round whose real verdict, 19 items later, was `revise` with 3 findings. Treat an
`approved` with empty `findings` arriving before any `command_execution` item as `unparsed`:
Codex cannot have approved a target it never opened.

Ignore cosmetic `item.type: error` warnings that plugins emit every run, such as
`clamping SessionEnd hook timeout` and `Skill descriptions were shortened`.

**Approval is validated, not reported.** Strict mode ignores `description`, so the schema
permits `approved` beside a full `findings` array. Reject it unless **all five** hold:

1. `$last` is attempt-specific and never used before. Missing file = error, never approval.
2. `findings` empty. 3. `next_steps` empty. 4. Exit `0`, no fatal JSONL event.
5. **The ledger reconciles** — every id from any earlier round is `accepted` (and addressed),
   `rejected` (with cited evidence), or in Codex's `settled`.

Any failure → treat as `revise` and log which invariant broke.

**5. Arbitrate, in one table row per finding.** `accepted` / `rejected` / `escalated`, with a
one-line reason. **A rejection cites a `file:line` or a test result, not an assertion.** Keep
`rejected` (you judge it wrong) distinct from `escalated` (a human decision) — recording an
escalation as a rejection is how a real risk becomes invisible. Prose essays per finding are
how a run gets expensive; the reason is one sentence.

**6. Rewrite the working copy**, append the round row, increment.

### Why rewriting is the whole trick

The first run of this skill took seven rounds and grew its target by 1,077 lines, because each
round *annotated* the target with a `[CORRECTED]` block instead of fixing the text. Three
things went wrong at once, and they compound:

- The target grew 1,913 → 2,990 lines, so **every later round paid to re-read the record of the
  earlier ones.**
- Each block quoted a superseded rule in prose sitting next to its replacement, so **the
  annotations became the contradiction surface.** Rounds 4–6 were almost entirely findings
  against the previous round's own fixes. Findings went 10, 7, 7, 5, 5, 5 — flat, not
  converging.
- The deliverable became a log of its own review, and a separate clean plan had to be written
  afterwards anyway.

So: **state each rule once, in the present tense, as if it had always been that way.** The
correction history goes in the run log, which is the only place anyone needs it. When the fix
touches more than one section, rewrite the whole section or the whole file in one pass — every
such rewrite in that run settled several findings and regressed none.

Two traps that rewriting introduces, both of which cost a round:

- **Sweep the parts you did *not* rewrite.** A rewrite changes the whole document's consistency
  surface. Round 7 found a superseded rule sitting in an untouched section, contradicting its
  replacement in the rewritten one.
- **Before deleting a correction block, check whether it *defines* anything.** A `[CORRECTED]`
  header makes a load-bearing block look like commentary. That same rewrite deleted the sole
  definition of a required schema enum and left two pointers aimed at removed text. Grep for
  inbound references first.

Sweep flattened, so a line-wrapped survivor cannot hide (bash; run it with the Bash tool, or in
Git Bash on Windows):

```bash
tr '\n' ' ' < "$file" | tr -s ' ' | grep -o "the phrase you superseded"
```

## Step 4 — Termination

- **`approved` + all five invariants** → Step 5.
- **Cap reached** → **the one question.** Ask the user whether to spend `N` more rounds, and
  give a recommendation: recommend continuing when findings are still falling round over round
  or an open finding is `high`; recommend stopping when the count is flat across two rounds,
  since that means the loop is re-litigating rather than converging. Log the answer as a human
  override. If the user declines, go to Step 5 with `status: deadlock-cap-reached`.
- **Error or `unparsed`** → stop and surface it. `unparsed` is never an approval.

Say which kind of deadlock it is: *cap-reached* and *irreconcilable* mean different things, and
only the second implies the two models actually disagree.

## Step 5 — Finish. Claude decides.

No sign-off question: after the cap question, Claude decides and that is it.

1. **Re-hash the original and compare to `target_sha256`.** Match → overwrite it with the
   converged copy and write a `.bak` alongside (never clobber an existing `.bak` — suffix it).
   **Mismatch → do not write.** It changed under us; leave both files and say so in the report.
2. **If the target is a plan** and a `handoff` skill is installed (the `session-handoff` plugin
   from this marketplace provides one), append "Run the handoff skill" as its final task, in
   prose. No `handoff` skill installed → skip this step.
3. **Write the report** (below). Set `status`, release the lock.
4. **Say one line in the conversation:** the verdict, the round count, and the report path.
   Nothing else. If a `high` finding is unresolved, add one sentence naming it.

### The report — `~/.claude/reports/<run_id> report.md`

**Central, not per-project** — one place to scan across every project's reviews, rather than
a folder buried in each one. `run_id` already carries a project-descriptive slug plus a
4-hex nonce (`2026-09-02 11-28-50 pre-deploy-review 4119`), so the filename alone identifies
which project and run it came from with no separate index needed. Create
`~/.claude/reports/` if it doesn't exist yet. The run log, raw round artifacts, and staging
copy stay exactly where they are, under `<project>/adversarial-review/` — only this one
human-readable summary moves.

Written for someone who did not watch the debate. A table, then at most three short notes.

```markdown
# <target> — adversarial review

**<approved | deadlock, cap reached>** after N rounds · Codex <model> (or the Step 0a critic line) · <date>
Project: <project path> · Converged file: <path> · Backup: <path>
Run log: <project>/adversarial-review/<run_id> review.md

| # | Topic | Resolution |
|---|---|---|
| 1 | Readiness banner claimed an unverified state | Fixed — renamed, per-gate states |
| 2 | Codex read boundary described as enforced | Fixed — reframed as mitigation |
| 3 | Elevated bypass escapes rollback | Open — needs the user's call, hatch kept |

**Still open:** one line each, or "nothing".
**Unverified:** anything changed after the final round, or "nothing".
**Accepted risks:** one line each, or "nothing".
```

One row per *topic*, not per finding — three rounds arguing the same rule is one row. Resolution
is `Fixed — <what changed>`, `Open — <why>`, or `Rejected — <evidence>`. No round numbers, no
finding ids, no Codex quotes. The full per-round record, with Codex's raw final message at a
deadlock, stays in the run log for whoever needs to reopen a decision.

## References

- [codec-loop.md](references/codec-loop.md) — failure playbook, recovery, mechanics
- [review-output.schema.json](references/review-output.schema.json) — the contract
- `references/review-prompt.md` — the adversarial charge sent to Codex
- [troubleshooting.md](references/troubleshooting.md) — Windows sandbox ACL fix, model-slug and old-CLI errors, stale broker
