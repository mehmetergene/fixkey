#!/bin/bash
# Copyright © 2026 Mehmet Ergene. Licensed under CC BY-NC 4.0: non-commercial use only, credit required. See LICENSE.
# Runs Fixkey's tests and prints one line per suite. Full output goes to build/test-*.log.
#   Tools/test.sh               quick checks, no model or simulator: guardrails, shared code, relay, reminder, setup
#   Tools/test.sh --simulator   also the keyboard unit tests in the iOS simulator
#   Tools/test.sh --model       also the model evaluation (needs Llama.app with the model; a few minutes)
set -uo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
failed=0

run() {
  local name=$1 log="build/test-$1.log"
  shift
  if "$@" >"$log" 2>&1; then
    # Xcode prints its summary out of order, so prefer the line that counts the tests.
    printf 'ok    %-12s %s\n' "$name" "$( (grep -E 'Executed [0-9]+ tests?,' "$log" || grep -v '^$' "$log") | tail -1 | sed 's/^[[:space:]]*//')"
  else
    printf 'FAIL  %-12s see %s\n' "$name" "$log"
    failed=1
  fi
}

simulator() {
  local device
  device=$(xcrun simctl list devices available | grep -m1 -oE 'iPhone [^(]+' | sed 's/ *$//')
  xcodebuild -project Fixkey.xcodeproj -scheme Fixkey -destination "platform=iOS Simulator,name=$device" \
    -derivedDataPath build/sim test
}

run guardrails Tools/guardrail-check/run.sh
run core Tools/core-check/run.sh
run relay python3 -I Tools/lan-relay/test_relay.py
run reminder Tools/reminder/test.sh
run setup bash -c 'bash -n fixkey && bash -n "Fixkey Setup.command" && ./fixkey help >/dev/null && echo "The setup scripts parse and run."'
for option in "$@"; do
  case "$option" in
    --simulator) run simulator simulator ;;
    --model) run model Tools/model-eval/run.sh unsloth/Qwen3.5-4B-GGUF:Q4_K_M qwen nothink ;;
    *) echo "Unknown option: $option" >&2; exit 2 ;;
  esac
done
exit $failed
