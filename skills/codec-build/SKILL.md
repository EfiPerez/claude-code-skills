---
name: codec-build
description: >-
  Hands a frozen spec to a second model to IMPLEMENT, then runs a bounded review-and-fix loop between Claude and OpenAI Codex over the resulting diff. Claude picks the topology (Codex builds by default; a Sonnet subagent builds when the main context needs protecting), enforces a clean-tree or snapshot gate before any write, and caps fix rounds at 2 before Opus takes over directly. Runs silently: the user is asked only whether to commit, and the output is one report file with a table of topics and how each resolved. Claude writes every commit; Codex never commits. Use when the user says "/codec-build", "have codex build this", "codex implement the plan", "hand this to codex to build", "delegate the build", or right after a plan survives codec-review and they choose to implement it. NOT for tiny edits under ~20 lines where delegation overhead loses, NOT for design work (if writing the spec forces decisions, run codec-review first), and NOT for reviewing existing code without building (that is codec-review).
---

# codec-build — one model types, the other verifies

**If a Codex call fails before any build work starts, re-run Step 0's checks, then read
`../codec-review/references/troubleshooting.md`.** The Windows sandbox/ACL failure and the two
model-slug failures all surface as an identical hard error from Codex's stderr, and that file
is the only place the three are told apart. It does not load by itself.

The role-flip of `codec-review`. There, Claude drafts and Codex critiques read-only. Here a builder writes real code and a reviewer judges the diff like a contributor PR.

**The user is asked exactly one question: commit or not** (plus, only when Codex can't be reached, the Step 0a same-family offer before anything starts). Everything before it — topology, rounds, arbitration — is Claude's call, and none of it is reported mid-run. The commit gate stays because a commit is outward-facing and hard to reverse; refereeing the build is not.

**Build rounds run against the real worktree — this is the one thing to get right.** Build rounds run against the **real worktree** with `cwd_root = project_root`. Staging is a read-scope control for reviews and must never be used here: a build launched with `-C` pointing at a staging directory writes into the staged copy and leaves the project untouched, producing a build that reports success and changes nothing.

[codec-loop.md](../codec-review/references/codec-loop.md) (bundled with `codec-review`) is reference for when something breaks — read §1 (asymmetry) and §8 (build completion) on failure or when changing this skill, not on every run.

Adapted from `chaseai-yt/claudex-loop`'s `codex-build` (MIT — see the repository's `NOTICE`): its spec-as-work-order contract, bounded fix loop, and round reporting. Its `grill-me-codex` / `grill-with-docs-codex` / `claudex-loop` skills are **out of scope**.

**Spec quality decides success.** The builder starts with zero session context — everything it needs must be in the spec file. A plan that survived `codec-review` is the ideal input.

## Which shell

Every command in the loop comes in two forms (the full blocks are in
[codec-loop.md](../codec-review/references/codec-loop.md) §5, §8 and §4). In the **PowerShell
tool (Windows)** use the PowerShell form. In the **Bash tool (macOS or Linux; Git Bash on
Windows also works)** use the bash form. Never mix the two in one call, and re-assign
variables at the top of every call — they and the working directory do not survive between
tool calls. The bash forms use only `bash`, POSIX tools that ship with macOS, `git` and
`node`. They were tested under Git Bash on Windows; macOS itself is untested. Advice marked
**Windows-only** does not apply on macOS or Linux.

## Hard rules

- **Claude writes every commit. Codex never commits.** Commits, pushes, and any GitHub mutation happen Claude-side, after the human gate.
- **Never skip the diff read.** The builder's report is advisory until Claude has read the full diff and run the proof command itself. A pasted proof output is not proof.
- **Arbitrate in the main session, never a subagent.** If you set `CLAUDE_CODE_SUBAGENT_MODEL` (for example to `sonnet`), an "Opus" subagent may silently be a smaller model. The main session is already the stronger model, so judging inline is both correct and free.
- **The fix loop terminates.** After `MAX_FIX_ROUNDS`, Opus finishes directly. No unbounded delegation ping-pong.
- **Never `--yolo`.** It works but is a hidden, undocumented alias. See codec-loop.md §3b for the bypass rules.
- **Run silent.** No per-round status in the conversation. The only interruptions are the finished-build banner in step 4 and the commit gate in step 7.
- **No per-run exposure prompt — but know what this does.** Codex sends whatever it reads to OpenAI, under the user's own account, and in this skill it also **writes** in the real project (`workspace-write`). A sandbox restricts writes, not reads: Codex can read any file the user's account can read — the project's `.env` and data files, and also files elsewhere such as home-directory credentials and global config. Do not raise the topic on every run (the repository README carries the warning), and never describe scope exclusions as enforced. The user should run this skill only on projects and machines where that exposure is acceptable.

## Tunables

| Var | Default | Meaning |
|---|---|---|
| `SPEC_FILE` | asked | The frozen spec to implement. |
| `MAX_FIX_ROUNDS` | `2` | Fix iterations before Opus takes over. Chase's finding: delegation stops paying off past this. |
| `PROOF_CMD` | from spec | The exact test/verify command. If the spec lacks one, ask **one** question to get it before launching. |
| `MODEL` / `EFFORT` | resolved / `high` | Per codec-loop.md §5b. |

---

## Step 0 — Can this app reach Codex?

A one-time setup check per computer, shared with `codec-review`. Codex is needed in both
modes (it builds in Mode 2 and reviews in Mode 1). Stop at the first check that fails: tell the
user in two or three plain sentences what you found and what to do next. Check 1 failing ends
the run. Checks 2–3 failing end it too, unless the user takes the same-family offer in Step 0a.

- **Check 1 is free and always applies** — it only looks at this session's tool list.
- **Checks 2–3 run only when `~/.claude/state/codec/codex-ready.json` is absent.** When both
  pass, write that file (`{"codex_version": "...", "checked": "<ISO date>"}`, creating the
  folder if needed) and continue silently. When it exists, skip them.
- **If any later Codex call fails before build work starts, delete the marker and re-run
  checks 2–3** before reading `../codec-review/references/troubleshooting.md` — a
  since-logged-out or uninstalled Codex must get this plain explanation, not a raw error.
- **Any failed check 2–3 deletes the marker — no exceptions**, even when the cause looks
  temporary or session-specific (a probe kept it once, reasoning "the real setup is probably
  fine"). The marker means "verified working", never "probably fine".

1. **Shell access.** No Bash or PowerShell tool in this session (Claude Desktop's Chat tab,
   claude.ai, mobile) → this skill cannot run here: it drives the Codex command-line program
   on this computer and builds in the real project folder, and this app can reach neither.
   Next step: open the project in Claude Code — the Claude Desktop **Code** tab with a
   **Local** session, a terminal, or VS Code — and run the skill again. If a Codex-looking MCP
   tool is connected, say it isn't used: OpenAI removed the official `codex mcp-server`, and
   the build needs local files anyway.
2. **`codex --version`.** Fails → Codex isn't installed or isn't on PATH. Next step:
   `npm install -g @openai/codex` (needs Node.js), then `codex login`. With the Codex plugin
   for Claude Code installed, `/codex:setup` checks the same things.
3. **`codex login status`.** Non-zero exit / `Not logged in` → Next step: the user runs
   `codex login` in a terminal (it opens a browser; a ChatGPT plan or an API key works). Never
   run `codex login` yourself — it is interactive.

## Step 0a — No Codex connection: offer same-family mode

Same check and same offer as `codec-review` Step 0a
(`../codec-review/SKILL.md`; look for any other usable Codex route — none of the known ones
can build here), worded for a build: *"…or reply **"use Claude"** and a Claude subagent builds
it while a different Claude model reviews the diff. That is weaker than a different AI
company's model checking the work — same-family models share more blind spots — but it is
still a valid, independent review."* No answer or anything but a clear yes → end the run.
**Never switch silently**; never write the `codex-ready.json` marker.

In same-family mode the topology is fixed (no Mode choice):

```
Claude subagent, model "sonnet"   → builds from the spec (Mode 1 contract: closing JSON manifest)
Claude subagent, a different model ("opus"), subagent_type "Plan" (read-only)
                                  → adversarial review of the diff, codec-review Step 0a critic rules
Opus (main)                       → reads the full diff, runs PROOF_CMD, arbitrates
fresh "sonnet" builder subagent   → applies accepted fixes ... up to MAX_FIX_ROUNDS
```

Skip Step 4's `codex login status` re-check. The commit question becomes *"A Claude subagent
built it, a different Claude model reviewed it (no Codex), proof passes, diff reviewed.
Commit?"*, and the report's header names both models and says "same-family mode — weaker than
a cross-vendor review, still independent".

## Step 1 — Topology (Claude decides)

**Default to Mode 2.** It is the more reliable of the two and needs no question. Choose Mode 1
only when the build is large enough that keeping the writing off the main context matters more
than reliability, and say which you picked in the report — do not ask.

**If the user named Codex ("build it with Codex", "have codex build this"), Mode 2 is fixed** — never
switch to Mode 1 for context reasons. Once a user planned a Codex build and got Sonnet agents instead,
which ended the day with untested code.

**Mode 1 — Sonnet builds, Opus judges, Sonnet fixes**

```
Sonnet subagent  → builds from the spec
Codex            → adversarial review of the diff (read-only)
Opus (main)      → judges which findings are legitimate, writes a fix list
Sonnet subagent  → applies the accepted fixes
Codex            → re-reviews          ... up to MAX_FIX_ROUNDS
```

State the caveats honestly when offering it. Subagents share no context, so the spec and the fix list must be **self-contained files passed by absolute path**. They return prose, not a patch, so the arbiter re-derives what changed from the diff. And they can silently drop tasks — mitigated by a numbered one-file-per-task list plus a **required closing JSON manifest** (`files_touched`, `tasks_completed`) that the arbiter diffs against the spec. Mode 2 is the more reliable default; Mode 1 exists to keep the heavy writing off the main context.

**Mode 2 — Codex builds, Opus reviews, fixes ride the same Codex thread**

```
Codex (workspace-write) → builds from the spec
Opus (main, inline)     → reads the full diff, runs PROOF_CMD
Codex (same thread)     → applies the accepted fixes  ... up to MAX_FIX_ROUNDS
```

Opus reviews **inline, not in a subagent** — the arbiter needs the spec, the diff, and every prior round at once, which a subagent gets none of for free. The one legitimate fork is a read-only `Explore` gatherer on a diff of thousands of lines, which condenses and never decides.

## Step 2 — Spec gate

`SPEC_FILE` must exist and read as a work order: goal, concrete steps, bounds. No spec → route to `codec-review` to produce one, or write it *with* the user first. **Do not build from a rough idea** — that is designing by delegation, and it fails.

Fill the work-order contract in `references/build-prompt.md` completely. When chained from `codec-review`, derive it from the converged plan's sections.

## Step 3 — Safety gate (before any write)

Never let a builder write with no way back.

**Git repo:**
1. `git check-ignore adversarial-review` must **succeed**. This is a hard gate, not an offer — excluding the directory from a clean-tree pathspec does nothing to stop a later `git add .` staging briefs and raw model output containing source excerpts, and many Claude Code setups pre-allow `git add` in their settings. If yours does, this gate is the only thing between those files and a commit.
2. Clean tree, scoped: `git status --porcelain -- . ':(exclude)adversarial-review'`. Dirty → **stop** and ask the user to commit or stash. Non-negotiable: a dirty tree means the diff cannot be isolated or cleanly reverted. The exclusion matters because this skill's own logs would otherwise dirty the tree and deadlock its own gate by round 2.
3. Record `base_sha`.

**Not a git repo:**
1. Pass `--skip-git-repo-check` — `codex exec` otherwise refuses to run at all.
2. Snapshot **outside the project**: `$env:TEMP\codec-snap-<safe_id>\` (Windows) or `${TMPDIR:-/tmp}/codec-snap-<safe_id>/` (macOS/Linux). A snapshot inside the worktree lands inside its own comparison and can recurse while copying. The bash snapshot, manifest and test-restore commands are in codec-loop.md §4.
3. Write a per-file SHA-256 manifest, and **verify a test restore** into a scratch directory before treating it as a rollback base. An unverified snapshot is not a rollback plan.

Then go. No scope statement, no round-by-round approvals; the gate is at the end.

## Step 4 — Build

**Re-run `codex login status` right before launching any builder** — this step and every Step 6
fix round, in either mode, whatever the Step 0 marker says. Non-zero → delete the marker, give
Step 0's check-3 explanation, and stop before anything writes. The marker cannot cover this: in
Mode 1 Sonnet edits the real worktree before Codex's first call, so a since-logged-out Codex would
leave changes nobody can review.

- **Mode 2:** launch per codec-loop.md §5d (PowerShell and bash forms) — `-s workspace-write`, `cwd_root = project_root`, no `--output-schema`. Capture the thread UUID; persist state before launching.
- **Mode 1:** `Agent` tool with `model: "sonnet"`, handed the absolute spec path. Require the closing JSON manifest.

Backgrounded rounds are the default. When one finishes, the **first line** of your next message must be a standalone banner — `🔔 CODEX FINISHED — <what> (exit ok/fail) — verifying now` — before any verification output. The user is not watching tool calls; never let a completed build slide silently into the verify phase.

## Step 5 — Verify completion, then review

Check the five **build completion** conditions in codec-loop.md §8 — *not* the review verdict ladder, which expects a schema object a build never produces.

The condition that matters most: **at least one changed application file**, computed with the run's own artifacts excluded. Briefs, JSONL, exit files and the run log all live inside the worktree and change on every attempt, so an unscoped diff reports changes even when the builder touched nothing. An empty application diff is the exact symptom of the staging misconfiguration in §1.

Then review properly:

1. Read the **full diff**. Judge it like a contributor PR: correctness, spec fidelity, style match with surrounding code, nothing touched outside scope.
2. Run `PROOF_CMD` **yourself**.
3. Append to the run log: the builder's report summary, then your verdict with what passed and what failed, per-finding.

**Completion is not acceptance.** It only means the round produced something reviewable.

## Step 6 — Fix loop (`MAX_FIX_ROUNDS = 2`)

**Snapshot before *each* fix round, not once** — otherwise round 2 has no clean base to return to.

Write the fix list to a file with the same contract discipline as the spec: exact problem, exact file, expected proof. Mode 2 sends it through the same Codex thread; Mode 1 hands it to a fresh Sonnet subagent by absolute path.

Arbitrate every finding with `accepted` / `rejected` / `deferred` / `escalated` and a one-line reason. **A rejection must cite a `file:line` or a test result.**

After 2 rounds without convergence: **stop delegating.** Opus finishes the remaining fixes directly and logs the takeover — what was left, and why. Ping-ponging trivia through delegation burns more than it saves.

## Step 7 — Human commit gate

Present: a 3-bullet summary of what was built, the files-changed list, the verbatim tail of the proof output with pass/fail, rounds used, any spec deviations, and **any accepted risks that materialised**.

If a bypass round ran, **say so explicitly here** (codec-loop.md §3b). A bypass run is unsandboxed and, on Windows with `[windows] sandbox = "elevated"`, can write outside the project, where nothing appears in this diff and no rollback covers it — so the diff must never be presented as a complete account of what changed.

Then ask: *"Codex built it, proof passes, diff reviewed. Commit?"* — the one question in this
skill.

- Commit **only** on yes, and Claude writes it.
- Rejected → ask what is wrong, route back to step 6, or take over directly if fix rounds are spent.
- **Never** auto-commit, and never let the builder commit.

## Step 8 — The report

Write `~/.claude/reports/<run_id> report.md` (central, not per-project — same reasoning as
`codec-review`'s report) and give the user its path in one line. Same format — a table of topics
and how each resolved, then the short notes — plus the topology used, `PROOF_CMD` and its
result, and whether a bypass round ran. One row per topic, not per finding. No round
numbers, no Codex quotes; those stay in the run log under `<project>/adversarial-review/`.

## Step 9 — Rollback

Git: `git restore` to `base_sha`. Non-git: restore from the verified snapshot manifest. Either way, state what was restored and what was not.

## References

- [codec-loop.md](../codec-review/references/codec-loop.md) — failure playbook and mechanics; §1 asymmetry and §8 build completion are the two that bite
- [troubleshooting.md](../codec-review/references/troubleshooting.md) — Windows sandbox ACL fix, model-slug and old-CLI errors, stale broker
- `references/build-prompt.md` — the work-order contract and the manifest requirement
