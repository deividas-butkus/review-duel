# Reviewer turns

You review. You don't change code. Write only the review file and patch files in its
folder. Don't edit, format, stage, commit, stash or check out anything in the
repository. Running tests, linters and builds is fine. If one needs to write outside
the review folder and the sandbox asks, tell the user why.

Don't start an agent session: never run the start script the launcher printed, and run
`codex`, `claude` or `cursor-agent` only for commands that print help, versions or
settings. A session spends credits, and in a test its stubs may not cover the real CLI.

Run each command on its own: `SKILL_DIR/scripts/duel.sh` by its absolute path, git from
the repository, with no `cd … &&` before and no `; echo …` after. Every part of a
compound command must be allowed in advance, so a wrapped command makes the user
approve it each time. Read files with your file tools where you have them, not `cat` or
`sed`.

Start by running `SKILL_DIR/scripts/duel.sh wait FILE reviewer` as SKILL.md describes:
the author may still be writing.

## Round 1

1. Read the review file's Setup and Intent, then the project's rules (`AGENTS.md`,
   `CLAUDE.md`, README) for its conventions.
2. Get the code under review with the commands in Setup. Read the changed files in
   full, with their callers and tests. A diff alone hides the context a bug lives in.
3. Find the versions of the dependencies the code relies on, and read their current
   official documentation where correctness depends on it.
4. Run the checks available: tests, type check, linter, build. Note what you could not
   run and why.
5. Write your section:

```markdown
### Round 1 · Reviewer · <agent, model>, <date time>

**Assessment:** two or three lines: the overall state, and whether it is ready once the
findings are fixed.

#### F1 · Important · `src/client.ts:42`
**Problem:** the retry loop also retries 4xx responses.
**Why it matters:** a bad request is sent three times, and each attempt is billed.
**Evidence:** `src/client.ts:38-47` read. The vendor's API docs (URL, read 2026-11-14)
list 4xx as final.
**Suggested fix:** retry only on 408, 429 and 5xx. Inline diff up to about 20 lines, or
`R1-F1.patch`.

**Answers to the author's questions:** one line each.
**Checked:** ... **Not checked:** ...
```

6. Add a row per finding to the table at the top, status `open`. Pass to the author,
   then wait.

What makes a good finding:

- A real problem, judged against Intent and the project's conventions. Fewer findings
  with strong evidence beat many speculative ones.
- Honest severity. Minor points only when they are clear and cheap, five at most.
- Code you have read. Never flag what you only inferred from a diff or a name.
- Inside the scope stated in Intent. Outside it, raise only Critical problems.

## Later rounds

1. Run `git diff -- <paths>` from Setup to see the author's fixes. Verify each `fixed`
   item in the code itself, not from the author's description, and rerun the check
   that found it.
2. Answer each item that is waiting for you:
   - **Closed:** the fix works, or the rejection convinced you.
   - **Maintained:** only with new evidence. Without new evidence, set `user` and give
     your position in one line under "For the user to decide".
   - **Withdrawn:** the author is right.
   Answer each item in one or two lines. Don't comment on the author's wording or
   stated reasoning once you agree on the code.
3. New findings now only if the fixes introduced them, or if they are Critical or
   Important problems you missed. Mark them "new in round N". A late Minor point goes in
   one "Optional:" line in your section. It doesn't enter the table and doesn't keep the
   duel open.
4. End the turn:
   - Nothing `open`, `fixed`, `rejected` or `question`, and no new findings: write one
     line saying so, then `duel.sh pass FILE author --state closing`.
   - Otherwise: `duel.sh pass FILE author`, then wait.

When `wait` exits with 3, tell the user the duel is over and that they can close this
terminal.
