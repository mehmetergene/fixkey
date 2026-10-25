#!/bin/bash
# Copyright © 2026 Mehmet Ergene. Licensed under CC BY-NC 4.0: non-commercial use only, credit required. See LICENSE.
# Tests remind.sh without showing anything: a temporary folder, a fake clock and a fake click.
set -uo pipefail
cd "$(dirname "$0")"
dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT
checks=0 failures=0 out=""

expect() { # label, then a command that must succeed
  local label=$1
  shift
  checks=$((checks + 1))
  if ! "$@"; then
    failures=$((failures + 1))
    printf 'FAIL  %s\n      got: %s\n' "$label" "${out:-<nothing>}"
  fi
}
silent() { [ -z "$out" ]; }
says() { case "$out" in *"$1"*) return 0 ;; *) return 1 ;; esac; }
lacks() { ! says "$1"; }

# Runs the reminder at the given time; the dialog "clicks" the given button.
remind() { out=$(FIXKEY_SUPPORT_DIR="$dir" FIXKEY_NOW="$1" FIXKEY_DRY_RUN="${2:-OK}" bash ./remind.sh 2>&1 >/dev/null); }

day=86400 hour=3600 start=2000000000
mkdir -p "$dir/repo"
printf '#!/bin/bash\n' >"$dir/repo/fixkey"
chmod +x "$dir/repo/fixkey"
printf 'REPO=%s\nLANGUAGE=en\n' "$dir/repo" >"$dir/reminder.conf"

remind $start
expect "no build installed yet: nothing" silent

echo $((start + 3 * day)) >"$dir/expiry"
remind $start
expect "three days left: nothing" silent

remind $((start + 2 * day + hour)) Later
expect "the day before: says when it stops" says "stops working on your iPhone on"
expect "the day before: offers to reinstall now" says "[Later Reinstall]"
expect "the day before: Later opens nothing" lacks "OPEN:"
remind $((start + 2 * day + 2 * hour))
expect "the day before: only once" silent

remind $((start + 3 * day + 60)) Later
expect "after the end: offers to reinstall" says "has stopped working"
expect "after the end: Later or Reinstall" says "[Later Reinstall]"
expect "Later opens nothing" lacks "OPEN:"
remind $((start + 3 * day + 2 * hour)) Later
expect "after the end: quiet for 12 hours" silent

remind $((start + 3 * day + 13 * hour)) Reinstall
expect "after 12 hours: asks again" says "has stopped working"
expect "Reinstall opens Terminal" says "OPEN: $dir/Reinstall Fixkey.command"
expect "the command file reinstalls in the Fixkey folder" grep -q "cd $dir/repo && ./fixkey reinstall" "$dir/Reinstall Fixkey.command"

echo $((start + 10 * day)) >"$dir/expiry"
remind $((start + 3 * day + 14 * hour))
expect "a new 7-day permit: quiet again" silent

printf 'REPO=%s\nLANGUAGE=da\n' "$dir/repo" >"$dir/reminder.conf"
remind $((start + 9 * day + hour)) Senere
expect "Danish: the day before" says "holder op med at virke på din iPhone"
expect "Danish: time with kl." says " kl. "
remind $((start + 10 * day + 60)) Senere
expect "Danish: after the end" says "[Senere Geninstaller]"

if [ "$failures" -eq 0 ]; then echo "All $checks reminder checks pass."; else echo "$failures of $checks reminder checks FAILED."; fi
[ "$failures" -eq 0 ]
