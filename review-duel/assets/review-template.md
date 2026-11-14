<!-- review-duel turn=author round=1 state=active interval=5 timeout=1800 cap=10 -->
# Review duel: {what is reviewed}

## Outcome

**State:** in progress, round 1 of at most {cap}.

{At the end the author replaces this paragraph: how the duel ended, what changed and how
to see it, and what was not checked.}

### Findings

| ID | Severity | Where | Finding | Status | Resolution |
|---|---|---|---|---|---|

### For the user to decide

| ID | Reviewer's position | Author's position |
|---|---|---|

## Setup

- **Repository:** `{absolute path}`
- **Scope:** {uncommitted changes in these paths, branch against base, files}
- **Code under review:** `{git diff --cached -- paths}`, baseline staged {date time}
- **Fixes made in the duel:** `{git diff -- paths}`, left unstaged
- **Author:** {agent, model, effort}
- **Reviewer:** {agent, model, effort}
- **Reviewer started with:** `{command printed by launch_reviewer.sh}`
- **Turn script:** `{absolute path}/scripts/duel.sh`
- **Check interval, wait limit, round cap:** {5 s}, {30 min}, {10}
- **Patch files:** this folder, `R<round>-F<id>.patch`
- **Earlier duel on this code:** {link, or none}
- **Started:** {date time}

## Intent

{Author, up to 15 lines: what the code is for, requirements and constraints, decisions
already taken with the user and why, known limits, what is out of scope, and what you
most want checked.}

## Rounds

<!-- Each turn adds a section: "### Round N · Reviewer · agent, model, date time" or
"### Round N · Author · ...". Newest at the bottom. -->
