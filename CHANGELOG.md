# Changelog

## [codec-loop 1.1.0] - 2026-11-04
### Added
- `codec-review` - works with the new `plan-review` mod (`EfiPerez/claude-code-mods`): when the mod starts a review of an approved plan, `codec-review` keeps the mod's review record up to date with the bundled `scripts/plan-record.mjs` (renews its lease every round, marks the plan `reviewed` at the end, removes it on abort), so an unchanged plan is not reviewed twice. Without the mod nothing changes
### Changed
- README - recommends the `plan-review` mod as an optional companion

## [codec-loop 1.0.0] - 2026-11-01
### Added
- `codec-loop` - two skills installed together: `codec-review` runs a bounded adversarial review loop between Claude and OpenAI Codex over a plan, document or codebase (Codex critiques read-only, Claude judges and rewrites, one Codex thread, 5-round cap); `codec-build` hands a frozen spec to a second model to implement and runs a bounded review-and-fix loop over the diff, with a clean-tree or snapshot gate and a commit gate. Works on Windows (PowerShell) and macOS/Linux (bash; macOS untested). Needs the Codex CLI and `codex login`; without them, both skills offer an opt-in same-family mode (a different Claude model as critic — weaker, still independent). See the README prerequisites and Privacy section
- `codec-review` bundles `references/codec-loop.md` (shared mechanics and failure playbook), `references/review-output.schema.json` and `references/troubleshooting.md`; `codec-build` links to them
- `NOTICE` and `LICENSES/Apache-2.0.txt`: the loop design is adapted from `chaseai-yt/claudex-loop` (MIT), and two reference files are derived from the OpenAI Codex plugin (Apache-2.0, modified)

## [session-handoff 1.2.0] - 2026-11-01
### Changed
- `handoff` - now always writes to the session's project folder, never into the global `~/.claude` folder (the shell's current directory can drift there after a `cd`)

## [done 1.1.0] - 2026-10-21
### Added
- `done` - creates a git repository for a new project folder: a deny-by-default `.gitignore` (`assets/gitignore-baseline`) and a secret/PII check (`scripts/first-commit-check.sh`) that must pass before the first commit; adds a remote only if your CLAUDE.md defines a convention for it
- `done` - marks the handoff this session resumed as `complete` (pairs with `session-handoff` 1.1.0)
### Changed
- `done` - stages only the files this session changed (never `git add -A` in an existing repo), covers every repository the session edited, and reports what it left unstaged

## [session-handoff 1.1.0] - 2026-10-21
### Added
- `handoff` - new `**Handoff-Status:** open` line under the title, a machine-readable lifecycle marker (`open` → `resumed` → `complete`) that scripts can use, for example to archive finished handoffs
- `resume-handoff` - marks the loaded handoff `resumed <date time>`, and looks in `archive/handoffs/` for a newer or named handoff (moving it back before use)
### Changed
- `handoff` no longer writes "wait for the user's go" as a step; `resume-handoff` treats such a step as already satisfied and starts the first real step

## [1.1.0] - 2026-10-13
### Added
- `session-handoff` - two skills installed together: `handoff` writes the current session's goal, state, gotchas and next steps to a `handoffs/` Markdown file; `resume-handoff` loads the newest one in a fresh session, checks it against the current code, and continues the work

## [1.0.0] - 2026-10-11
### Added
- Initial publish: `done` - end-of-session wrap-up (change detection, CLAUDE.md gotcha updates, tests, commit and push, status report)
