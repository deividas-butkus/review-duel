# Launching the reviewer

`scripts/launch_reviewer.sh` builds the commands below. Flags were checked against each
CLI's `--help` and official documentation on 2026-11-14 (Codex CLI 0.167.0, Claude Code
2.1.325; Cursor agent 2026.11.13 against `--help` only). If a CLI rejects a flag, check
its `--help` and current documentation, then fix the script.

## Per CLI

| | Codex | Claude Code | Cursor agent |
|---|---|---|---|
| Working folder | the review folder (`-C`) | the repository | the repository |
| Prompt | `$review-duel reviewer FILE` | `/review-duel reviewer FILE` | "Read SKILL_DIR/SKILL.md and act as the review-duel reviewer for FILE" |
| Model | `-m MODEL` | `--model MODEL` (alias or full name) | `--model MODEL` (`--list-models`) |
| Effort | `-c model_reasoning_effort="LEVEL"`. Levels depend on the model, e.g. `low`, `medium`, `high`, `xhigh` | `--effort LEVEL`: `low`, `medium`, `high`, `xhigh`, `max` | no flag: pick a model variant |
| Web | `--search` (built-in web search) | `WebSearch` and `WebFetch` allowed | its own tools |
| Turned off | computer use and browser use (`--disable computer_use --disable browser_use`) | | |
| Kept off the code by | the sandbox | permission prompts | approval prompts, if set to allowlist |

Leaving out model and effort runs the CLI's configured defaults.

Cursor's agent, seen on 2026-11-14:

- `cursor-agent models` lists the account's models but doesn't mark which ones its
  plan runs. On the Free plan only Grok 4.7, Grok 4.6 and Auto run, "with fixed
  settings": `grok-4.7-medium` ran, while `grok-4.7-high`, `grok-4.7-xhigh` and
  `gemini-4-hydrogen-xhigh` stopped at once with "Model unavailable on Free". Auto may
  pick a Claude model.
- An expired login shows "Logged in (unable to fetch user details)" and "No models
  available for this account". `cursor-agent login` fixes it.
- It updates itself when it starts, so check `cursor-agent --version` after the first
  start.

## How read-only is enforced

- **Codex:** `-s workspace-write` with the review folder as working root. Codex may
  write in its working root and the temporary folders, and nowhere else. A local test
  with `codex sandbox` on 2026-11-14 confirmed it. With the working root in a review
  folder inside a repository, writing to the repository's code and running `git add`
  failed with "Operation not permitted", while writing in the review folder worked.
  Reading the repository and running `git diff` and `git log` worked.
  Exception: a repository inside `/tmp` or `$TMPDIR` stays writable, so keep the code
  being reviewed outside the temporary folders.
- **Claude Code:** `--permission-mode default` asks the user before any edit or
  command that isn't allowed in advance. Allowed in advance: edits inside the review
  folder (`Edit(//absolute/path/**)`), `duel.sh`, read-only git commands, web search and
  fetch. The user declines anything else in the reviewer's terminal.
- **Cursor agent:** no per-folder write limit. With `approvalMode` set to `allowlist`
  in `~/.cursor/cli-config.json`, as in the setup tested on 2026-11-14, it asks before
  each shell command not on its allowlist and before writing a file, so the user's
  answers guard the code along with the reviewer's instructions. In other modes the
  instructions are the only guard. The author's check at the start of each turn
  (`git status`, `git diff --stat`) catches changes it didn't make.

## Session variables

The start script clears the variables Claude Code sets for its own child processes:
`CLAUDECODE`, `CLAUDE_PID`, `CLAUDE_EFFORT` and `CLAUDE_CODE_` + `ENTRYPOINT`,
`EXECPATH`, `SESSION_ID`, `CHILD_SESSION`, `SESSION_ATTENDED`, `MESSAGING_SOCKET`,
`MESSAGING_TOKEN` (seen in Claude Code 2.1.325's Bash tool, 2026-11-14). A terminal
opened from a Claude session, such as a VS Code window started with `code -n` from its
Bash tool, inherits them, and a Claude reviewer started there runs as a child session
with transcript saving off. Other `CLAUDE_CODE_*` variables, which users set
themselves, are kept.

## First run

The user may see these prompts once:

- macOS asks whether the app running the author (VS Code, Terminal) may control
  Terminal. Allow it, or use `--terminal print`. Unanswered for about 2 minutes, the
  request times out (`AppleEvent timed out (-1712)`) and the launcher prints how to fix
  it.
- Codex asks whether to trust the working folder.
- Codex warns "Running without the shared background server". It comes with `--search`
  and is harmless.
- Codex with computer use on asks to control "Codex Computer Use". The launcher turns
  computer use and browser use off; if the prompt still appears, deny it.
- Claude Code asks whether to trust the repository, if it hasn't run there before.
- Claude Code asks "Allow external CLAUDE.md imports" when agent rules above the
  repository import files. Answer No: the reviewer needs the repository's rules, not
  files that may hold the user's private notes.
- Cursor's agent asks before each shell command not on its allowlist and before
  writing a file. Tab adds the command to the allowlist in `~/.cursor/cli-config.json`,
  for all its sessions. Add `duel.sh`, `git diff`, `git log`, `git show`,
  `git status`, `date` and writes to the review file. Allow tests and one-off checks
  once. Decline anything that changes the repository or Git state, or that starts an
  agent session (the start script, `codex`, `claude`, `cursor-agent`). Don't add a
  whole CLI such as `codex` to the allowlist, since that also allows `codex exec`, and
  don't choose "Run Everything".
- Codex's sandbox blocks tool caches outside the review folder (for example `uv`, `npm`
  or `pip` caches), so a test run may ask for approval. The user approves it in the
  reviewer's terminal.
- Codex's sandbox has no network by default. The reviewer reads documentation through
  `--search`. A command that needs the network asks for approval.

## Skill discovery

The skill is the `review-duel/` folder inside its repository, linked into:

- `~/.claude/skills/review-duel` for Claude Code, which follows symlinked skill folders.
- `~/.agents/skills/review-duel` for Codex, which scans `$HOME/.agents/skills` and
  follows symlinks.

Cursor's agent gets the SKILL.md path in its prompt, so it needs no install.

Sources, read 2026-11-14:

- Claude Code skills: https://code.claude.com/docs/en/skills
- Claude Code CLI reference: https://code.claude.com/docs/en/cli-reference
- Codex skills: https://developers.openai.com/codex/skills
- Codex CLI reference: https://developers.openai.com/codex/cli/reference
- Codex config reference: https://developers.openai.com/codex/config-reference
- Agent Skills specification: https://agentskills.io/specification
