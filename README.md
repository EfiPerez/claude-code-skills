# claude-code-skills

Practical Claude Code skills for real workflows, by Efi Perez ([@EfiPerez](https://github.com/EfiPerez)).

## Install

**Option A - plugin marketplace (recommended):**

1. Add the marketplace (once):
   ```
   /plugin marketplace add EfiPerez/claude-code-skills
   ```
   This only registers the catalog - it installs nothing by itself.

2. Install only what you want - each line is one plugin:

   | Plugin | Skills it installs | Install command |
   |---|---|---|
   | `done` | `done` | `/plugin install done@efi-skills` |
   | `session-handoff` | `handoff` + `resume-handoff` (a pair - one writes the handoff, the other reads it) | `/plugin install session-handoff@efi-skills` |

   Or run `/plugin` and browse the marketplace to pick skills from a menu.

One-time marketplace registration; every skill added later needs no new
setup on your side. Third-party marketplace auto-update is **off by
default** - run `/plugin marketplace update` to pull new versions, or turn
on auto-update for this marketplace.

<details>
<summary>Option B - manual copy (no plugin system)</summary>

There is no `claude skill install` command. Download this repo, then copy
the folder for the skill you want into `~/.claude/skills/`:

```
cp -r claude-code-skills/skills/done ~/.claude/skills/
```

`handoff` and `resume-handoff` are a pair (the `session-handoff` plugin) - copy both folders.
</details>

## Skills in this repo

| Skill | Plugin | What it does |
|---|---|---|
| `done` | `done` | End-of-session wrap-up: detects what changed, updates CLAUDE.md with gotchas only (not inventories), runs the test suite, commits only this session's files and pushes, creates a git repository (with a secret check before the first commit) for a new project folder, marks a resumed handoff complete, and prints a short status report. Needs `git`; the new-repository check also needs `bash` (Git Bash on Windows). |
| `handoff` | `session-handoff` | Saves an unfinished session to `handoffs/YYYY-MM-DD_HH-topic.md`: goal, constraints, current state, gotchas, files to read first, and exact next steps - so a fresh session can continue without re-explaining. |
| `resume-handoff` | `session-handoff` | Loads the newest handoff in a new session, reads the files it points at, flags anything that changed since (new commits, moved files), and starts the first next step. |

## Licence

MIT - see [LICENSE](LICENSE).

## Credit

Built by Efi Perez, published from personal Claude Code skills developed for real day-to-day work.

