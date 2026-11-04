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
   | `codec-loop` | `codec-review` + `codec-build` (a pair - one reviews with a second model, the other builds with it; they share a reference file) | `/plugin install codec-loop@efi-skills` |

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
`codec-review` and `codec-build` are a pair (the `codec-loop` plugin) - copy both folders:
`codec-build` links to the reference files inside `codec-review`.
</details>

## Skills in this repo

| Skill | Plugin | What it does |
|---|---|---|
| `done` | `done` | End-of-session wrap-up: detects what changed, updates CLAUDE.md with gotchas only (not inventories), runs the test suite, commits only this session's files and pushes, creates a git repository (with a secret check before the first commit) for a new project folder, marks a resumed handoff complete, and prints a short status report. Needs `git`; the new-repository check also needs `bash` (Git Bash on Windows). |
| `handoff` | `session-handoff` | Saves an unfinished session to `handoffs/YYYY-MM-DD_HH-topic.md`: goal, constraints, current state, gotchas, files to read first, and exact next steps - so a fresh session can continue without re-explaining. |
| `resume-handoff` | `session-handoff` | Loads the newest handoff in a new session, reads the files it points at, flags anything that changed since (new commits, moved files), and starts the first next step. |
| `codec-review` | `codec-loop` | Adversarial review loop between Claude and OpenAI Codex over a plan, document or codebase: Codex attacks the work read-only and returns a structured verdict, Claude judges each finding and rewrites the target, and they repeat on one Codex thread until Codex approves or a round cap (5 by default) is hit. Runs silently; the only question you are asked is whether to spend more rounds at the cap. Output is one report file with a table of topics and how each was resolved. |
| `codec-build` | `codec-loop` | Hands a frozen spec to a second model to implement (Codex builds by default), then runs a bounded review-and-fix loop over the resulting diff: clean-tree or snapshot gate before any write, at most 2 fix rounds before Claude takes over, Claude writes every commit, and the only question you are asked is whether to commit. |

## Prerequisites

**`codec-loop` (`codec-review` + `codec-build`):**

- **Claude Code**, with a shell tool: the terminal CLI, VS Code, or the Claude Desktop app's **Code** tab with a **Local** session.
- **OpenAI Codex CLI**, installed and signed in: `npm install -g @openai/codex` (needs Node.js), then `codex login` (a ChatGPT plan or an API key). Both skills check this on first use and tell you what to do if it is missing. Codex runs on your own OpenAI account and quota, separate from Claude's. **No Codex?** The skills tell you no connection was found and offer a *same-family mode*: reply "use Claude" and a different Claude model acts as the critic (and, for `codec-build`, a Claude subagent builds). It is weaker than a cross-vendor review — models from the same family share more blind spots — but still a valid, independent review, and the report says which mode ran.
- **Windows or macOS** (Linux is untested but uses the same bash commands as macOS). The skills carry PowerShell commands for Windows and bash commands for macOS/Linux. They were developed and tested on Windows; the bash commands were tested under Git Bash on Windows, and **macOS has not been tested** - please open an issue if something fails on a Mac.
- `git` is needed for `codec-build`'s clean-tree gate (without it the skill uses a verified file snapshot instead). The bash commands also use `node`, which is present whenever the Codex CLI is.
- Optional: the `session-handoff` plugin from this marketplace. When a `handoff` skill is installed, `codec-review` appends a "run the handoff skill" step to every plan it reviews; without it that step is skipped. The Codex plugin for Claude Code (`openai/codex-plugin-cc`) is also optional and not required: its `/codex:setup` repeats the install check, and `/codex:adversarial-review` is a cheaper one-shot critique of a git diff with no loop.
- Optional, recommended: the **`plan-review` mod** from the companion marketplace [`EfiPerez/claude-code-mods`](https://github.com/EfiPerez/claude-code-mods). When you approve a plan in plan mode, it saves the plan to `plans/` and has Claude run `codec-review` on it before any code is written; on Windows it also skips plans that were already reviewed unchanged. Install it with `/plugin marketplace add EfiPerez/claude-code-mods`, then `/plugin install plan-review@efi-mods`.
- **Not supported: the Claude Desktop Chat tab and claude.ai.** OpenAI removed `codex mcp-server`, the only way a chat-only app could have reached Codex, and both skills also need local files and a shell. In those apps the skills stop at their first check and explain how to open the project in Claude Code.

## Privacy: what Codex can read

`codec-review` and `codec-build` send the files Codex reads to OpenAI, under your own account. Their sandbox setting (`read-only` for reviews, `workspace-write` for builds) restricts what Codex can **write**; it does **not** confine what Codex can **read** to the project. Codex can read any file your user account can read: the project's `.env` and data files, and also files elsewhere on the computer such as credentials and configuration in your home directory. The skills exclude obvious secret and data-file patterns from the working set, but that only keeps the default scope small - it is not a security boundary, and the skills do not ask you again on each run.

Run `codec-loop` only on projects and machines where that exposure is acceptable to you and your organisation. `codec-build` additionally lets Codex edit files in your real project folder, which is why it requires a clean git tree (or a verified snapshot) before it starts.

## Licence

MIT - see [LICENSE](LICENSE). Third-party components retain their original licences - see [NOTICE](NOTICE) and [LICENSES/Apache-2.0.txt](LICENSES/Apache-2.0.txt).

## Credit

Built by Efi Perez, published from personal Claude Code skills developed for real day-to-day work.

`codec-review` and `codec-build` adapt the loop design of [`chaseai-yt/claudex-loop`](https://github.com/chaseai-yt/claudex-loop) by Chase AI (MIT). Two files in `codec-review/references/` - `review-prompt.md` and `review-output.schema.json` - are derived from the [OpenAI Codex plugin for Claude Code](https://github.com/openai/codex-plugin-cc) (Apache-2.0, Copyright 2026 OpenAI) and carry Apache-2.0 terms; both were modified.
