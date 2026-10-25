#!/bin/bash
# Copyright © 2026 Mehmet Ergene. Licensed under CC BY-NC 4.0: non-commercial use only, credit required. See LICENSE.
#
# Reminds you when Fixkey's 7 days on the iPhone end (free Apple ID). ./fixkey reminder on copies this script to
# ~/Library/Application Support/Fixkey, and macOS runs it every few hours. It reads only its own files there:
#   expiry          when the installed build stops working (seconds since 1970), written by ./fixkey reinstall
#   reminder.conf   REPO=<the Fixkey folder> and LANGUAGE=en|da
#   reminder.state  what it has already shown
# The day before, and again after the end (at most every 12 hours), it offers to reinstall, which gives 7 new days.
#
# Testing: FIXKEY_SUPPORT_DIR=<folder> FIXKEY_NOW=<seconds> FIXKEY_DRY_RUN=<button to click> remind.sh

SUPPORT=${FIXKEY_SUPPORT_DIR:-"$HOME/Library/Application Support/Fixkey"}
NOW=${FIXKEY_NOW:-$(date +%s)}
STATE_FILE="$SUPPORT/reminder.state"

[ -f "$SUPPORT/expiry" ] || exit 0
EXPIRY=$(tr -cd '0-9' <"$SUPPORT/expiry")
[ -n "$EXPIRY" ] || exit 0
REPO=$(sed -n 's/^REPO=//p' "$SUPPORT/reminder.conf" 2>/dev/null)
LANGUAGE=$(sed -n 's/^LANGUAGE=//p' "$SUPPORT/reminder.conf" 2>/dev/null)
STATE=$(cat "$STATE_FILE" 2>/dev/null)

t() { if [ "$LANGUAGE" = da ]; then printf '%s' "$2"; else printf '%s' "$1"; fi; }

# A dialog with the given buttons; the last one is the default. Prints the button clicked.
dialog() {
  local text=$1 buttons="" last=""
  shift
  for last in "$@"; do buttons="$buttons${buttons:+, }\"$last\""; done
  if [ -n "${FIXKEY_DRY_RUN:-}" ]; then
    printf 'DIALOG: %s [%s]\n' "$text" "$*" >&2
    printf '%s' "$FIXKEY_DRY_RUN"
    return
  fi
  osascript -e "button returned of (display dialog \"$text\" with title \"Fixkey\" buttons {$buttons} default button \"$last\" giving up after 3600)" 2>/dev/null
}

when=$(t "$(LC_ALL=en_US.UTF-8 date -r "$EXPIRY" '+%A at %H:%M')" "$(LC_ALL=da_DK.UTF-8 date -r "$EXPIRY" '+%A kl. %H.%M')")
left=$((EXPIRY - NOW))
[ "$left" -le 86400 ] || exit 0
mkdir -p "$SUPPORT"

# Shows the message with Later and Reinstall; Reinstall opens Terminal at ./fixkey reinstall.
offer_reinstall() {
  local later reinstall answer command
  later=$(t "Later" "Senere")
  reinstall=$(t "Reinstall" "Geninstaller")
  answer=$(dialog "$1" "$later" "$reinstall")
  [ "$answer" = "$reinstall" ] && [ -x "$REPO/fixkey" ] || return 0
  # A small command file of our own opens Terminal at the reinstall.
  command="$SUPPORT/Reinstall Fixkey.command"
  printf '#!/bin/bash\ncd %q && ./fixkey reinstall\n' "$REPO" >"$command"
  chmod 700 "$command"
  if [ -n "${FIXKEY_DRY_RUN:-}" ]; then echo "OPEN: $command" >&2; else open "$command"; fi
}

if [ "$left" -gt 0 ]; then
  [ "$STATE" = "soon $EXPIRY" ] && exit 0
  echo "soon $EXPIRY" >"$STATE_FILE"
  offer_reinstall "$(t "Fixkey stops working on your iPhone on $when, when the free Apple ID's 7 days end. Reinstall now for 7 more days: connect the iPhone with its cable, unlock it, and click Reinstall." \
    "Fixkey holder op med at virke på din iPhone $when, når det gratis Apple-id's 7 dage er gået. Geninstaller nu for 7 dage mere: forbind iPhonen med kablet, lås den op, og klik Geninstaller.")"
  exit 0
fi

# Ended: ask at most every 12 hours until a new build is installed, which changes the expiry.
case "$STATE" in "ended $EXPIRY "*) [ $((NOW - ${STATE##* })) -lt 43200 ] && exit 0 ;; esac
echo "ended $EXPIRY $NOW" >"$STATE_FILE"
offer_reinstall "$(t "Fixkey has stopped working on your iPhone: the free Apple ID's 7 days are over. Connect the iPhone with its cable, unlock it, and click Reinstall." \
  "Fixkey er holdt op med at virke på din iPhone: det gratis Apple-id's 7 dage er gået. Forbind iPhonen med kablet, lås den op, og klik Geninstaller.")"
