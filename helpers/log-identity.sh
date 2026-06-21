# /tmp log path + stable per-repo identity.

# Build the /tmp log path. Caller passes already-sanitized parts.
sr_log_path() { # $1 = repo basename, $2 = safe name
  printf '/tmp/spec-review-%s-%s.log' "$1" "$2"
}

# Short stable hash of the repo root path — for a collision-free /tmp log identity.
sr_root_hash() {
  local root
  root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
  printf '%s' "$root" | { sha256sum 2>/dev/null || shasum -a 256; } | cut -c1-8
}
