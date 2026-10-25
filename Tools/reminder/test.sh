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

# Renewing by itself: a stand-in for ./fixkey records its runs, exits with the status in $dir/status, and on
# success installs a "new build" that works until day 20.
cat >"$dir/fake-fixkey" <<EOF
#!/bin/bash
echo "\$*" >>"$dir/renew.calls"
status=\$(cat "$dir/status")
[ "\$status" = 0 ] && echo $((start + 20 * day)) >"$dir/expiry"
exit "\$status"
EOF
chmod +x "$dir/fake-fixkey"
renew() {
  echo "$2" >"$dir/status"
  out=$(FIXKEY_SUPPORT_DIR="$dir" FIXKEY_NOW="$1" FIXKEY_DRY_RUN="${3:-Later}" FIXKEY_RENEW_COMMAND="$dir/fake-fixkey" \
    FIXKEY_RENEW_LOG="$dir/renew.log" bash ./remind.sh 2>&1 >/dev/null)
}
calls() { [ "$(cat "$dir/renew.calls" 2>/dev/null | wc -l | tr -d ' ')" = "$1" ]; }
fresh() { rm -f "$dir/reminder.state" "$dir/renew.last" "$dir/renew.calls"; echo "$1" >"$dir/expiry"; }

printf 'REPO=%s\nLANGUAGE=en\n' "$dir/repo" >"$dir/reminder.conf"
fresh $((start + 13 * day))
renew $((start + 10 * day)) 0
expect "renewing: not before the last 2 days" calls 0
renew $((start + 11 * day + hour)) 3
expect "renewing: tries when 2 days are left" calls 1
expect "renewing: runs ./fixkey renew" grep -qx "renew --lang en" "$dir/renew.calls"
expect "renewing: iPhone not reachable, quiet while more than a day is left" silent
renew $((start + 11 * day + 2 * hour)) 3
expect "renewing: at most every 3 hours" calls 1
renew $((start + 11 * day + 5 * hour)) 4
expect "renewing: tries again after 3 hours" calls 2
expect "renewing: Xcode's sign-in, says so" says "sign in to your Apple ID again"
expect "renewing: Xcode's sign-in, offers to reinstall" says "[Later Reinstall]"
renew $((start + 11 * day + 9 * hour)) 4
expect "renewing: the sign-in message only once" silent
renew $((start + 12 * day + 3 * hour)) 0
expect "renewing: renewed, says until when" says "renewed itself on your iPhone. It works until"
expect "renewing: renewed, no dialog" lacks "DIALOG:"
expect "renewing: the new date is kept" grep -qx "$((start + 20 * day))" "$dir/expiry"

fresh $((start + 13 * day))
renew $((start + 12 * day + hour)) 1
expect "renewing failed, the day before: reminds as before" says "couldn't renew itself yet"
renew $((start + 13 * day + hour)) 4
expect "renewing failed after the end: says why" says "has stopped working on your iPhone, and it couldn't renew itself"

printf 'REPO=%s\nLANGUAGE=da\n' "$dir/repo" >"$dir/reminder.conf"
fresh $((start + 13 * day))
renew $((start + 12 * day)) 0
expect "Danish: renewed" says "har fornyet sig selv på din iPhone"
expect "Danish: renews with --lang da" grep -qx "renew --lang da" "$dir/renew.calls"

if [ "$failures" -eq 0 ]; then echo "All $checks reminder checks pass."; else echo "$failures of $checks reminder checks FAILED."; fi
[ "$failures" -eq 0 ]
