# Author turns

Each time `wait` returns 0, take one turn. Keep the status line current with
`duel.sh note FILE author "…"` (SKILL.md): at the start, for example "answering F1–F3",
then before tests and before writing up.

## 1. Check the ground

Read the reviewer's newest section and the findings table. Run `git status --short`
and `git diff --stat`. If code changed that you didn't change, stop and tell the user
before anything else. The reviewer must not edit code, and the user may have.

## 2. Resolve every finding in this turn

Work through the open items in severity order. Verify each before acting: read the
cited code, reproduce the case or run the test, and check the documentation if the
finding turns on a dependency's behaviour. Then answer with one of these:

- **Agree.** Fix it in the working tree and leave the fix unstaged. Run the relevant
  tests, type check or linter. Reply in one or two lines, for example:
  "Fixed: retries stop on 4xx. `git diff -- src/client.ts`. `npm test client`: pass."
  Status `fixed`.
- **Disagree.** Give the reason and the evidence. Status `rejected`.
- **Unclear.** Say what you need to know. Status `question`. Don't fix on a guess.
- **The user's call.** A product or business decision, or a change to something the user
  decided earlier, goes to the user. If it blocks other fixes, ask the user now, within
  this turn. Otherwise set status `user`.

Answer everything in one turn. Fixes split across rounds add rounds. Where the reviewer adopted a suggested patch file, apply it, check it, and say so.

On items the reviewer answered in its last turn, reply only where something is still
open. A `closed` or `withdrawn` item needs no reply.

## 3. Update the top of the file

Update the table rows you touched, and the state line under Outcome ("In progress,
round N of at most CAP").

## 4. End the turn

- `state=closing`, or this is round `cap`: close the duel (below).
- Otherwise: `duel.sh pass FILE reviewer --round N+1`, then wait.

## Closing the duel

Rewrite the Outcome section:

- **State:** consensus in round N, cap reached in round N, or stopped by the user.
- **What changed:** one to three lines, and how to see it: `git diff -- <paths>` for
  the fixes, and `git diff --cached -- <paths>` (or the base range) for the code as
  reviewed.
- **For the user to decide:** every `user` item, and anything not `closed` or
  `withdrawn` at the cap, with each side's position in one line. A `fixed` item the
  reviewer didn't verify is listed as "fixed, not verified".
- **Not checked:** what neither side could verify, such as tests not run or a live
  service not called.

Then `duel.sh pass FILE none --state closed`.

Report to the user in chat: the outcome in up to five lines, the review file path, how
to close the reviewer (`/quit` in Codex, `/exit` in Claude Code, `/quit` or `/exit` in
Cursor's agent), and the first open item for them to decide, with the others named in
one line. The fixes stay unstaged. Staging and committing are the user's call.
