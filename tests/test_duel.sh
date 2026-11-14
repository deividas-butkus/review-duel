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

# The status line below the title: pass and note keep it current.
status() { "$duel" show "$f" | sed -n 's/^status=//p'; }
sides() {
  sed -i.bak -e 's/^- \*\*Author:\*\* .*/- **Author:** Claude Code, opus, xhigh/' \
    -e 's/^- \*\*Reviewer:\*\* .*/- **Reviewer:** Cursor agent, grok-4.7-medium/' "$f"
  rm -f "$f.bak"
}
fresh; sides
check "a fresh file says the author is setting up" 0 0 "$(status)" "⚪ **Setting up**"
out=$("$duel" note "$f" author "writing Intent · round 1 · since 12:34" 2>&1)
"$duel" note "$f" author "writing Intent" >/dev/null
[[ $(status) == '⚪ **Setting up** · writing Intent' ]]
check "a note during setup replaces the last one whole" 0 $? "$(status)"
out=$("$duel" note "$f" reviewer "reading" 2>&1); check "note from the side without the turn is refused" 2 $? "$out" "author's turn"
"$duel" pass "$f" reviewer >/dev/null
s=$(status)
check "pass names the reviewer and its model" 0 0 "$s" "🔵 **Reviewer working** · Cursor agent, grok-4.7-medium · round 1 · since "
[[ $s != *"writing Intent"* ]]; check "pass clears the last note" 0 $? "$s"
"$duel" note "$f" reviewer "running tests" >/dev/null
[[ $(status) =~ ' · since '[0-9]{2}:[0-9]{2}' · running tests'$ ]]; check "note goes after the time" 0 $? "$(status)"
"$duel" note "$f" reviewer 'writing findings & a/b \ c' >/dev/null
s=$(status)
[[ $s == *' · writing findings & a/b \ c' && $s != *"running tests"* ]]
check "a new note replaces the old one, text kept as is" 0 $? "$s"
"$duel" note "$f" reviewer 'waiting for tests · round 9 · since 12:34' >/dev/null
"$duel" note "$f" reviewer 'writing findings' >/dev/null
s=$(status)
[[ $s =~ ' · round 1 · since '[0-9]{2}:[0-9]{2}' · writing findings'$ && $s != *12:34* ]]
check "a note with its own round and time is replaced whole" 0 $? "$s"
"$duel" pass "$f" author --state closing >/dev/null
check "closing pass names the author" 0 0 "$(status)" "🟣 **Author closing** · Claude Code, opus, xhigh · round 1"
awk '{ print }
  /^[|]---[|]---[|]---[|]---[|]---[|]---[|]$/ { print "| F1 | Minor | `a.sh:1` | x | closed | fixed |"; print "| F2 | Important | `b.sh:2` | y | user | split |" }
  /^[|]---[|]---[|]---[|]$/ { print "| F2 | keep it | change it |" }' "$f" >"$f.new" && mv "$f.new" "$f"
"$duel" pass "$f" none --state closed >/dev/null
check "closed after consensus, findings counted once" 0 0 "$(status)" \
  "✅ **Closed** · consensus in round 1 · 2 findings: 1 closed, 1 for the user · at "

fresh; sed -i.bak '1s/cap=10/cap=1/' "$f"; rm -f "$f.bak"
"$duel" pass "$f" reviewer >/dev/null; "$duel" pass "$f" author >/dev/null
"$duel" pass "$f" none --state closed >/dev/null
check "closed at the round cap" 0 0 "$(status)" "✅ **Closed** · round cap reached in round 1 · no findings"
fresh; "$duel" pass "$f" reviewer >/dev/null; "$duel" pass "$f" none --state stopped >/dev/null
check "stopped" 0 0 "$(status)" "🛑 **Stopped** · round 1 · at "

# A review file from before the status line: pass changes line 1 and nothing else.
fresh; grep -v 'Setting up' "$f" >"$f.new" && mv "$f.new" "$f"
cp "$f" "$dir/before.md"
"$duel" pass "$f" reviewer >/dev/null
diff <(tail -n +2 "$dir/before.md") <(tail -n +2 "$f") >/dev/null
check "a file without a status line keeps its body" 0 $? ""
out=$("$duel" note "$f" reviewer "x" 2>&1); check "note needs a status line" 2 $? "$out" "no status line"

# Lines that only look like a status line (a bold label without a status emoji) are left
# alone, with or without a real status line below them.
fresh; sed -i.bak '2s/.*/# **Waiting** queue refactor/' "$f"; rm -f "$f.bak"
awk 'NR == 3 { print "- **Waiting** for checks" } { print }' "$f" >"$f.new" && mv "$f.new" "$f"
"$duel" pass "$f" reviewer >/dev/null
[[ $(sed -n 2,3p "$f") == $'# **Waiting** queue refactor\n- **Waiting** for checks' ]] &&
  [[ $(status) == "🔵 **Reviewer working**"* ]]
check "lookalike lines stay, the real status line changes" 0 $? "$(sed -n 2,5p "$f")"
fresh; sed -i.bak '2s/.*/# **Waiting** queue refactor/' "$f"; rm -f "$f.bak"
awk '/Setting up/ { print "- **Waiting** for checks"; next } { print }' "$f" >"$f.new" && mv "$f.new" "$f"
cp "$f" "$dir/before.md"
"$duel" pass "$f" reviewer >/dev/null
diff <(tail -n +2 "$dir/before.md") <(tail -n +2 "$f") >/dev/null
check "lookalike lines stay in a file without a status line" 0 $? "$(sed -n 2,4p "$f")"

# Lines other than line 1 and the status line are copied byte for byte, down to a
# missing final newline.
fresh; printf 'last line' >>"$f"
"$duel" pass "$f" reviewer >/dev/null
[[ $(tail -c 9 "$f") == 'last line' && $(tail -c 1 "$f" | od -An -c | tr -d ' ') == e ]]
check "pass keeps a missing final newline" 0 $? "$(tail -c 12 "$f" | od -c | head -1)"

# open: only inside VS Code's terminal, with code -r. A stub code records its arguments.
mkdir -p "$dir/codebin"
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$@" >"%s/code.args"\n' "$dir" >"$dir/codebin/code"
chmod +x "$dir/codebin/code"
abs="$(cd "$dir" && pwd -P)/review.md"
out=$(env -u CURSOR_TRACE_ID TERM_PROGRAM=vscode PATH="$dir/codebin:$PATH" "$duel" open "$f" 2>&1)
check "open in VS Code's terminal" 0 $? "$(tr '\n' ' ' <"$dir/code.args" 2>/dev/null)" "-r -g $abs:1"
rm -f "$dir/code.args"
out=$(env -u TERM_PROGRAM PATH="$dir/codebin:$PATH" "$duel" open "$f" 2>&1)
[[ ! -e $dir/code.args ]]; check "outside VS Code, open only prints the path" 0 $? "$out" "Open the review file"
out=$(CURSOR_TRACE_ID=1 TERM_PROGRAM=vscode PATH="$dir/codebin:$PATH" "$duel" open "$f" 2>&1)
[[ ! -e $dir/code.args ]]; check "in Cursor's terminal, open doesn't call code" 0 $? "$out" "Open the review file"

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
