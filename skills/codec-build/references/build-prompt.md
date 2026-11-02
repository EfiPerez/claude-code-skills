# The work-order contract

Fill every field. The builder starts with **zero session context** — anything not in this file does not exist as far as it is concerned. Write it to a file and pass the absolute path; never inline it into the command (codec-loop.md §5e).

```
GOAL
  <one paragraph: what "done" looks like, in observable terms>

SPEC
  Read <ABSOLUTE PATH TO SPEC_FILE>. It is a frozen, already-reviewed spec.
  Implement it exactly. If a step is impossible as written, implement the closest
  faithful version and REPORT THE DEVIATION — do not redesign.

KEY PATHS
  <files and directories you will touch, or must read first>

CONSTRAINTS
  <"do not touch X", style rules to match, dependencies that must not change>
  Follow the conventions already present in the surrounding code rather than
  introducing new ones.

NON-GOALS
  <explicitly out of scope — from the spec's "Out of scope" section>

TASKS  (numbered, one file per task where possible)
  1. <file> — <what and why>
  2. <file> — <what and why>
  ...

PROOF
  Run `<PROOF_CMD>` and include its full output in your report.

OUTPUT
  End your report with a JSON manifest, fenced, exactly:
  {
    "files_touched":   [{"path": "<repo-relative>", "what": "<one line>"}],
    "tasks_completed": [1, 2, 3],
    "deviations":      [{"task": 2, "why": "<one line>"}]
  }
```

## Why the manifest is mandatory

It is the arbiter's check against the failure mode delegation actually has: **silently dropping tasks.** Diff `tasks_completed` against the numbered TASKS list, and every `files_touched` path against `project_root`. A task missing from the manifest is a finding, not an oversight to be discovered later.

In Mode 1 this is the only structured signal you get at all — a Sonnet subagent returns prose, not a patch — so without it there is nothing to reconcile against the spec.

## Fix-list rounds

Same discipline, smaller shape. One entry per problem:

```
FIX <n>
  PROBLEM  <what is wrong, concretely>
  FILE     <path:line>
  EXPECTED <what correct behaviour looks like>
  PROOF    <how to demonstrate it is fixed>
```

Never send "address the review findings" — the builder cannot see the review, and a vague fix list produces a vague diff. Include only findings you **accepted**; a rejected finding must not appear, or you are asking for a change you already judged wrong.

## Notes

**No `--output-schema` on build rounds.** A build's deliverable is a diff plus a prose report, so there is no verdict object. Applying the review verdict ladder to it parses as `unparsed`, triggers a pointless re-ask, and halts a build that actually succeeded. Use the §8 completion conditions instead.

**Codex has a native image-generation tool** in `codex exec` sessions (ChatGPT-account backed, no API key). Specs may therefore include "generate these image assets yourself" — name exact file paths, dimensions and style in the contract if so.

**The empty-diff trap.** If the builder reports success and the application diff is empty, the cause is almost always `cwd_root` pointing at a staging directory instead of `project_root` (codec-loop.md §1). Check that before believing the spec was a no-op.
