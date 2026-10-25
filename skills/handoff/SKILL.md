---
name: handoff
description: >
  Compresses the current session's context, progress, and next steps into a
  Markdown file in the project's handoffs/ folder, so a future Claude Code
  session can resume exactly where this one stopped.

  Trigger this skill whenever the user types /handoff, or says "write a
  handoff", "hand off to the next session", "save the session context", "save
  where we left off", "I'm running out of context", "context is running low",
  "I'll continue this tomorrow", "dump the state so I can resume", "session
  handoff", or any variation of wanting the current session's state preserved
  for later. Also trigger when the user is clearly stopping mid-task and wants
  to come back to it.

  Do NOT trigger on "we're done", "wrap up the session", or "that's it for
  today" — those belong to the `done` skill, which closes out finished work.
---

## Run without pausing

Invoking this skill is the user's request to run every step below — reading
files, running git and shell commands, creating the `handoffs/` folder, writing
the handoff document, and appending to `.gitignore`. Run the whole skill start
to finish without stopping to ask questions: not about the destination, not
about the filename, not about what to include. If something is ambiguous, make
the sensible call and note it in the document rather than stopping to ask.
Claude Code's own permission settings still apply: if a tool call needs
approval under those settings, the harness will prompt for it.

## What this skill does

A session ends and everything that made it productive — why a path was chosen,
what was already tried and failed, which file you were halfway through editing —
disappears with the context window. The handoff is a letter to the next session.

The bar to aim for: a fresh Claude, with no memory of this conversation, reads
the file and can continue the work without asking the user a single "wait, what
were we doing?" question. Anything that fails that bar is worth writing down;
anything the next session can trivially derive by reading the code is not.

## Step 1 — Check the trigger message for an inline open task

The message that triggered this skill sometimes carries more than the trigger
itself — e.g. `/handoff add task: test the CSV export` or `/handoff — also
note we still need to update the README`. Scan the *exact message
that invoked /handoff* (not the whole conversation) for a marker phrase —
"add task", "open task", "also add", "note task" — case-insensitive. Everything
after the marker, up to the end of the message or the next marker if more than
one appears, becomes one open-task entry.

These are **separate from Next Steps**: Next Steps continue the interrupted
work itself; an inline open task is a distinct ask that surfaced but was never
started (e.g. "also test X" while you were mid-way through Y). Keep them in
their own list, captured for Step 5's Open Tasks section. If no marker is
present, there is nothing to capture — don't invent a task from context.

## Step 2 — Reconstruct what actually happened

Figure out what changed, in this order:

1. **Git repo** — `git status`, `git diff HEAD` (or `git diff` if nothing is
   staged), and `git log --oneline -10`.
2. **No git** — look at recently modified files, e.g.
   - macOS / Linux / Git Bash:
     `find . -type f -mmin -720 -not -path '*/node_modules/*' -not -path '*/.git/*' | head -30`
   - Windows PowerShell:
     `Get-ChildItem -Recurse -File -Include *.js,*.py,*.md,*.html,*.json | Where-Object { $_.LastWriteTime -gt (Get-Date).AddHours(-12) -and $_.FullName -notmatch 'node_modules|\.git' } | Sort-Object LastWriteTime -Descending | Select-Object -First 30`
3. **Conversation context** — if neither is conclusive, rely on what you know
   from this session.

Git and the filesystem tell you *what* changed. They can't tell you the things
that only exist in this conversation, and those are usually the most valuable
part of the handoff:

- Decisions made, and — just as important — **options considered and rejected**,
  with the reason. Without this the next session cheerfully re-proposes the idea
  the user already turned down.
- Dead ends already tried, so nobody pays for the same mistake twice.
- The exact stopping point: not "working on auth" but "`validateToken()` in
  [middleware/auth.js](middleware/auth.js) returns the decoded payload, but
  nothing calls it yet — the route wiring in `routes/api.js` is untouched."
- Anything the user said about constraints, preferences, or environment.

## Step 3 — Destination

Always the current working directory: `<cwd>/handoffs/`. Create the folder if it
doesn't exist. Don't ask, don't search for a "better" project root — predictable
beats clever, and the user can move the file if they want it elsewhere.

## Step 4 — Name the file

Format: `YYYY-MM-DD_HH-<1-3-word-topic>.md` — date, hour (no minutes), and a
short lowercase kebab-case topic.

```
2026-08-11_10-auth-middleware.md
2026-08-11_15-csv-export.md
```

Get the real timestamp from the system rather than guessing:
`date +%Y-%m-%d_%H` (macOS / Linux / Git Bash) or
`Get-Date -Format "yyyy-MM-dd_HH"` (Windows PowerShell). If that exact filename
already exists, append `-2`, `-3`, and so on — never overwrite an existing
handoff, since the one on disk may be the only surviving record of an earlier
session.

The ISO ordering here is deliberate: it makes the newest handoff the one that
sorts last, which is how `resume-handoff` finds it. Keep the filename in this
format even if the user prefers another date format elsewhere. The
**Date & Time** line *inside* the document can follow the user's preferred
date format (check CLAUDE.md for a date convention); default to
`YYYY-MM-DD HH:MM` if none is set.

## Step 5 — Write the document

The `**Handoff-Status:**` line directly under the H1 is a machine-readable
lifecycle marker: `open` here, `resumed <date time>` once `resume-handoff` loads
it, and `complete <date time>` if your end-of-session step marks the work
finished. A script can read it, for example to move completed handoffs into
`archive/handoffs/`. Always write it exactly as `open` — never invent another
value.

Use this structure. The next session (and the `resume-handoff` skill) looks for
these headings by name, so keep them as-is even when a section is thin:

```markdown
# Session Handoff: [Brief Topic]
**Handoff-Status:** open
**Date & Time:** [YYYY-MM-DD HH:MM, or the user's preferred date format]

## 🎯 Goal
[1-2 sentences on the ultimate aim of the feature/project being worked on]

## 🛑 Constraints & Environment
[Specific rules, active constraints, architectural decisions, environment
quirks. e.g. "React 18 strict mode"]

## 📝 Current State
**✅ Completed:**
- [Specific task — include file paths and config changes]
- [Specific task]

**🚧 In Progress:**
- [Exact state of the current unfinished task. If none, write "None."]

## 🧠 Key Learnings & Gotchas
[Crucial context the next session MUST know to avoid repeating mistakes.
e.g. "The API needs the X-Auth header, not Authorization",
"Options A and B were rejected because …"]

## 📂 Files to Review on Resume
[2-4 critical files the next session should read immediately to orient itself]

## ⏭️ Next Steps
[Numbered, highly specific, executable steps. If the work is finished,
write exactly: "There are no next steps."]

## 📌 Open Tasks
[Only include this heading when at least one task was captured in Step 1 —
one bullet per task, in the user's own words. Omit the entire section,
heading included, when there are none. These are asks that came up but
haven't been started yet — not a restatement of Next Steps.]
```

**Be relentlessly specific.** A vague handoff is worse than none, because it
looks like context while carrying none. Name exact file paths (as clickable
relative markdown links, e.g. `[server.js](server.js)` or
`[auth.js:42](middleware/auth.js#L42)`), exact function and variable names, and
exact commands including their flags. Phrases like "fixed the bug", "cleaned
things up", "various changes", or "refactored some code" carry no information —
if you catch yourself writing one, replace it with what actually happened.

**Example — In Progress**

Weak: `Working on the login fix.`

Strong: `Rewrote validateToken() in [middleware/auth.js](middleware/auth.js) to
return the decoded payload instead of a boolean. The three call sites in
[routes/api.js](routes/api.js) still expect a boolean and will silently treat
the payload object as truthy — they have NOT been updated yet. Start there.`

**Example — Next Steps**

Weak: `1. Finish the auth work. 2. Test it.`

Strong: `1. Update the three validateToken() call sites in
[routes/api.js](routes/api.js) (lines 22, 48, 91) to read req.user from the
returned payload. 2. Run npm test -- auth.test.js; the "rejects expired token"
case is expected to fail until step 1 lands.`

**Never write "wait for the user's go" as a Next Step, Goal or Constraint.**
Running `/resume-handoff` *is* the go, so a wait step makes the next session
stall for approval the user already gave. If the work is a plan or design the
user hasn't signed off yet, record that as state ("design reviewed, nothing
built yet") and make step 1 the first real build action. Real gates (push,
deploy, delete, spending budget the user said is exhausted) are still worth
naming — on the step they guard, not as a blanket wait.

If the "Files to Review on Resume" list would be more than four files, you're
probably listing everything you touched rather than the few files that *orient*
someone. Pick the ones that explain the shape of the work.

## Step 6 — Secret hygiene, then write

Before writing, check what you're about to commit to disk. A handoff is a plain
file that may get synced, zipped, or committed, so it should never contain:

- API keys, tokens, passwords, connection strings, or service-account JSON —
  refer to them by name and location instead ("the service-account key at
  `config/service-account.json`", "the value of `API_KEY_PATH`").
- Personal data — customer or employee names, salaries, IDs. Describe the query
  or the shape of the data, not the rows.

Then write the file. Afterwards, if the project is a git repo (`.git` exists),
make sure `handoffs/` is listed in `.gitignore` — append it under a
`# Session handoffs` comment if missing, and do nothing if it's already there.
Handoffs are personal working notes and rarely belong in a shared repo.

## Step 7 — Confirm

Report in five lines or fewer — what was written, where, and how to load it:

```
Handoff saved → [handoffs/2026-08-11_10-auth-middleware.md](handoffs/2026-08-11_10-auth-middleware.md)
Topic: JWT middleware refactor — 3 call sites still to update
Next session: say "resume the handoff" (runs the resume-handoff skill), or "read the newest file in handoffs/ and continue"
```

Add a fourth line only if something genuinely needs flagging (e.g. "Added
`handoffs/` to .gitignore", or "Captured 1 open task: test the CSV export" if
Step 1 found one). Don't restate the document's contents — the whole point is
that they're in the file.

## Relationship to the `done` skill

These are complementary and shouldn't be confused (`done` is a separate skill
in the same marketplace — this skill works fine without it):

| | `done` | `handoff` |
|---|---|---|
| For | Work that's **finished** | Work that's **unfinished** |
| Does | Updates CLAUDE.md, runs tests, commits and pushes | Writes one Markdown file |
| Output | Printed in chat | A file in `handoffs/` |

Running both is fine and the order doesn't matter. When the user asks only for a
handoff, don't run `done`'s commit and push machinery — writing a file is the
entire job here.
