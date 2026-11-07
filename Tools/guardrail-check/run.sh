#!/bin/bash
# Copyright © 2026 Mehmet Ergene. Licensed under CC BY-NC 4.0: non-commercial use only, credit required. See LICENSE.
# Runs the guardrail checks on the Mac (no model needed).
set -euo pipefail
cd "$(dirname "$0")/../.."
out="$(mktemp -d)/guardrail-check"
swiftc -o "$out" Shared/Guardrails.swift Tools/guardrail-check/main.swift
"$out"
