#!/usr/bin/env bash
# Shared library for /codex:spec-review and /codex:code-review.
# Thin barrel: sources single-responsibility helpers from ./helpers/. No god file.
# Helpers are pure (no persistent shell-state or fs side effects) except sr_stamp_marker.
if [ -z "${BASH_VERSION:-}" ]; then
  echo "codex-lib.sh requires bash (run the command's shell blocks with bash)" >&2
  return 1 2>/dev/null || exit 1
fi
_codex_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
for _h in "$_codex_lib_dir"/helpers/*.sh; do . "$_h"; done
unset _h _codex_lib_dir
