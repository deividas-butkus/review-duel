#!/usr/bin/env bash
# Turn line and status line for a review duel. Line 1 of the review file holds the duel's
# state:
#   <!-- review-duel turn=reviewer round=1 state=active interval=5 timeout=1800 cap=10 -->
# Below the title, the status line tells the user who is working and on what:
#   🔵 **Reviewer working** · Cursor agent, grok-4.7-medium · round 2 · since 15:43 · running tests
# Only the side whose turn it is writes to the file; it passes the turn as its last step.
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage:
  duel.sh show FILE
  duel.sh wait FILE author|reviewer [--chunk SECONDS]
  duel.sh pass FILE author|reviewer|none [--round N] [--state active|closing|closed|stopped]
  duel.sh note FILE author|reviewer TEXT
  duel.sh open FILE

wait exit codes:
  0   your turn
  3   duel closed or stopped
  10  --chunk seconds elapsed, still the other side's turn: run wait again
  20  the other side has not touched the file for `timeout` seconds
  2   usage or file error
EOF
  exit 2
}

die() { echo "duel.sh: $*" >&2; exit 2; }

# turn_line FILE: prints line 1 if it is a turn line, else returns 1
turn_line() {
  local line
  [[ -f $1 ]] || return 1
  line=$(head -n 1 "$1") || return 1
  [[ $line == '<!-- review-duel '*' -->' ]] || return 1
  printf '%s\n' "$line"
}

marker() {
  [[ -f $1 ]] || die "no review file: $1"
  turn_line "$1" || die "line 1 of $1 is not a review-duel turn line"
}

# read_line FILE SECONDS: the turn line, read up to three times SECONDS apart, because
# the other side's editor may be rewriting the file at that instant
read_line() {
  local try
  for try in 1 2; do turn_line "$1" && return; sleep "$2"; done
  marker "$1"
}

# field LINE KEY: the value of KEY=value in the turn line
field() { printf '%s\n' "$1" | tr ' ' '\n' | sed -n "s/^$2=//p" | head -n 1; }

mtime() { stat -f %m "$1" 2>/dev/null || stat -c %Y "$1"; }

is_uint() { [[ $1 =~ ^[0-9]+$ ]]; }

# A status line: one of the emoji status_text writes, then one of its labels in bold.
status_re='^(⚪|🟣|🔵|✅|🛑) \*\*(Setting up|Author working|Author closing|Reviewer working|Waiting|Closed|Stopped)\*\*'

# status_lineno FILE: the number of the status line, looked for above the first "## "
# heading. Prints nothing for a review file without one.
status_lineno() {
  local n=0 l
  while IFS= read -r l || [[ -n $l ]]; do
    n=$((n + 1))
    [[ $l == '## '* ]] && break
    if [[ $l =~ $status_re ]]; then echo "$n"; break; fi
  done <"$1"
  return 0
}

# side_label FILE Author|Reviewer: the rest of that side's line in Setup (agent, model,
# effort)
side_label() {
  awk -v k="- **$2:** " 'index($0, k) == 1 { s = substr($0, length(k) + 1); sub(/^ +/, "", s); print s; exit }' "$1"
}

# findings_summary FILE: "no findings", or "3 findings: 2 closed, 1 for the user", from
# the status column of the Findings table
findings_summary() {
  awk '
    /^#/ { in_table = ($0 ~ /^### Findings/); next }
    in_table && /^\| *F[0-9]+ *\|/ {
      n++
      if (match($0, /\| *(open|fixed|rejected|question|closed|withdrawn|user) *\|/)) {
        s = substr($0, RSTART, RLENGTH); gsub(/[| ]/, "", s); count[s]++
      }
    }
    END {
      if (!n) { print "no findings"; exit }
      out = n (n == 1 ? " finding" : " findings")
      k = split("closed withdrawn user open fixed rejected question", order, " ")
      sep = ": "
      for (i = 1; i <= k; i++) {
        s = order[i]
        if (count[s]) { out = out sep count[s] " " (s == "user" ? "for the user" : s); sep = ", " }
      }
      print out
    }' "$1"
}

# status_text FILE TURN STATE ROUND CAP PREVIOUS_STATE: the status line for a new turn line
status_text() {
  local file=$1 turn=$2 state=$3 round=$4 cap=$5 prev=$6 now how emoji label who=""
  now=$(date +%H:%M)
  case $state in
    closed)
      how="round $round"
      if [[ $prev == closing ]]; then
        how="consensus in round $round"
      elif is_uint "$cap" && is_uint "$round" && ((round >= cap)); then
        how="round cap reached in round $round"
      fi
      printf '✅ **Closed** · %s · %s · at %s\n' "$how" "$(findings_summary "$file")" "$now" ;;
    stopped) printf '🛑 **Stopped** · round %s · at %s\n' "$round" "$now" ;;
    *)
      case $turn in
        author)
          emoji=🟣 label='Author working' who=$(side_label "$file" Author)
          [[ $state == closing ]] && label='Author closing' ;;
        reviewer) emoji=🔵 label='Reviewer working' who=$(side_label "$file" Reviewer) ;;
        *) emoji=⚪ label=Waiting ;;
      esac
      printf '%s **%s**%s · round %s · since %s\n' "$emoji" "$label" "${who:+ · $who}" "$round" "$now" ;;
  esac
}

# write_lines FILE LINE1 N LINE_N: replace line 1, and line N if N > 1, in a copy that
# keeps the file's permissions, then move it into place, so the waiting side never reads
# a half-written file. The other lines are copied byte for byte.
write_lines() {
  local tmp="$1.duel-tmp.$$" n=$3
  cp -p "$1" "$tmp"
  if ((n > 1)); then
    {
      printf '%s\n' "$2"
      if ((n > 2)); then sed -n "2,$((n - 1))p" "$1"; fi
      printf '%s\n' "$4"
      tail -n +$((n + 1)) "$1"
    } >"$tmp"
  else
    { printf '%s\n' "$2"; tail -n +2 "$1"; } >"$tmp"
  fi
  mv -f "$tmp" "$1"
}

cmd_show() {
  local line sn
  line=$(marker "$1")
  for key in turn round state interval timeout cap; do
    printf '%s=%s\n' "$key" "$(field "$line" "$key")"
  done
  sn=$(status_lineno "$1")
  [[ -z $sn ]] || printf 'status=%s\n' "$(sed -n "${sn}p" "$1")"
}

cmd_wait() {
  local file=$1 role=$2 chunk=0
  shift 2
  [[ $role == author || $role == reviewer ]] || die "role must be author or reviewer"
  while (($#)); do
    case $1 in
      --chunk) is_uint "${2:-}" || die "--chunk needs seconds"; chunk=$2; shift 2 ;;
      *) usage ;;
    esac
  done

  local line interval timeout start now idle turn state round
  line=$(read_line "$file" 1)
  interval=$(field "$line" interval); interval=${interval:-5}
  timeout=$(field "$line" timeout); timeout=${timeout:-1800}
  is_uint "$interval" && ((interval >= 1)) || die "interval must be a whole number of seconds, at least 1"
  is_uint "$timeout" || die "timeout must be a whole number of seconds"
  start=$(date +%s)

  while :; do
    line=$(read_line "$file" "$interval")
    turn=$(field "$line" turn)
    state=$(field "$line" state)
    round=$(field "$line" round)
    if [[ $turn == "$role" ]]; then
      echo "YOUR TURN: role=$role round=$round state=$state"
      exit 0
    fi
    if [[ $state == closed || $state == stopped ]]; then
      echo "DUEL OVER: state=$state round=$round"
      exit 3
    fi
    now=$(date +%s)
    idle=$((now - $(mtime "$file")))
    if ((idle >= timeout)); then
      echo "TIMED OUT: turn=$turn has not touched the review file for ${idle}s (limit ${timeout}s)"
      exit 20
    fi
    if ((chunk > 0 && now - start >= chunk)); then
      echo "STILL WAITING: turn=$turn round=$round. Run wait again."
      exit 10
    fi
    sleep "$interval"
  done
}

cmd_pass() {
  local file=$1 to=$2 round="" state=""
  shift 2
  [[ $to == author || $to == reviewer || $to == none ]] || die "pass to author, reviewer or none"
  while (($#)); do
    case $1 in
      --round) is_uint "${2:-}" || die "--round needs a number"; round=$2; shift 2 ;;
      --state)
        case ${2:-} in active | closing | closed | stopped) state=$2 ;; *) die "unknown state: ${2:-}" ;; esac
        shift 2 ;;
      *) usage ;;
    esac
  done

  local line cur_turn cur_state new sn status=""
  line=$(marker "$file")
  cur_turn=$(field "$line" turn)
  cur_state=$(field "$line" state)
  [[ $cur_state == closed || $cur_state == stopped ]] && die "the duel is already $cur_state"
  [[ $cur_turn == "$to" ]] && die "it is already $to's turn: pass from the side that holds the turn"

  new=$(printf '%s\n' "$line" | sed -E "s/ turn=[^ ]+/ turn=$to/")
  [[ -n $round ]] && new=$(printf '%s\n' "$new" | sed -E "s/ round=[^ ]+/ round=$round/")
  [[ -n $state ]] && new=$(printf '%s\n' "$new" | sed -E "s/ state=[^ ]+/ state=$state/")

  # A pass also rewrites the status line, which clears the last side's note.
  sn=$(status_lineno "$file")
  if [[ -n $sn ]]; then
    status=$(status_text "$file" "$to" "$(field "$new" state)" "$(field "$new" round)" \
      "$(field "$new" cap)" "$cur_state")
  fi
  write_lines "$file" "$new" "${sn:-0}" "$status"
  echo "PASSED: $new"
}

# note: the side holding the turn says what it is doing, at the end of the status line
cmd_note() {
  local file=$1 role=$2 text=$3 line turn state sn status re base
  [[ $role == author || $role == reviewer ]] || die "role must be author or reviewer"
  line=$(marker "$file")
  turn=$(field "$line" turn)
  state=$(field "$line" state)
  [[ $state == closed || $state == stopped ]] && die "the duel is already $state"
  [[ $turn == "$role" ]] || die "it is $turn's turn: only the side that holds the turn writes"
  sn=$(status_lineno "$file")
  [[ -n $sn ]] || die "no status line above the first section of $file"
  text=$(printf '%s' "$text" | tr '\n\r\t' '   ')
  [[ -n ${text// /} ]] || die "note needs text"
  status=$(sed -n "${sn}p" "$file")
  # Keep what pass wrote and replace the rest, so no part of the last note survives:
  # during setup only the label, after a pass everything up to the first
  # "round N · since HH:MM".
  re='^[^ ]+ \*\*[^*]+\*\*'
  [[ $status =~ $re ]] || die "unreadable status line: $status"
  base=${BASH_REMATCH[0]}
  re=' · round [0-9]+ · since [0-9]{2}:[0-9]{2}'
  if [[ $base != *'**Setting up**' && $status =~ $re ]]; then
    base=${status%%"${BASH_REMATCH[0]}"*}${BASH_REMATCH[0]}
  fi
  write_lines "$file" "$line" "$sn" "$base · $text"
  echo "NOTED: $text"
}

# open: show the review file in the VS Code window the author runs in. Only from inside
# VS Code's terminal: from elsewhere, `code` may start a new window that inherits the
# caller's environment. Cursor's terminal also sets TERM_PROGRAM=vscode, so it is left out.
cmd_open() {
  local file=$1
  [[ -f $file ]] || die "no review file: $file"
  file="$(cd "$(dirname "$file")" && pwd -P)/$(basename "$file")"
  if [[ ${TERM_PROGRAM:-} == vscode && -z ${CURSOR_TRACE_ID:-} ]] && command -v code >/dev/null; then
    code -r -g "$file:1"
    echo "OPENED in VS Code: $file"
  else
    echo "Open the review file in your editor to watch the duel: $file"
  fi
}

(($# >= 2)) || usage
cmd=$1
shift
case $cmd in
  show) (($# == 1)) || usage; cmd_show "$1" ;;
  wait) (($# >= 2)) || usage; cmd_wait "$@" ;;
  pass) (($# >= 2)) || usage; cmd_pass "$@" ;;
  note) (($# == 3)) || usage; cmd_note "$@" ;;
  open) (($# == 1)) || usage; cmd_open "$1" ;;
  *) usage ;;
esac
