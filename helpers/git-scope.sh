# Resolve + validate the git review scope (base..HEAD).

# Prints "<merge-base>\t<branch-label>".
# rc 2 not-a-worktree, rc 3 base-not-a-commit, rc 4 no-merge-base. Detached HEAD -> detached-<sha>.
sr_diff_scope() { # $1 = base ref
  local base="$1" branch mb
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "not a git work tree" >&2; return 2; }
  git rev-parse --verify --quiet "${base}^{commit}" >/dev/null 2>&1 || { echo "base '$base' is not a commit" >&2; return 3; }
  mb="$(git merge-base "$base" HEAD 2>/dev/null)" || { echo "no merge-base with '$base'" >&2; return 4; }
  [ -n "$mb" ] || { echo "no merge-base with '$base'" >&2; return 4; }
  branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null)"
  [ "$branch" = "HEAD" ] && branch="detached-$(git rev-parse --short HEAD)"
  printf '%s\t%s\n' "$mb" "$branch"
}
