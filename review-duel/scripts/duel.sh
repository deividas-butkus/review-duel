#!/usr/bin/env bash
# Turn line for a review duel. Line 1 of the review file holds the duel's state:
#   <!-- review-duel turn=reviewer round=1 state=active interval=5 timeout=1800 cap=10 -->
# Only the side whose turn it is writes to the file; it passes the turn as its last step.
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage:
  duel.sh show FILE
  duel.sh wait FILE author|reviewer [--chunk SECONDS]
  duel.sh pass FILE author|reviewer|none [--round N] [--state active|closing|closed|stopped]

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

cmd_show() {
  local line
  line=$(marker "$1")
  for key in turn round state interval timeout cap; do
    printf '%s=%s\n' "$key" "$(field "$line" "$key")"
  done
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

  local line cur_turn cur_state new tmp
  line=$(marker "$file")
  cur_turn=$(field "$line" turn)
  cur_state=$(field "$line" state)
  [[ $cur_state == closed || $cur_state == stopped ]] && die "the duel is already $cur_state"
  [[ $cur_turn == "$to" ]] && die "it is already $to's turn: pass from the side that holds the turn"

  new=$(printf '%s\n' "$line" | sed -E "s/ turn=[^ ]+/ turn=$to/")
  [[ -n $round ]] && new=$(printf '%s\n' "$new" | sed -E "s/ round=[^ ]+/ round=$round/")
  [[ -n $state ]] && new=$(printf '%s\n' "$new" | sed -E "s/ state=[^ ]+/ state=$state/")

  # Rewrite line 1 in a copy that keeps the file's permissions, then move it into place,
  # so the waiting side never reads a half-written turn line.
  tmp="$file.duel-tmp.$$"
  cp -p "$file" "$tmp"
  { printf '%s\n' "$new"; tail -n +2 "$file"; } >"$tmp"
  mv -f "$tmp" "$file"
  echo "PASSED: $new"
}

(($# >= 2)) || usage
cmd=$1
shift
case $cmd in
  show) (($# == 1)) || usage; cmd_show "$1" ;;
  wait) (($# >= 2)) || usage; cmd_wait "$@" ;;
  pass) (($# >= 2)) || usage; cmd_pass "$@" ;;
  *) usage ;;
esac
