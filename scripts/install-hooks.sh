#!/bin/bash
# Use the repository's git hooks (.githooks/), which check commit messages for Conventional Commits.
set -euo pipefail
cd "$(dirname "$0")/.."
git config core.hooksPath .githooks
chmod +x .githooks/*
echo "Git hooks enabled (core.hooksPath = .githooks)."
