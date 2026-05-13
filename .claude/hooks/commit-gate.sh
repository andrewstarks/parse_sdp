#!/bin/bash
# Pre-commit gate: enforces doc sync when Lua source files are staged.

STAGED=$(git diff --cached --name-only 2>/dev/null)

# Only enforce when source files are being committed.
STAGED_LUA=$(echo "$STAGED" | grep -E '(^|/).*\.lua$' || true)
[ -z "$STAGED_LUA" ] && exit 0

MISSING=""
echo "$STAGED" | grep -q 'CHANGELOG\.md' || MISSING="$MISSING\n  - CHANGELOG.md not staged"
echo "$STAGED" | grep -q 'PLAN\.md'      || MISSING="$MISSING\n  - PLAN.md not staged"

# CHANGELOG.md must have at least one bullet under [Unreleased].
UNRELEASED=$(awk '/^## \[Unreleased\]/{f=1;next} f&&/^## /{exit} f&&/^- /{print;exit}' CHANGELOG.md 2>/dev/null)
[ -z "$UNRELEASED" ] && MISSING="$MISSING\n  - CHANGELOG.md has no entries under [Unreleased]"

if [ -n "$MISSING" ]; then
  printf 'Commit gate failed — fix before committing:%b\n' "$MISSING"
  exit 2
fi

exit 0
