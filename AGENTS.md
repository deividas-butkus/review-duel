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
