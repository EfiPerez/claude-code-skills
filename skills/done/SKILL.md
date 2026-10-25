---
name: done
description: >
  End-of-session wrap-up skill. Run at the end of every working session to:
  summarize what changed, update any affected CLAUDE.md sections, run the
  project's test suite (if one exists), commit and push to git, and print a
  final status report.

  Trigger this skill whenever the user types /done, says "wrap up the session",
  "end of session", "let's close out", "finish up", "session summary", or any
  variation of wanting a structured close-out after completing work. Also trigger
  if the user says "we're done" or "that's it for today" in the context of
  finishing a coding session.
---

## Run without pausing

Invoking this skill is the user's request to run every step below — reading files, running shell commands (git, PowerShell, Bash), and writing/editing CLAUDE.md. Execute every step without stopping to ask for confirmation. Claude Code's own permission settings still apply: if a tool call needs approval under those settings, the harness will prompt for it.


## What this skill does

You're closing out a working session. The goal is to leave the project in a
clean, well-documented state: capture what happened, update the docs that
describe the project so a future session picks up with full context, confirm
tests still pass, and report a crisp summary.

## Step 1 — Detect what changed this session

First, figure out what actually happened. Check in order:

1. **Git repo** — run `git status` and `git diff HEAD` (or `git diff` if
   nothing is staged). Also run `git log --oneline -10` to see recent commits.
2. **No git** — look at files with recent modification times:
   Bash: `find . -type f -newer /dev/null -not -path '*/node_modules/*' -not -path '*/.git/*' -printf '%T+ %p\n' 2>/dev/null | sort -r | head -40`
   (If `printf` fails, fall back to: `ls -lt --time-style=full-iso *.html *.js *.py *.md 2>/dev/null | head -20`)
3. **Conversation context** — use what you know from this session if neither
   of the above is conclusive.

From this, produce a short internal change list (you'll use it in Steps 2–5):
- Which files were created or modified
- What the overall purpose of the session was (feature, bugfix, config, docs)
- Any architectural or behavioral changes worth documenting

## Step 2 — Update CLAUDE.md

Open the project-level `CLAUDE.md` (in the current working directory) and the
global `~/.claude/CLAUDE.md`. For each, ask: do the changes from Step 1 affect
any documented section?

The bar for writing a line into CLAUDE.md is **"would a future session get this
wrong if the line weren't there?"** Per Anthropic's [context-engineering rules
for Claude 5 models](https://claude.com/blog/the-new-rules-of-context-engineering-for-claude-5-generation-models),
CLAUDE.md should stay lightweight and spend most of its tokens on *gotchas*.
Claude 5 recovers structure from the filesystem reliably, so anything derivable
by listing a directory, reading `package.json`, or grepping the source is
context cost with no return — and the built-in `/doctor` checkup will strip it
out later anyway.

Update only if one of these is true:
- A **pitfall or gotcha** was discovered that would bite a future session —
  especially one that already cost time this session
- A **rationale** was established: why the code is this way, and what breaks if
  someone "fixes" it
- A **convention that differs from the tool's default** was adopted
- A build / test / run command changed
- A security, auth, or data-handling rule changed
- An integration's contract changed (how another system must be called, not
  which package was installed)

Do **not** update CLAUDE.md for:
- Anything derivable from the codebase — file inventories, directory layouts,
  dependency lists, route inventories, "architecture overview" narration
- Routine feature additions that are self-evident from the code
- Bug fixes with no architectural impact
- Things already documented

A concrete version of the distinction: "added `ws` to dependencies" is
derivable — skip it. "The WebSocket server shares the same `http.Server` as
Express, so changing the port in one place moves both" is a gotcha — write it.
When a change produced both, write only the gotcha.

If you make any changes, note exactly which file and which section was updated.
If no changes are needed, say so explicitly — don't skip it silently.

### Step 2a — Decide where the content goes: cut, keep, or load on demand

Content that passed Step 2 is real knowledge. Now decide where it lives. The
test is **not** file length — it's whether a future session needs this on a
typical task, or only when working on that one narrow feature.

- **Ask:** would a session working on an unrelated part of this project ever need this fact to avoid a mistake, or is it only relevant to someone specifically touching the feature/section this change belongs to?
- **Keep in CLAUDE.md** — pitfalls, rationale, and conventions that differ from tool defaults; security/auth gates; data rules; cross-cutting gotchas (anything that could bite unrelated work); build/test/run commands; and anything genuinely referenced from multiple places in the codebase. Note the shift from the older phrasing: architecture *rationale* ("the terminal and API share one `http.Server`, so…") stays, but an architecture *overview* that just narrates the file layout is derivable and should have been dropped back in Step 2.
- **Relocate so it loads on demand** — deep implementation detail scoped to one narrow feature, tile, routine, or endpoint that only gets touched on its own dedicated task (e.g. "how the PDF export button formats page breaks," "the full history of one specific data-check's edge cases," "Dockerfile/deploy-zip build gotchas"). If it's the kind of detail you'd only look up when someone says "fix X" for that specific X, relocate it.
- If genuinely unsure whether something is narrow or cross-cutting, default to keeping it in CLAUDE.md — moving a cross-cutting gotcha out is the costlier mistake (it gets missed on unrelated tasks), not the safer default. This tie-break applies to *where a real gotcha lives*, not to whether derivable content survives — for that, Step 2 already says drop it.
- Don't force existing, already-appropriate CLAUDE.md content into a reference doc just because the file is long. Only relocate content this session actually added or is directly touching. A full rightsizing pass is a separate, explicit task — e.g. the built-in `/doctor` checkup — not something `/done` does on every run.

**Where to relocate — prefer the highest rung that fits.** The point is for the
harness to load the content automatically when it becomes relevant, rather than
relying on a session noticing a pointer:

1. **A skill** (`~/.claude/skills/<name>/SKILL.md`) — the content is a multi-step *procedure*, not a fact. Split a long one across several files in the skill folder instead of one wall of text.
2. **A path-scoped rule** (`<project>/.claude/rules/<topic>.md` with `paths:` frontmatter globs) — the content is a convention or constraint tied to specific files or directories. It loads only when Claude reads a matching file.
3. **A nested `CLAUDE.md`** in the subdirectory the content is about — loads on demand when Claude reads files in that subtree. Caveat: nested files are not re-injected after `/compact`, so don't use this for anything that must survive a long session.
4. **`docs/X.md` + a pointer** — a common convention, and the right fallback for narrative reference material that's neither a procedure nor path-scoped (e.g. `docs/DEPLOYMENT.md`, `docs/INTEGRATIONS.md`). Reuse an existing one if the topic fits; otherwise name a new one after the feature.

When moving content out: write the full detail to the target, and leave a short paragraph or bullet list in CLAUDE.md — enough for a session to know the feature exists and get the one-sentence gist — ending with a pointer like "See `docs/X.md` for full detail." Never use an `@path` import for this: imports are expanded at launch, so they organize content without saving any context.

**If you create or edit a `.claude/rules/*.md`, resolve every `paths:` glob before you finish.** A glob matching zero files (a typo, or a path that has since been renamed) means the rule never loads and the content you just relocated is silently gone — worse than having left it in CLAUDE.md, because nothing ever surfaces the failure. Check each pattern against the filesystem and confirm it matches at least one real file. Same applies to a rule you didn't write but whose files this session renamed or moved: renaming a file out from under a glob is an easy way to kill a rule without touching it. Don't leave a known-dead glob behind for a later audit to find.

## Step 3 — Run tests

Detect the test framework and run it. Check in this order:

| Indicator | Command |
|---|---|
| `pytest.ini`, `pyproject.toml` with `[tool.pytest]`, or `tests/` dir with `.py` files | `pytest` |
| `package.json` with a `"test"` script | `npm test` (use `call npm test` in bat context) |
| `package.json` with a `"test:run"` or `"vitest"` script | `npm run test:run` |
| `Makefile` with a `test` target | `make test` |
| No tests found | Skip and note "No test suite detected" |

Capture the output. Report:
- Pass / fail count if the framework shows it
- Any failing test names and their error summary (first line of the error)
- If the test command itself errors (e.g., missing dependency, config error), report the error output verbatim — do not swallow it as "No test suite detected"
- If tests were skipped due to no suite being found

Do not fix failing tests here — just report them so the user knows what to
address next session.

## Step 3a — Close the resumed handoff

If **this same conversation** loaded a handoff with `/resume-handoff` (the
`session-handoff` plugin), set that file's `**Handoff-Status:**` line (directly
under the H1) to `**Handoff-Status:** complete <date time>` with the real time —
`date "+%Y-%m-%d %H:%M"` (macOS / Linux / Git Bash) or `Get-Date -Format
"yyyy-MM-dd HH:mm"` (Windows PowerShell), or the user's preferred date format if
CLAUDE.md sets one. Insert the line under the H1 if it is missing. Change
nothing else in the file. If the file has moved (an archiving script may have
moved it), skip it and say so in the report.

Close **only** the path(s) this conversation itself resumed — you know them from
your own context. There is no fallback: a session that did not resume a handoff
marks none complete, not even the newest one, so one session's `/done` can never
close another session's handoff. A script can then move `complete` handoffs into
`archive/handoffs/`.

## Step 4 — Git commit and push

**Commit only the files this session changed — never `git add -A` or `git add .`**
Several sessions often share one working tree, so a blanket add sweeps another
session's unsaved work into this commit. Use the Step 1 change list
cross-checked against what this conversation actually edited; a modified file
you didn't touch stays unstaged and is named in the report.

Do this for **every repository this session edited files in**, not only the
current directory's — a session in one project can still have changed
`~/.claude` or another project. For each:

1. **No `.git` folder** — if it is a new project folder, create the repository
   with Step 4a, then continue with item 2. Otherwise skip it and note "No git
   repository".
2. **`.git` exists** — run `git status --porcelain` to check for uncommitted changes.
   - **None of this session's files are modified** — note "Git: nothing to commit". Still run `git push` in case earlier commits were never pushed.
   - **This session's files are modified** — do all three in order:
     1. `git add -- <each file this session changed>`, then `git diff --cached --stat` to confirm nothing else is staged
     2. `git commit -m "<message>"` — derive the message from the session summary in Step 1. Use the format: `"<verb> <what>  — session wrap-up"` (e.g. `"Add weekly compliance chart — session wrap-up"`). Keep it under 72 characters.
     3. `git push`

Report the outcome:
- `Git: ✓ committed "<message>" and pushed` — on success
- `Git: ✓ nothing to commit — pushed` — if only a push was needed
- `Git: ✗ push failed — <error>` — if push errors (show the error)
- `Git: skipped — no repository` — if no `.git` folder
- `Left unstaged: <files>` — other changes in the tree this session didn't make

### Step 4a — Create a repository for a new project

A new project folder with no git yet gets a repository, a deny-by-default
`.gitignore`, and a first commit that has passed a secret check.

**Create one only when all of these hold** — otherwise skip and note why:
- The folder is a single project's root folder: the session's working
  directory, or another project folder this session edited. Never the home
  folder, the Desktop, a folder that holds several projects, or a synced or
  network drive.
- `git -C <folder> rev-parse --is-inside-work-tree` fails (not already inside a repo).
- No subfolder has its own `.git` — a folder that *contains* repos must never
  become one.
- There is no `.nogit` file in the folder. That file is the user's opt-out for
  scratch folders; respect it silently.
- This session changed files in it.

**Steps, in order — never skip the safety check:**
1. **`.gitignore`** — if none exists, copy `assets/gitignore-baseline` (in this
   skill's folder) to `<folder>/.gitignore`. If one exists, append only the
   baseline lines it is missing; never remove a line.
2. **Init** — `git init` (uses the user's configured default branch).
3. **Stage** — `git add -A` is correct *here only*: the repo is brand new, so
   every file is the project's first version.
4. **Safety check before the first commit** — run
   `bash <this skill's folder>/scripts/first-commit-check.sh "<folder>"` (on
   Windows, from Git Bash). It prints one `<reason>\t<path>` line per staged
   file that must stay out: spreadsheets, CSVs, databases, key and credential
   files; non-code files whose name says key/secret/token/credential/password/
   snapshot/employee/salary/payroll; anything over 5 MB; and any file whose
   content looks like a key or password. For each line:
   `git rm --cached -- "<path>"` and add the path to `.gitignore`. Then
   `git add .gitignore` and re-run the script until it prints nothing **and
   exits 0**. A non-zero exit means the check itself failed: do not commit —
   report the error and leave the repo uncommitted. Report removed files by
   name only — never open or print their contents.
5. **Commit** — `"Initial commit — <project> — session wrap-up"`.
6. **Remote** — only if the user's CLAUDE.md defines where new projects get
   their remote (for example a local bare repo per project as a backup):
   follow that convention, then `git push -u origin <branch>`. If the target
   already exists, don't push — it may belong to another project or an old
   copy; report the name clash and leave the repo local. With no convention
   defined, leave the repo local and say so.

Report: `Git: ✓ new repository — <N> files committed[, pushed to <remote>| — local only]`,
plus `Kept out of git: <files>` for anything the safety check removed.

## Step 5 — Final status report

Print a compact, scannable summary using this template:

```
Session wrap-up
───────────────────────────────────────
Changed: <N> files
  • <file1> — <one-line description of what changed>
  • <file2> — <one-line description>
  ...

CLAUDE.md: <"Updated — <which file>, <which section>" | "Updated — <section> (+ <topic> detail → <docs/X.md | skill | .claude/rules/X.md>)" | "No changes needed" | "No changes needed — <what changed> is derivable from the code">


Tests: <"✓ N passed" | "✗ N failed — <test names>" | "No test suite detected">
───────────────────────────────────────
<One sentence summarizing the overall session goal and outcome.>
```

Keep each bullet tight — one line. The user can read the diff for details;
this report is for orientation, not documentation.
