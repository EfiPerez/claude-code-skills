---
name: resume-handoff
description: >
  Loads the most recent session handoff document from the project's handoffs/
  folder, reads the files it points at, checks whether anything has changed
  since it was written, and reports where the last session stopped so work can
  continue seamlessly.

  Trigger this skill whenever the user types /resume-handoff, or says "resume
  the handoff", "load the last handoff", "read the handoff", "pick up where we
  left off", "continue from yesterday", "continue where the last session
  stopped", "what were we working on", "restore the session context", or any
  variation of wanting a previous session's context restored at the start of a
  new one. Also trigger at the start of a session when the user refers to prior
  work as if you should already know about it.

  This is the read side of the `handoff` skill — use `handoff` to write one.
---

## Run without pausing

Invoking this skill is the user's request to read the handoff folder and its
files, read the source files the handoff points at, run read-only git
commands (`git log`, `git status`), and edit the loaded handoff's
`**Handoff-Status:**` line (Step 1). Run through the skill without stopping to
ask questions. Claude Code's own permission settings still apply: if a tool
call needs approval under those settings, the harness will prompt for it.

After reporting, this skill goes on to start the handoff's first Next Step. See
Step 4.

## What this skill does

A previous session wrote down where it stopped. Your job is to absorb that
state, confirm it's still accurate, and get the user back to productive work in
one short exchange — without them having to re-explain the project.

A handoff is a snapshot, not a live view. It was true when written; the code may
have moved since. Treating it as gospel is how a resume skill quietly sends a
session down a path that no longer exists, so verification is a real step here,
not a formality.

## Step 1 — Find the handoff

Look for a `handoffs/` folder in the current working directory. If there isn't
one, check one level up before concluding there's nothing to load.

Pick the file:

- If the user named a file, date, or topic ("load the auth one", "yesterday's
  handoff"), match it.
- Otherwise take the **newest by filename**. Handoffs are named
  `YYYY-MM-DD_HH-topic.md`, so a plain alphabetical sort puts the newest last —
  no date parsing needed.

Don't ask which file to load. Name the file you picked in your report instead,
so if it's the wrong one the user can see that at a glance and say so.

**Archived handoffs.** If the project moves finished handoffs to
`<project>/archive/handoffs/`, check there too. If that folder holds a file
newer (by filename) than the newest one in `handoffs/` — or the file the user
named is only there — say so and offer it; don't silently fall back to an older
file. If the user chooses an archived handoff, **move it back to `handoffs/`
first** (a same-name file already there → stop and ask, never overwrite), then
continue with it.

**Mark it resumed.** Right after picking the file, set its
`**Handoff-Status:**` line (directly under the H1) to
`**Handoff-Status:** resumed <date time>` using the real time — `date
"+%Y-%m-%d %H:%M"` (macOS / Linux / Git Bash) or `Get-Date -Format
"yyyy-MM-dd HH:mm"` (Windows PowerShell), or the user's preferred date format
if CLAUDE.md sets one. If the line is missing (older files), insert it under the
H1. Change nothing else in the file. Remember this path for the session: an
end-of-session step that marks handoffs `complete` should close exactly this
file and no other.

**If no handoffs folder or no files exist**, say so in one line and stop — don't
invent context or guess at what the last session was doing:

```
No handoffs found in this project. To create one, run /handoff at the end of a session.
```

## Step 2 — Read it, and read what it points at

Read the handoff document, then immediately read every file listed under
**📂 Files to Review on Resume**. Reading the pointers is what separates being
*oriented* from merely being *informed* — the handoff tells you the shape of the
work, the files tell you the current truth of it.

If a listed file no longer exists at that path, note it for Step 3 rather than
hunting for it silently.

## Step 3 — Check whether it's still true

Confirm the snapshot still matches reality:

- **Git** — `git log --oneline -10` and `git status`. Have there been commits
  since the handoff's timestamp? Is the working tree dirty in ways the handoff
  doesn't mention?
- **Files** — did every file the handoff references survive, and do the
  functions or line ranges it calls out still exist? (Line numbers drift easily;
  treat a shifted line number as normal, a missing function as drift.)

Anything that no longer holds gets flagged in the report. A handoff that's
entirely still accurate needs no commentary — say nothing rather than padding
the report with "everything checks out" for each item.

## Step 4 — Report, then proceed

Six lines or fewer (seven if the handoff carries an Open Tasks section). The
user is at the start of a session and wants orientation, not a re-read of the
document they can open themselves:

```
Loaded [handoffs/2026-08-11_10-auth-middleware.md](handoffs/2026-08-11_10-auth-middleware.md) — 2026-08-11
Goal: move JWT validation into shared middleware so all API routes verify tokens the same way.
Stopped at: validateToken() returns the decoded payload, but the 3 call sites in routes/api.js still expect a boolean.
Since then: 2 commits touched routes/api.js — line numbers in the handoff have shifted.
Next step: update the 3 call sites to read req.user from the payload. Starting now.
Open tasks: test the CSV export.
```

Dates in the report follow the user's preferred date format (check CLAUDE.md
for a date convention); default to `YYYY-MM-DD` if none is set. Drop the "Since
then" line entirely when nothing has drifted, and drop the "Open tasks" line
entirely when the handoff has no **📌 Open Tasks** section — don't print
"none".

**Then start the work — don't ask.** Running this skill is itself the go-ahead,
so begin the handoff's first Next Step straight after the report. Never end the
report with "Want me to start there?". Only pause if the drift in Step 3 makes
the Next Step unsafe or meaningless (for example the file it targets is gone),
and say why in one line. A handoff whose Next Steps or Goal say "wait for the
user's go" / "don't build until they say go" is already satisfied: running this
skill is that go, so skip the wait step and start the first real one. Next Steps
that are irreversible or outward-facing
(push, deploy, delete) still follow the normal confirmation rules; the go-ahead
covers starting, not those.
