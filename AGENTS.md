# review-duel: agent guidance

The review-duel Agent Skill and its tests. The skill is the `review-duel/` folder; the
README says how it is installed.

## Repository

- Public repository: keep personal paths, client names and private notes out of
  committed files.
- The skill folder `review-duel/` holds only what agents use: `SKILL.md`, `scripts/`,
  `references/`, `assets/`. README, LICENSE, tests and this file stay at the root.

## Changing the skill

- Follow the Agent Skills specification, so any tool that reads the format can load the
  skill, and the skill guides of Claude Code and Codex, where it is tested in both
  roles: `name` matches the folder name, `description` says what the skill does and
  when to use it, in the third person, under 1,024 characters. Keep `SKILL.md` under
  500 lines, with references one level deep.
- Frontmatter uses only `name` and `description`, the two fields the specification
  requires and every tool reads, so one `SKILL.md` serves them all.
- Check CLI flags and paths against each tool's `--help` and current official
  documentation, and record the date checked in the skill.
- After changing a script in `review-duel/scripts/`, run `tests/test_duel.sh`; all
  cases must pass.
- Ask before anything that spends vendor credits, such as launching a reviewer to test
  the skill.

## Adding a reviewer CLI

The launcher knows Codex, Claude Code and Cursor's agent. Any other agent CLI can review
already: the author starts it with the prompt in `review-duel/references/setup.md`. To
add one to the launcher:

1. From its `--help` and current official documentation, find how to pass a prompt at
   start, pick a model and effort, set the working folder, limit writes to the review
   folder, and allow web search. Record the version and the date checked.
2. Add a `case` branch to `review-duel/scripts/launch_reviewer.sh`.
3. In `review-duel/references/launch.md`, add its column to the table, how read-only is
   enforced, and its first-run prompts.
4. Add a test with a stub of the CLI on PATH, and run `tests/test_duel.sh`.
5. Ask before a test duel, since it spends credits. Then add the CLI to the README's
   "Tested with".
