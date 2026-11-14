#!/usr/bin/env bash
# Starts the review-duel reviewer: writes a start script into the temporary folder, then
# opens it in a new Terminal.app window (--terminal app) or prints the command to paste
# into a terminal tab (--terminal print). See references/launch.md.
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage: launch_reviewer.sh --cli codex|claude|cursor-agent --repo REPO --review-file FILE
                          [--model MODEL] [--effort LEVEL] [--terminal app|print]
EOF
  exit 2
}

die() { echo "launch_reviewer.sh: $*" >&2; exit 2; }

cli="" repo="" file="" model="" effort="" terminal=app
while (($#)); do
  case $1 in
    --cli) cli=${2:-}; shift 2 ;;
    --repo) repo=${2:-}; shift 2 ;;
    --review-file) file=${2:-}; shift 2 ;;
    --model) model=${2:-}; shift 2 ;;
    --effort) effort=${2:-}; shift 2 ;;
    --terminal) terminal=${2:-}; shift 2 ;;
    *) usage ;;
  esac
done
[[ -n $cli && -n $repo && -n $file ]] || usage
[[ $terminal == app || $terminal == print ]] || die "--terminal is app or print"
[[ -d $repo ]] || die "no repository folder: $repo"
[[ -f $file ]] || die "no review file: $file"
command -v "$cli" >/dev/null || die "$cli is not installed or not on PATH"

skill_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
repo=$(cd "$repo" && pwd -P)
review_dir=$(cd "$(dirname "$file")" && pwd -P)
file="$review_dir/$(basename "$file")"

# A reviewer whose writable folder contains the code could change it.
case "$repo/" in
  "$review_dir/"*) echo "WARNING: the repository lies inside the review folder, so the reviewer's write access covers the code. Use a review folder inside or beside the repository instead." >&2 ;;
esac

case $cli in
  codex)
    # Working root = the review folder: workspace-write lets Codex write there and
    # nowhere in the repository (tested with `codex sandbox`, codex-cli 0.167.0).
    # A reviewer needs neither computer use nor the browser, and computer use asks to
    # control an app (flags checked with `codex features list`, codex-cli 0.167.0,
    # 2026-11-14).
    workdir=$review_dir
    cmd=(codex -C "$review_dir" -s workspace-write --search
      --disable computer_use --disable browser_use)
    [[ -n $model ]] && cmd+=(-m "$model")
    [[ -n $effort ]] && cmd+=(-c "model_reasoning_effort=\"$effort\"")
    cmd+=("\$review-duel reviewer $file")
    ;;
  claude)
    # The prompt comes first: --add-dir and --allowedTools take several values and
    # would swallow a prompt placed after them. Default permission mode asks the user
    # before any edit outside the review folder.
    workdir=$repo
    cmd=(claude "/review-duel reviewer $file")
    [[ -n $model ]] && cmd+=(--model "$model")
    [[ -n $effort ]] && cmd+=(--effort "$effort")
    cmd+=(--permission-mode default --add-dir "$review_dir"
      --allowedTools "Edit(/$review_dir/**)" "Bash($skill_dir/scripts/duel.sh *)"
      "Bash(git diff *)" "Bash(git log *)" "Bash(git show *)" "Bash(git status *)"
      WebSearch WebFetch)
    ;;
  cursor-agent)
    # No per-folder write limit: read-only rests on the skill's instructions.
    workdir=$repo
    cmd=(cursor-agent)
    [[ -n $model ]] && cmd+=(--model "$model")
    [[ -n $effort ]] && echo "NOTE: cursor-agent has no effort setting; choose a model variant instead (cursor-agent --list-models). --effort ignored." >&2
    cmd+=("Read $skill_dir/SKILL.md and act as the review-duel reviewer for $file")
    ;;
  *) die "unknown CLI: $cli. Start it yourself with the prompt in references/setup.md." ;;
esac

tmp=${TMPDIR:-/tmp}
start=$(mktemp "${tmp%/}/review-duel-start.XXXXXX")
{
  echo '#!/usr/bin/env bash'
  echo '# review-duel reviewer, written by launch_reviewer.sh'
  printf 'cd %q || exit 1\n' "$workdir"
  # Variables Claude Code sets for its child processes (seen in Claude Code 2.1.325,
  # 2026-11-14). A terminal that inherited them starts a Claude reviewer as a child
  # session, with transcript saving off. CLAUDE_CODE_* variables set by the user stay.
  echo 'unset CLAUDECODE CLAUDE_PID CLAUDE_EFFORT CLAUDE_CODE_ENTRYPOINT CLAUDE_CODE_EXECPATH \'
  echo '  CLAUDE_CODE_SESSION_ID CLAUDE_CODE_CHILD_SESSION CLAUDE_CODE_SESSION_ATTENDED \'
  echo '  CLAUDE_CODE_MESSAGING_SOCKET CLAUDE_CODE_MESSAGING_TOKEN'
  printf 'exec'
  printf ' %q' "${cmd[@]}"
  echo
} >"$start"
chmod 700 "$start"

printf 'Reviewer command:'
printf ' %q' "${cmd[@]}"
printf '\n(run from %s)\n' "$workdir"

if [[ $terminal == app ]]; then
  [[ $(uname) == Darwin ]] || die "Terminal.app needs macOS. Use --terminal print."
  case $start in *[\"\'\\]*) die "start script path has quotes or backslashes: $start" ;; esac
  if ! osascript -e "tell application \"Terminal\" to do script \"bash '$start'\"" \
    -e 'tell application "Terminal" to activate' >/dev/null; then
    cat >&2 <<EOF
launch_reviewer.sh: could not open a Terminal.app window.
- If macOS asked whether this app may control "Terminal", allow it and run the
  launcher again. Unanswered for about 2 minutes, the request times out (-1712).
- If it was denied, turn it on in System Settings > Privacy & Security > Automation.
- Or use --terminal print, or paste this into a new terminal tab:
  bash $(printf '%q' "$start")
EOF
    exit 1
  fi
  echo "Started in a new Terminal.app window."
else
  echo "Paste into a new terminal tab:"
  printf 'bash %q\n' "$start"
fi
