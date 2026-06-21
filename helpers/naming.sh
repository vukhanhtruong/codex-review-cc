# Name and slug derivation — pure string transforms, no I/O.

# Replace any char outside [A-Za-z0-9._-] with a dash.
sr_sanitize_name() { # $1 = raw name
  printf '%s' "$1" | sed 's/[^A-Za-z0-9._-]/-/g'
}

# Spec basename -> slug: drop leading YYYY-MM-DD- and trailing -design.md / .md / -design.
sr_derive_slug() { # $1 = spec filename (basename or path)
  local b="${1##*/}"
  b="$(printf '%s' "$b" | sed -E 's/^[0-9]{4}-[0-9]{2}-[0-9]{2}-//')"
  b="$(printf '%s' "$b" | sed -E 's/(-design)?\.md$//; s/-design$//')"
  printf '%s' "$b"
}

# Plan basename -> slug: drop leading YYYY-MM-DD- and trailing .md (plans carry no -design suffix).
sr_plan_slug() { # $1 = plan filename (basename or path)
  local b="${1##*/}"
  printf '%s' "$b" | sed -E 's/^[0-9]{4}-[0-9]{2}-[0-9]{2}-//; s/\.md$//'
}
