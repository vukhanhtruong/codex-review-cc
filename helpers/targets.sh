# Locate the review target docs: spec + plan (spec-review) and design docs (code-review).
# Depends on naming.sh (sr_derive_slug, sr_plan_slug).

# Select one spec. rc 0 -> prints path; rc 3 -> ambiguous (prints candidates); rc 4 -> none.
# On rc 4, the searched glob + available candidates go to stderr (spec requirement).
sr_select_spec() { # $1 = specs dir, $2 = name (optional)
  local dir="$1" name="${2:-}" f lb lname
  local all=() m=()
  local _ng; _ng="$(shopt -p nullglob || true)"; shopt -s nullglob
  all=("$dir"/*-design.md)
  eval "$_ng"
  if [ -n "$name" ]; then
    lname="$(printf '%s' "$name" | tr 'A-Z' 'a-z')"
    for f in "${all[@]}"; do
      lb="$(printf '%s' "${f##*/}" | tr 'A-Z' 'a-z')"
      case "$lb" in *"$lname"*) m+=("$f");; esac
    done
  else
    m=("${all[@]}")
  fi
  if [ "${#m[@]}" -eq 0 ]; then
    { echo "no spec matched: $dir/*-design.md (name='$name')"; echo "candidates:"; printf '  %s\n' "${all[@]}"; } >&2
    return 4
  fi
  if [ -n "$name" ] && [ "${#m[@]}" -gt 1 ]; then printf '%s\n' "${m[@]}"; return 3; fi
  printf '%s\n' "${m[@]}" | sort | tail -1   # newest by filename date prefix
}

# Find the plan whose slug equals $2. rc 0 -> prints path; rc 1 -> none; rc 3 -> ambiguous.
sr_match_plan() { # $1 = plans dir, $2 = slug
  local dir="$1" slug="$2" f m=()
  local _ng; _ng="$(shopt -p nullglob || true)"; shopt -s nullglob
  for f in "$dir"/*.md; do
    [ "$(sr_plan_slug "${f##*/}")" = "$slug" ] && m+=("$f")
  done
  eval "$_ng"
  [ "${#m[@]}" -eq 0 ] && return 1
  [ "${#m[@]}" -gt 1 ] && { printf '%s\n' "${m[@]}"; return 3; }
  printf '%s\n' "${m[0]}"
}

# Resolve the review target. Prints a TAB line:
#   spec\t<specpath>            or   plan\t<planpath>\t<specpath>
# rc: 3 ambiguous, 4 no spec, 5 forced plan but none/ambiguous.
sr_resolve_target() { # $1 specs, $2 plans, $3 force(spec|plan|""), $4 name("")
  local specs="$1" plans="$2" force="${3:-}" name="${4:-}"
  local spec slug plan rc target
  spec="$(sr_select_spec "$specs" "$name")"; rc=$?
  if [ "$rc" -ne 0 ]; then [ "$rc" -eq 3 ] && printf '%s\n' "$spec"; return "$rc"; fi
  slug="$(sr_derive_slug "${spec##*/}")"
  plan="$(sr_match_plan "$plans" "$slug")"; rc=$?
  if [ "$rc" -eq 3 ]; then printf '%s\n' "$plan"; return 3; fi
  if [ "$force" = "spec" ]; then target=spec
  elif [ "$force" = "plan" ]; then [ "$rc" -ne 0 ] && return 5; target=plan
  elif [ "$rc" -eq 0 ]; then target=plan
  else target=spec; fi
  if [ "$target" = "plan" ]; then printf 'plan\t%s\t%s\n' "$plan" "$spec"
  else printf 'spec\t%s\n' "$spec"; fi
}

# Resolve design docs for a branch/name hint: prints "<spec>\t<plan>" (either may be empty).
# Prefers docs whose basename contains the branch slug; falls back to the newest of each.
# rc 0 always (pipes to head). Reference these paths to Codex; do not embed their contents.
sr_design_docs() { # $1 = branch label or name hint
  local hint slug specs=docs/superpowers/specs plans=docs/superpowers/plans spec plan
  hint="${1##*/}"
  slug="$(printf '%s' "$hint" | sed -E 's/[^a-zA-Z0-9]+/-/g')"
  spec="$(ls -t "$specs"/*"$slug"*-design.md 2>/dev/null | head -1)"
  [ -n "$spec" ] || spec="$(ls -t "$specs"/*-design.md 2>/dev/null | head -1)"
  plan="$(ls -t "$plans"/*"$slug"*.md 2>/dev/null | head -1)"
  [ -n "$plan" ] || plan="$(ls -t "$plans"/*.md 2>/dev/null | head -1)"
  printf '%s\t%s\n' "$spec" "$plan"
}
