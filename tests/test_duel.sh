#!/usr/bin/env bash
# Regression tests for review-duel/scripts/duel.sh and launch_reviewer.sh. Runs in a
# throwaway folder; no model calls.
set -uo pipefail

duel="$(cd "$(dirname "$0")/.." && pwd -P)/review-duel/scripts/duel.sh"
template="$(cd "$(dirname "$0")/.." && pwd -P)/review-duel/assets/review-template.md"
dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT
f="$dir/review.md"
fails=0

check() { # check NAME EXPECTED_EXIT ACTUAL_EXIT [OUTPUT PATTERN]
  if [[ $2 == "$3" && ( -z ${5:-} || $4 == *"$5"* ) ]]; then
    echo "PASS  $1"
  else
    echo "FAIL  $1: expected exit $2${5:+ and \"$5\"}, got $3: $4"
    fails=$((fails + 1))
  fi
}

fresh() { sed "1s/interval=5/interval=1/; 1s/timeout=1800/timeout=${1:-1800}/" "$template" >"$f"; }

fresh
out=$("$duel" show "$f" 2>&1); check "show reads the template" 0 $? "$out" "turn=author"
out=$("$duel" wait "$f" author 2>&1); check "author holds the turn during setup" 0 $? "$out" "YOUR TURN"
out=$("$duel" wait "$f" reviewer --chunk 1 2>&1); check "reviewer waits, chunk elapses" 10 $? "$out" "STILL WAITING"
out=$("$duel" pass "$f" reviewer 2>&1); check "author passes after setup" 0 $? "$out" "turn=reviewer"
out=$("$duel" pass "$f" reviewer 2>&1); check "passing to the side holding the turn is refused" 2 $? "$out" "already reviewer"
out=$("$duel" wait "$f" reviewer 2>&1); check "reviewer's turn, round 1" 0 $? "$out" "round=1"
out=$("$duel" pass "$f" author 2>&1); check "reviewer passes to author" 0 $? "$out" "turn=author"
out=$("$duel" wait "$f" author 2>&1); check "author's turn after pass" 0 $? "$out" "round=1"
out=$("$duel" pass "$f" reviewer --round 2 2>&1); check "author passes, round 2" 0 $? "$out" "round=2"

# The waiting side wakes up when the turn changes.
("$duel" wait "$f" author >"$dir/bg.out" 2>&1; echo $? >"$dir/bg.code") &
sleep 2
"$duel" pass "$f" author --state closing >/dev/null
wait
check "waiting author wakes on pass" 0 "$(cat "$dir/bg.code")" "$(cat "$dir/bg.out")" "state=closing"

out=$("$duel" pass "$f" none --state closed 2>&1); check "author closes" 0 $? "$out" "state=closed"
out=$("$duel" wait "$f" reviewer 2>&1); check "reviewer sees the duel over" 3 $? "$out" "DUEL OVER"
out=$("$duel" pass "$f" reviewer 2>&1); check "no pass after closing" 2 $? "$out" "already closed"
grep -q '^## Outcome' "$f"; check "body kept after passes" 0 $? ""

# An editor rewriting the file can leave line 1 empty for a moment: wait reads it again.
fresh
"$duel" pass "$f" reviewer >/dev/null
cp "$f" "$dir/saved.md"
("$duel" wait "$f" author >"$dir/bg.out" 2>&1; echo $? >"$dir/bg.code") &
sleep 1
: >"$f"
sleep 1.5
cp "$dir/saved.md" "$f"
"$duel" pass "$f" author >/dev/null
wait
check "wait retries a briefly unreadable turn line" 0 "$(cat "$dir/bg.code")" "$(cat "$dir/bg.out")" "YOUR TURN"

# The same when wait starts while line 1 is empty (its first read). A fresh file is the
# author's turn.
fresh
cp "$f" "$dir/saved.md"
: >"$f"
(sleep 0.5; cp "$dir/saved.md" "$f") &
out=$("$duel" wait "$f" author 2>&1); check "wait's first read retries too" 0 $? "$out" "YOUR TURN"
wait

# A turn line that stays unreadable is still an error.
fresh
"$duel" pass "$f" reviewer >/dev/null
("$duel" wait "$f" author >"$dir/bg.out" 2>&1; echo $? >"$dir/bg.code") &
sleep 1
printf 'no turn line\n' >"$f"
wait
check "wait gives up when the turn line stays unreadable" 2 "$(cat "$dir/bg.code")" "$(cat "$dir/bg.out")" "not a review-duel turn line"

fresh 2
touch -t 202001010000 "$f"
out=$("$duel" wait "$f" reviewer 2>&1); check "timeout when the file is idle" 20 $? "$out" "TIMED OUT"

printf 'no turn line\n' >"$f"
out=$("$duel" wait "$f" author 2>&1); check "file without a turn line" 2 $? "$out" "not a review-duel turn line"
out=$("$duel" wait "$dir/missing.md" author 2>&1); check "missing file" 2 $? "$out" "no review file"
fresh
out=$("$duel" pass "$f" somebody 2>&1); check "unknown role" 2 $? "$out" "pass to author"
out=$("$duel" pass "$f" author --state done 2>&1); check "unknown state" 2 $? "$out" "unknown state"

chmod 640 "$f"; "$duel" pass "$f" reviewer >/dev/null
check "pass keeps file permissions" 640 "$(stat -f %Lp "$f" 2>/dev/null || stat -c %a "$f")" ""
[[ -z $(ls "$dir" | grep duel-tmp) ]]; check "no temporary file left" 0 $? ""

# launch_reviewer.sh: the start script drops Claude Code's session variables. A stub
# codex on PATH prints the names (not values) of the variables it was started with.
# The temporary folder has a space, so the printed command's quoting is tested too.
launcher="$(cd "$(dirname "$0")/.." && pwd -P)/review-duel/scripts/launch_reviewer.sh"
session_vars=(CLAUDECODE CLAUDE_PID CLAUDE_EFFORT CLAUDE_CODE_ENTRYPOINT
  CLAUDE_CODE_EXECPATH CLAUDE_CODE_SESSION_ID CLAUDE_CODE_CHILD_SESSION
  CLAUDE_CODE_SESSION_ATTENDED CLAUDE_CODE_MESSAGING_SOCKET CLAUDE_CODE_MESSAGING_TOKEN)
mkdir -p "$dir/bin" "$dir/repo" "$dir/rv" "$dir/tmp dir"
printf '#!/usr/bin/env bash\ncompgen -e\n' >"$dir/bin/codex"
chmod +x "$dir/bin/codex"
cp "$template" "$dir/rv/review.md"
out=$(PATH="$dir/bin:$PATH" TMPDIR="$dir/tmp dir/" "$launcher" --cli codex \
  --repo "$dir/repo" --review-file "$dir/rv/review.md" --terminal print 2>&1)
check "launcher prints the start command" 0 $? "$out" "Paste into a new terminal tab"
# Run the printed line as a user pasting it would, with every session variable set.
names=$(for v in "${session_vars[@]}"; do export "$v=1"; done
  export CLAUDE_CODE_USE_BEDROCK=1 PATH="$dir/bin:$PATH"
  bash -c "$(printf '%s\n' "$out" | tail -n 1)" 2>&1)
check "printed command starts the reviewer" 0 $? "$names"
left=$(grep -xF -f <(printf '%s\n' "${session_vars[@]}") <<<"$names")
[[ -z $left ]]; check "start script drops Claude Code's session variables" 0 $? "left: $left"
grep -qx CLAUDE_CODE_USE_BEDROCK <<<"$names"
check "start script keeps Claude variables the user set" 0 $? ""
check "codex starts without computer use and the browser" 0 0 "$out" \
  "--disable computer_use --disable browser_use"

# A TMPDIR without a trailing slash still puts the start script inside it.
mkdir -p "$dir/tmp2"
PATH="$dir/bin:$PATH" TMPDIR="$dir/tmp2" "$launcher" --cli codex --repo "$dir/repo" \
  --review-file "$dir/rv/review.md" --terminal print >/dev/null 2>&1
compgen -G "$dir/tmp2/review-duel-start.*" >/dev/null
check "start script lands in a TMPDIR without a trailing slash" 0 $? "$(ls "$dir")"

# When osascript fails (for example macOS denied control of Terminal), the launcher
# says how to fix it. Stubs stand in for osascript and for uname, so this runs anywhere.
mkdir -p "$dir/macbin"
printf '#!/usr/bin/env bash\necho "execution error: Not authorized to send Apple events to Terminal. (-1743)" >&2\nexit 1\n' >"$dir/macbin/osascript"
printf '#!/usr/bin/env bash\necho Darwin\n' >"$dir/macbin/uname"
chmod +x "$dir/macbin/osascript" "$dir/macbin/uname"
out=$(PATH="$dir/macbin:$dir/bin:$PATH" TMPDIR="$dir/tmp2" "$launcher" --cli codex \
  --repo "$dir/repo" --review-file "$dir/rv/review.md" 2>&1)
check "osascript failure prints how to fix it" 1 $? "$out" "Privacy & Security > Automation"

echo
((fails == 0)) && echo "ALL PASS" || { echo "$fails FAILED"; exit 1; }
