#!/bin/bash
# Copyright © 2026 Mehmet Ergene. Licensed under CC BY-NC 4.0: non-commercial use only, credit required. See LICENSE.
# Checks the shared code on the Mac (no model needed): diff and partial accept, clean-up, check range, errors.
set -euo pipefail
cd "$(dirname "$0")/../.."
out="$(mktemp -d)/core-check"
swiftc -o "$out" Shared/*.swift Tools/core-check/main.swift
"$out"
