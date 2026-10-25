# Changelog

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
