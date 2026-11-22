#!/bin/bash
# Self-check of the parts that don't need a Touch Bar.
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p build
swiftc -parse-as-library Draft.swift ClaudeChat.swift Sessions.swift Plan.swift test_draft.swift -o build/selfcheck
build/selfcheck
