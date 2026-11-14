---
name: review-duel
description: Runs a review duel, a cross-model code review in which a second AI agent, started in its own terminal, challenges the code under review, and the two argue each finding in one shared Markdown file until they agree or reach a round cap. The reviewer is an agent CLI (currently Codex, Claude Code or Cursor's agent) running any model it offers. Covers both roles, author and reviewer. Use when the user asks for a review duel, a second-model or cross-vendor code review, or for another agent or model (for example Codex, GPT, Gemini or Claude) to check code, and when a prompt says "review-duel reviewer" with a review file path.
---

# Review duel

Two agents review one piece of code in turns:

- The **author** is the session that runs the duel, usually the one that wrote the code.
  It interviews the user, sets the duel up, answers every finding and makes every code
  change.
- The **reviewer** is a second model in its own terminal. It reads, runs checks and
  argues. It never changes code.

They talk only through the **review file**, a Markdown file whose first line says whose
turn it is. The user can watch both terminals and step in at any time.

`SKILL_DIR` below is the folder holding this file. Resolve it once with
`cd SKILL_DIR && pwd -P` and use absolute paths, because the reviewer runs the same
scripts from another working directory.

## Your role

- The prompt says **reviewer** and gives a review file path: you are the reviewer.
  Read `references/reviewer.md` and follow it.
- The user asked for a review duel: you are the author. Work through
  `references/setup.md`, then `references/author.md` on each of your turns.
- Resuming an interrupted duel: run `SKILL_DIR/scripts/duel.sh show FILE` and continue
  in your role from the newest section.

## Rules for both sides

These rules keep duels short. Without them, most extra rounds go to acknowledgements,
split fixes and arguments about reasoning.

- **Argue from evidence.** Check each claim against the code before accepting or
  rejecting it: read the lines, run the test, reproduce the case. Agree in one line when
  the evidence supports the other side ("Agreed. Fixed in ..."), with no thanks, praise
  or apology. Disagree with the reason and the evidence. Don't concede to end the duel
  sooner, and don't hold a position once the evidence is against it.
- **Check current documentation.** When a finding, a fix or a rejection depends on how a
  library, framework, language feature, CLI or service behaves, find the version in use
  (lockfile, manifest, `--version`) and read the official documentation or changelog for
  it. Cite the URL and the date read. Remembered APIs may have changed since training.
- **Argue outcomes, not wording.** Once both sides agree on what the code should do,
  leave the other side's stated reasoning alone unless it ends up in the code or its docs.
- **Stop repeating.** If you would restate an argument already made, with no new
  evidence, the finding is deadlocked: set it to `user` and put each side's position in
  one line under "For the user to decide".
- **Keep the file readable.** The outcome and the findings table stay at the top; rounds
  go below. A finding takes about ten lines at most. Point to evidence (file:line, a
  command and its result in one line, a URL) instead of pasting output. A suggested patch
  longer than about 20 lines goes in a file next to the review file, named
  `R<round>-F<id>.patch`, linked from the finding.
- **Follow the project's rules.** Read the repository's `AGENTS.md`, `CLAUDE.md` or
  equivalent. If they require the user's approval for changes, get it within your turn.
- **Sign each section**: `### Round 2 · Author · <agent, model>, 2026-11-14 15:40`.
- **Record what you did not check** at the end of each section, in one line.

## The turn line

Line 1 of the review file holds the duel's state:

```
<!-- review-duel turn=author round=1 state=active interval=5 timeout=1800 cap=10 -->
```

Only the side whose turn it is writes to the review file. Write your section and table
updates first, then pass the turn as the last step, then wait:

```bash
SKILL_DIR/scripts/duel.sh pass FILE reviewer|author|none [--round N] [--state closing|closed|stopped]
SKILL_DIR/scripts/duel.sh wait FILE author|reviewer [--chunk SECONDS]
```

`wait` checks line 1 every `interval` seconds inside a shell loop, so waiting costs no
model tokens. Its exit code tells you what to do:

| Exit | Meaning | Action |
|---|---|---|
| 0 | Your turn | Take your turn |
| 3 | Duel closed or stopped | Tell the user in one line and stop |
| 10 | `--chunk` elapsed, still the other side's turn | Run `wait` again |
| 20 | The other side has not touched the file for `timeout` seconds | Tell the user, ask: keep waiting, or stop |
| 2 | Usage or file error | Fix the call |

How to wait:

- **Claude Code:** run `wait` through Bash with `run_in_background: true` and no
  `--chunk`. The harness wakes you when it exits. Don't poll its output.
- **Codex and other agents:** run it in the foreground with `--chunk 240`, and run it
  again on exit 10. 240 seconds stays under Codex's default 300-second poll window for
  long-running commands.

Any write to the review file restarts the other side's timeout, so on a long turn save
your section as you go.

If the user tells either side to stop: `duel.sh pass FILE none --state stopped`, after a
one-line note in the file.

## Findings

IDs are `F1`, `F2` and so on, assigned by the reviewer and never reused.

Severity:

- **Critical**: wrong results, data loss, a security hole, broken build or tests.
- **Important**: a bug in a realistic case, missing error handling, or a maintenance cost
  you can name.
- **Minor**: naming, readability, a small simplification.

Status in the findings table:

| Status | Meaning | Next move |
|---|---|---|
| `open` | Raised, not answered | Author |
| `fixed` | Author changed the code | Reviewer verifies |
| `rejected` | Author disagrees, with reasons | Reviewer accepts or maintains |
| `question` | One side needs information | The other side |
| `closed` | Fix verified, or rejection accepted | None |
| `withdrawn` | Reviewer dropped it | None |
| `user` | Deadlocked, or a product decision | The user |

## How a duel ends

- **Consensus.** In the reviewer's turn, nothing is `open`, `fixed`, `rejected` or
  `question`, and there are no new findings. The reviewer passes with
  `--state closing`. The author writes the outcome and sets `closed`.
- **Round cap.** A round is one reviewer turn and one author turn. After the author's
  turn in round `cap`, the author closes the duel. Everything not `closed` or
  `withdrawn` goes to the user.
- **Stopped** by the user, or after a timeout the user chose not to wait out.

A closing turn invites no reply. Nobody writes a turn only to acknowledge or confirm.

One duel covers one scope. Changes made after it closes get a new duel with a new review
file, whose Setup links the earlier one.

## Files

- `references/setup.md`: the author's interview, baseline, review file and launch.
- `references/author.md`: the author's turns and closing.
- `references/reviewer.md`: the reviewer's turns.
- `references/launch.md`: reviewer CLIs, flags, how read-only is enforced, first-run
  prompts.
- `assets/review-template.md`: the review file template.
- `scripts/duel.sh`: turn line (`show`, `pass`, `wait`).
- `scripts/launch_reviewer.sh`: starts the reviewer in a Terminal.app window, or prints
  the command to paste.
