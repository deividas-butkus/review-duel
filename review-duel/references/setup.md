# Setup (author)

Copy this checklist and tick it off:

```
- [ ] 1. Gather context
- [ ] 2. Interview the user
- [ ] 3. Set the baseline
- [ ] 4. Write the review file
- [ ] 5. Launch the reviewer
- [ ] 6. Pass the turn and wait for round 1
```

## 1. Gather context

Collect these before asking anything, so the questions offer real options:

- Reviewer CLIs installed: `command -v claude codex cursor-agent`.
- Repository state: `git rev-parse --show-toplevel`, `git status --short`,
  `git diff --cached --stat`, `git branch --show-current`, `git log --oneline -5`, and
  the default branch (`git symbolic-ref --short refs/remotes/origin/HEAD`, else `main`
  or `master`).
- What changed and why: your own work in this session, or what the user tells you about
  code you didn't write.
- An existing reviews folder in the repository (`reviews/`, `docs/reviews/`) or a
  convention for it in the project's agent rules.

## 2. Interview the user

Use the AskUserQuestion tool when available (up to four questions per dialog, the
recommended option first, marked "(Recommended)"). Otherwise ask the same questions as a
short numbered list. Every question offers a default, so the user can accept them all.

**Dialog 1**

1. **Reviewer.** The installed CLIs. Recommend one from a different vendor than yours,
   since a model from another family has fewer blind spots in common with you.
2. **Model and effort.** First option: "CLI defaults (Recommended)", the model and
   effort the CLI is configured with. Second: "Set model or effort", for the user to
   type, for example "gpt-x, high". Valid effort values per CLI are in `launch.md`.
   If "Set model or effort" comes back without values, ask a follow-up listing the
   CLI's choices: model aliases or names (`claude --help` names `opus`, `sonnet`,
   `fable`; `cursor-agent models` lists Cursor's), valid efforts, and Other. Recommend
   the CLI's default model, else the vendor's top model, and the default effort, else
   `xhigh`. Never recommend a cheaper model to save cost; that is the user's call. For
   Cursor's agent, check what the user's plan runs (`launch.md`).
3. **Scope.** Build the options from the repository state:
   - *Uncommitted changes*: working tree and index against HEAD, all of it or some
     paths. The default when this session's work is uncommitted.
   - *Branch against base*: `<base>...HEAD`. The default on a feature branch with
     commits.
   - *Last commit* or a commit range.
   - *Files or folders*: their whole content, for code that is already committed.
4. **Review file.** Temporary or permanent:
   - *Permanent*, the suggestion: the repository's existing reviews folder if it has
     one, otherwise `<repo>/docs/reviews/` when `docs/` exists, otherwise
     `<repo>/reviews/`. Inside it, one folder per duel:
     `YYYY-MM-DD_<slug>/review.md`, so patch files sit beside it. The user may name
     another place.
   - *Temporary*: `review-duel/YYYY-MM-DD_HHMM_<slug>/review.md` in the temporary
     folder, `$TMPDIR` or else `/tmp`, joined with one slash (on macOS `$TMPDIR` ends
     with one). The operating system may clear it later.

**Dialog 2: the go-ahead**

State the defaults in the question: "Check every 5 s, at most 10 rounds, wait limit
30 min, reviewer in a new Terminal.app window." Options:

- "Start with these (Recommended)".
- "Start in a VS Code tab": the launcher prints a one-line command for the user to paste
  into a new terminal tab.
- "Change the settings": the user types new values. A longer check interval suits slow
  turns. Keep at least 1 s.

Choosing a start option approves launching a session that spends the reviewer's
credits. Don't launch without it. Terminal.app exists only on macOS; elsewhere use the
printed command.

## 3. Set the baseline

The baseline is the code under review as it stood when the duel began. Stage it, so
`git diff --cached` keeps showing the original while `git diff` shows only the fixes
made during the duel. A large fix then stays in Git, not in the review file.

Before staging, run `git diff --cached --name-only`. If the index already holds changes
and the scope isn't exactly those staged changes, tell the user and ask before
staging. Staging a partly staged file erases the split the user made.

| Scope | Baseline step | Code under review | Fixes made in the duel |
|---|---|---|---|
| Uncommitted changes | `git add -A -- <paths>` | `git diff --cached -- <paths>` | `git diff -- <paths>` |
| Branch, range or last commit | None if the scope's files are clean. If they have uncommitted edits, ask: include them (stage them), or stop | `git diff <base>...HEAD` | `git diff` |
| Files or folders | None if clean. Otherwise `git add -A -- <paths>` | The files at HEAD or in the index | `git diff -- <paths>` |

- Stage only the files in scope. Leave everything else as it is.
- `git add -A` includes new files in scope and respects `.gitignore`. Check that no
  secret file (`.env`, keys) ends up in scope.
- Never commit, stash, reset or check out during the duel. At the end the fixes stay
  unstaged for the user to review.
- A permanent review folder inside the repository stays untracked unless the user says
  otherwise. Keep it out of the baseline.
- Not a Git repository: say that a baseline needs Git and ask. The user may run
  `git init` with a first commit, or run the duel without a baseline, with fixes then
  described in the review file.

## 4. Write the review file

Copy `SKILL_DIR/assets/review-template.md` to the chosen path. Set the turn line
values (interval, timeout in seconds, cap), and fill in the title, Setup and Intent.
The turn line starts with `turn=author`, so the reviewer waits until setup is done.

**Intent** is the author's main contribution. In up to 15 lines: what the code is for,
the requirements and constraints, decisions already taken with the user and why, known
limits, what is out of scope, and what you most want checked. The reviewer judges the
code against it, so a wrong statement here costs rounds.

**Setup** carries the exact commands for the code under review and for the fixes, and
the absolute path of `duel.sh`, because the reviewer copies them.

## 5. Launch the reviewer

```bash
SKILL_DIR/scripts/launch_reviewer.sh --cli codex|claude|cursor-agent \
  --repo REPO --review-file FILE [--model M] [--effort E] [--terminal app|print]
```

The script writes a start script into the temporary folder, then opens it in a new
Terminal.app window (`app`, the default) or prints `bash <start script>` (`print`). It
prints the reviewer command too. Add that command to Setup under "Reviewer started
with". `launch.md` explains the flags, how each CLI is kept off the code, and the
prompts the user may see on the first run.

For a CLI the script doesn't know, give the user the review file path and this prompt
to start it with: "Read SKILL_DIR/SKILL.md and act as the review-duel reviewer for
FILE".

Tell the user where the reviewer runs, or the command to paste, and that they can
watch it, type into it, or tell either side "stop". Then list the prompts the chosen
CLI may show and how to answer each, one line per prompt, from "First run" in
`launch.md`.

## 6. Pass the turn and wait for round 1

Once the launch command is in Setup, pass the turn with `duel.sh pass FILE reviewer`.
Then run `duel.sh wait FILE author` as described in SKILL.md, and continue with
`author.md`.
