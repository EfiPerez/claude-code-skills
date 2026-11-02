> Derived from the OpenAI Codex plugin's `prompts/adversarial-review.md` (Apache-2.0, Copyright 2026 OpenAI) and modified. See [NOTICE](../../../NOTICE) and [LICENSES/Apache-2.0.txt](../../../LICENSES/Apache-2.0.txt).

# The adversarial charge

Template for the round-1 brief. Adapted from the Codex plugin's `prompts/adversarial-review.md` (role, attack surface, finding bar) and Chase's `codex-review` verdict discipline. Substitute the bracketed parts.

Later rounds do **not** repeat this. They carry the revised target, your per-finding responses, and an instruction to put resolved ids in `settled` — Codex already holds this charge in thread context, and repeating it invites it to re-litigate settled points.

---

```
You are performing an adversarial review of [TARGET DESCRIPTION].

Read, in your working directory:
[FILE LIST — one line each, with a note on which is the primary target]

Your job is to break confidence in this work, not to validate it. Default to skepticism.
Assume it can fail in subtle, high-cost, or user-visible ways until the evidence says otherwise.
Do not give credit for good intent, partial fixes, or likely follow-up work. If something only
works on the happy path, treat that as a real weakness.

CONTEXT you may treat as already verified — do not spend findings re-litigating these:
[VERIFIED FACTS — measured environment claims, so the critique targets reasoning rather than
 re-deriving what has already been tested. Include anything you have empirically proven.]

PRIORITISE these attack surfaces:
- auth, permissions, tenant isolation, and trust boundaries
- data loss, corruption, duplication, and irreversible state changes
- rollback safety, retries, partial failure, and idempotency gaps
- race conditions, ordering assumptions, stale state, and re-entrancy
- empty-state, null, timeout, and degraded-dependency behaviour
- version skew, schema drift, migration hazards, compatibility regressions
- observability gaps that would hide failure or make recovery harder
- ways this reports SUCCESS or CONVERGENCE when it has not actually succeeded
[PLUS anything specific to this target]

METHOD: actively try to disprove it. Look for violated invariants, missing guards, unhandled
failure paths, and assumptions that stop being true under stress. Trace how bad inputs, retries,
concurrent actions, or partially completed operations move through it. Where a claim is made
about the codebase, verify it against the actual files and flag anything that assumes a file,
function, or behaviour that does not exist.

FINDING BAR: report only material findings. No style, naming, or low-value cleanup, and no
speculative concerns without evidence. Every finding must answer:
  1. What can go wrong?  2. Why is this path vulnerable?  3. What is the likely impact?
  4. What one concrete change would reduce the risk?
Cite file:line where you can. Calibrate `confidence` honestly — do not inflate.

Return ONLY a JSON object conforming to the provided output schema.
Use verdict "approved" only if it is sound enough to proceed as written, with an empty findings
array. Do not approve to be agreeable — and do not manufacture a finding to appear rigorous.
```

---

## Notes on why this is shaped this way

**The verified-facts block earns its length.** Without it Codex burns findings re-deriving environment facts already measured, and its confidence numbers on those are meaningless. With it, the critique lands on reasoning.

**"Ways this reports success when it has not succeeded"** is worth keeping in every review of a loop, pipeline, or check. Reviewing this design's own document, two of the most valuable findings were of exactly that shape: a build that reports success while changing nothing, and a completion test satisfied by the run's own log files.

**Never ask for both a `VERDICT:` line and a schema object.** Schema mode returns only JSON, so asking for both guarantees one is violated. The `VERDICT:` regex exists solely as a fallback for when schema mode fails, and per codec-loop.md §7 it may only ever produce `revise` or `unparsed`.

**Settled ids are how the loop converges.** From round 2, always ask Codex to populate `settled`. That is what stops it re-raising resolved points and is the main reason resuming one thread beats a fresh review each round.
