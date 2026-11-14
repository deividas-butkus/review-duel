# review-duel

An [Agent Skill](https://agentskills.io/specification) for a cross-model code review.
The session that wrote the code starts a second agent in its own terminal: Codex,
Claude Code or Cursor's agent, with any model they offer. The two argue each finding in
one review file until they agree or reach a round cap. The reviewer never changes code;
the author's fixes stay unstaged against a staged baseline.

## Why

A model reviewing its own code tends to accept its own reasoning, and models from one
family share blind spots. A second agent, ideally another vendor's model, starts
without the author's reasoning in context. Every finding is argued from evidence (the
code, a test run, current documentation), so neither side's bias is accepted
unchecked. The same model in a fresh session also works, with less independence.

## Install

The skill is the `review-duel/` folder inside this repository. Clone it anywhere (the
path below is an example), then link the skill folder into your agents' personal skill
folders:

```bash
git clone https://github.com/deividas-butkus/review-duel.git ~/Projects/agent-skills/review-duel
mkdir -p ~/.claude/skills ~/.agents/skills
ln -s ~/Projects/agent-skills/review-duel/review-duel ~/.claude/skills/review-duel
ln -s ~/Projects/agent-skills/review-duel/review-duel ~/.agents/skills/review-duel
```

Claude Code reads `~/.claude/skills/`. Codex reads `~/.agents/skills/`. Both follow
symlinked skill folders. Edits take effect in new sessions of either tool. Cursor's
agent needs no install as reviewer: the launch prompt gives it the `SKILL.md` path.

The skill is tested in Claude Code and Codex, and with Cursor's agent as reviewer.
Other agents that read the Agent Skills format, such as Gemini CLI, GitHub Copilot and Cursor, can load it from their own skill
folders; see each tool's documentation.

Then ask the session that wrote the code for a review duel.

## What a duel looks like

The top of a finished review file, from the duel that reviewed a change to this
repository's launcher (Claude Code as author, Codex as reviewer):

```markdown
<!-- review-duel turn=none round=2 state=closed interval=5 timeout=1800 cap=10 -->
# Review duel: launcher start script clears Claude Code's session variables

**State:** consensus in round 2 of at most 10.

| ID | Severity | Where | Finding | Status | Resolution |
|---|---|---|---|---|---|
| F1 | Minor | `tests/test_duel.sh:72-76` | Test treats a shell-escaped start path as a literal filename; fails under a TMPDIR containing spaces | closed | Verified: printed command runs via `bash -c`, exit status is checked, spaced path and all ten variables are covered; 25 checks pass |
```

Line 1 says whose turn it is. Below the table, each round adds a signed section: the
reviewer's findings with evidence, then the author's answers and fixes.

## Tested with

- macOS 26.6, the system Bash 3.2.
- Author: Claude Code 2.1.325 in VS Code 1.145's integrated terminal.
- Reviewer: Codex CLI 0.167.0 in a Terminal.app window; Claude Code 2.1.325 and
  Cursor's agent 2026.11.13 (grok-4.7-medium) in VS Code terminal tabs, started with the
  printed command.

Not tested yet: JetBrains IDEs and other terminals, Linux, Windows. The Terminal.app launch needs macOS; the printed command for
a terminal tab needs only Bash.

## Tests

```bash
tests/test_duel.sh
```

It tests the turn script in a throwaway folder and makes no model calls.

## License

[MIT](LICENSE)
