#!/usr/bin/env bash
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
DEST="$(mktemp -d)"
CLAUDE_HOME="$DEST" bash "$HERE/../install.sh" >/dev/null 2>&1
rc=$?
ok=0
C="$DEST/commands/codex"
[ "$rc" -eq 0 ] \
  && [ -f "$C/spec-review.md" ] \
  && [ -f "$C/code-review.md" ] \
  && [ -f "$C/codex-lib.sh" ] \
  && [ -d "$C/helpers" ] \
  && [ -f "$C/helpers/naming.sh" ] \
  && [ -f "$C/helpers/review-payload.sh" ] \
  && [ -f "$C/reference/security-checklist.md" ] \
  && [ -f "$C/reference/reliability-checklist.md" ] \
  && [ -f "$C/reference/simplification-checklist.md" ] \
  && ok=1
rm -rf "$DEST"
if [ "$ok" -eq 1 ]; then echo "install OK"; else echo "install FAIL (rc=$rc)"; exit 1; fi
