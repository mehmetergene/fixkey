#!/bin/bash
# Copyright © 2026 Mehmet Ergene. Licensed under CC BY-NC 4.0: non-commercial use only, credit required. See LICENSE.
# Starts the Wi-Fi relay for Fixkey on the iPhone (same as ./fixkey relay). Stop it with Ctrl+C when done.
set -euo pipefail
exec python3 -I "$(dirname "$0")/relay.py" "$@"
