#!/bin/bash
# Copyright © 2026 Mehmet Ergene. Licensed under CC BY-NC 4.0: non-commercial use only, credit required. See LICENSE.
#
# Renews Fixkey on the iPhone by itself before a free Apple ID's 7 days end, and reminds you when it can't.
# ./fixkey reminder on copies this script to ~/Library/Application Support/Fixkey, and macOS runs it every few hours.
# It reads only its own files there:
#   expiry          when the installed build stops working (seconds since 1970), written by ./fixkey reinstall
#   reminder.conf   REPO=<the Fixkey folder> and LANGUAGE=en|da
#   reminder.state  what it has already shown
#   source/         the copy of Fixkey that ./fixkey renew builds from (renew.last: when it last tried)
# From 2 days before the end it runs ./fixkey renew over Wi-Fi, at most every 3 hours. If that doesn't work, it
# reminds you the day before, and again after the end (at most every 12 hours), offering to reinstall.
#
# Testing: FIXKEY_SUPPORT_DIR=<folder> FIXKEY_NOW=<seconds> FIXKEY_DRY_RUN=<button to click>
#          FIXKEY_RENEW_COMMAND=<stands in for ./fixkey> FIXKEY_RENEW_LOG=<file> remind.sh

SUPPORT=${FIXKEY_SUPPORT_DIR:-"$HOME/Library/Application Support/Fixkey"}
NOW=${FIXKEY_NOW:-$(date +%s)}
STATE_FILE="$SUPPORT/reminder.state"
RENEW=${FIXKEY_RENEW_COMMAND:-"$SUPPORT/source/fixkey"}
RENEW_LOG=${FIXKEY_RENEW_LOG:-"$HOME/Library/Logs/Fixkey/renew.log"}

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

notify() {
  if [ -n "${FIXKEY_DRY_RUN:-}" ]; then
    printf 'NOTIFY: %s\n' "$1" >&2
    return
  fi
  osascript -e "display notification \"$1\" with title \"Fixkey\"" >/dev/null 2>&1
}

when() { t "$(LC_ALL=en_US.UTF-8 date -r "$1" '+%A at %H:%M')" "$(LC_ALL=da_DK.UTF-8 date -r "$1" '+%A kl. %H.%M')"; }

left=$((EXPIRY - NOW))
[ "$left" -le $((2 * 86400)) ] || exit 0
mkdir -p "$SUPPORT"

# Runs ./fixkey renew, at most every 3 hours. Prints ok, later (not now, or the iPhone can't be reached),
# signin (Xcode needs the Apple ID again) or failed.
try_renew() {
  local last
  last=$(tr -cd '0-9' 2>/dev/null <"$SUPPORT/renew.last")
  if [ -n "$last" ] && [ $((NOW - last)) -lt 10800 ] || [ ! -x "$RENEW" ]; then
    echo later
    return
  fi
  echo "$NOW" >"$SUPPORT/renew.last"
  mkdir -p "$(dirname "$RENEW_LOG")"
  "$RENEW" renew --lang "${LANGUAGE:-en}" >>"$RENEW_LOG" 2>&1
  case $? in 0) echo ok ;; 3) echo later ;; 4) echo signin ;; *) echo failed ;; esac
}

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

result=$(try_renew)
if [ "$result" = ok ]; then
  renewed=$(tr -cd '0-9' <"$SUPPORT/expiry")
  notify "$(t "Fixkey renewed itself on your iPhone. It works until $(when "${renewed:-$EXPIRY}")." \
    "Fixkey har fornyet sig selv på din iPhone. Den virker til $(when "${renewed:-$EXPIRY}").")"
  exit 0
fi

signin=$(t "Xcode needs you to sign in to your Apple ID again: open Xcode › Settings › Apple Accounts and sign in." \
  "Xcode skal have dig til at logge ind med dit Apple-id igen: åbn Xcode › Settings › Apple Accounts, og log ind.")

if [ "$left" -gt 0 ]; then
  case "$STATE" in "soon $EXPIRY" | "signin $EXPIRY") exit 0 ;; esac
  if [ "$result" = signin ]; then
    echo "signin $EXPIRY" >"$STATE_FILE"
    offer_reinstall "$(t "Fixkey couldn't renew itself on your iPhone. $signin Then click Reinstall, or let Fixkey renew itself." \
      "Fixkey kunne ikke forny sig selv på din iPhone. $signin Klik så Geninstaller, eller lad Fixkey forny sig selv.")"
    exit 0
  fi
  [ "$left" -le 86400 ] || exit 0
  echo "soon $EXPIRY" >"$STATE_FILE"
  offer_reinstall "$(t "Fixkey stops working on your iPhone on $(when "$EXPIRY") and couldn't renew itself yet. Put the iPhone on the same Wi-Fi as this Mac, or connect it with its cable, unlock it, and click Reinstall." \
    "Fixkey holder op med at virke på din iPhone $(when "$EXPIRY") og kunne ikke forny sig selv endnu. Sæt iPhonen på samme Wi-Fi som denne Mac, eller forbind den med kablet, lås den op, og klik Geninstaller.")"
  exit 0
fi

# Ended: ask at most every 12 hours until a new build is installed, which changes the expiry.
case "$STATE" in "ended $EXPIRY "*) [ $((NOW - ${STATE##* })) -lt 43200 ] && exit 0 ;; esac
echo "ended $EXPIRY $NOW" >"$STATE_FILE"
if [ "$result" = signin ]; then
  offer_reinstall "$(t "Fixkey has stopped working on your iPhone, and it couldn't renew itself. $signin Then click Reinstall." \
    "Fixkey er holdt op med at virke på din iPhone, og den kunne ikke forny sig selv. $signin Klik så Geninstaller.")"
else
  offer_reinstall "$(t "Fixkey has stopped working on your iPhone: the free Apple ID's 7 days are over. Put the iPhone on the same Wi-Fi as this Mac, or connect it with its cable, unlock it, and click Reinstall." \
    "Fixkey er holdt op med at virke på din iPhone: det gratis Apple-id's 7 dage er gået. Sæt iPhonen på samme Wi-Fi som denne Mac, eller forbind den med kablet, lås den op, og klik Geninstaller.")"
fi
