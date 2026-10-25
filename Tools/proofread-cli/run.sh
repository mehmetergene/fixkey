#!/bin/bash
# Copyright © 2026 Mehmet Ergene. Licensed under CC BY-NC 4.0: non-commercial use only, credit required. See LICENSE.
# Builds and runs the proofread CLI (macOS) against Llama.app. Pass sentences as arguments to try your own.
set -euo pipefail
cd "$(dirname "$0")/../.."
out="$(mktemp -d)/proofread-cli"
swiftc -o "$out" Shared/*.swift Tools/proofread-cli/main.swift
"$out" "$@"
