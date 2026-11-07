#!/bin/bash
# Copyright © 2026 Mehmet Ergene. Licensed under CC BY-NC 4.0: non-commercial use only, credit required. See LICENSE.
# Builds and runs the model evaluation against Llama.app. See main.swift for arguments.
set -euo pipefail
cd "$(dirname "$0")/../.."
out="$(mktemp -d)/model-eval"
swiftc -o "$out" Shared/*.swift Tools/model-eval/main.swift
"$out" "$@"
