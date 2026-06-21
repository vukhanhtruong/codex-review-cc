#!/usr/bin/env bash
# Manual (non-plugin) install. Copies the commands, codex-lib.sh + helpers/, and the
# checklists into ${CLAUDE_HOME:-$HOME/.claude}/commands/codex so /codex:* resolves
# without the plugin marketplace. Prefer `/plugin install` (see README) when possible.
set -euo pipefail
SRC="$(cd "$(dirname "$0")" && pwd)"
DEST="${CLAUDE_HOME:-$HOME/.claude}/commands/codex"
mkdir -p "$DEST/helpers" "$DEST/reference" "$DEST/schemas"
cp "$SRC/commands/spec-review.md" "$DEST/spec-review.md"
cp "$SRC/commands/code-review.md" "$DEST/code-review.md"
cp "$SRC/codex-lib.sh" "$DEST/codex-lib.sh"
cp "$SRC/helpers/"*.sh "$DEST/helpers/"
cp "$SRC/reference/security-checklist.md" "$DEST/reference/security-checklist.md"
cp "$SRC/reference/reliability-checklist.md" "$DEST/reference/reliability-checklist.md"
cp "$SRC/reference/simplification-checklist.md" "$DEST/reference/simplification-checklist.md"
cp "$SRC/schemas/review-output.schema.json" "$DEST/schemas/review-output.schema.json"
echo "Installed /codex:spec-review + /codex:code-review (lib + helpers + checklists) to $DEST"
