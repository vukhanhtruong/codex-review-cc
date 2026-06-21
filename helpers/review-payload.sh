# Build the code-review surface: tracked diffs (secret-redacted) + untracked contents,
# bounded by per-file and total-size caps. Self-contained (sr_is_sensitive lives here).

# rc 0 if the path's basename looks like a secret/credential file.
sr_is_sensitive() { # $1 = path
  case "${1##*/}" in
    .env|.env.*|*.env|*.pem|*.key|*.p12|*.pfx|*.keystore|*.crt|id_rsa|id_dsa|id_ecdsa|id_ed25519|*credential*|*secret*) return 0 ;;
    *) return 1 ;;
  esac
}

# Diff changed tracked files for a spec (<mb>...HEAD or HEAD), skipping any change whose old
# OR new basename is sensitive (covers renames away from a secret name). -M surfaces renames.
_sr_tracked_diff() { # $1 = diff spec
  local spec="$1" st p1 p2 newp; local -a safe=()
  while IFS=$'\t' read -r st p1 p2; do
    [ -n "$st" ] || continue
    newp="${p2:-$p1}"
    if sr_is_sensitive "$p1" || { [ -n "$p2" ] && sr_is_sensitive "$p2"; }; then
      printf '\n=== diff (skipped: sensitive filename): %s ===\n' "$newp"
    else
      safe+=("$newp")
    fi
  done < <(git diff --name-status --find-renames=1% $spec)
  [ ${#safe[@]} -gt 0 ] && git diff --find-renames=1% $spec -- "${safe[@]}"
  return 0
}

# Raw review surface: committed + working tracked diffs (secret-redacted) + untracked contents
# (skipping sensitive/binary/oversized files with markers).
_sr_payload_body() { # $1 = merge-base
  local mb="$1" f sz fmax=$((256 * 1024))
  _sr_tracked_diff "$mb...HEAD"
  _sr_tracked_diff "HEAD"
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    if sr_is_sensitive "$f"; then printf '\n=== untracked (skipped: sensitive filename): %s ===\n' "$f"; continue; fi
    if [ -s "$f" ] && ! grep -Iq . "$f" 2>/dev/null; then printf '\n=== untracked (skipped: binary): %s ===\n' "$f"; continue; fi
    sz="$(wc -c < "$f" 2>/dev/null || echo 0)"
    if [ "$sz" -gt "$fmax" ]; then printf '\n=== untracked (skipped: %s bytes > cap): %s ===\n' "$sz" "$f"; continue; fi
    printf '\n=== untracked: %s ===\n' "$f"
    cat -- "$f"
  done < <(git ls-files --others --exclude-standard)
}

# Mask credential-shaped tokens + secret-named assignment values in stdin.
# Complements sr_is_sensitive (whole-file skipping): this catches secret VALUES
# embedded in otherwise-normal tracked/untracked files, which filename rules miss.
# Provider-token rules are quote-agnostic; the keyword rule masks double-quoted
# values on lines naming a credential (single-quoted values rely on token shape).
sr_redact_secrets() {
  awk '
  {
    l=$0
    gsub(/(sk|pk|rk)-[A-Za-z0-9_-]+/, "***REDACTED-KEY***", l)
    gsub(/AKIA[0-9A-Z]+/, "***REDACTED-AWS***", l)
    gsub(/(ghp|gho|ghu|ghs|ghr|github_pat)_[A-Za-z0-9_]+/, "***REDACTED-GH***", l)
    gsub(/AIza[0-9A-Za-z_-]+/, "***REDACTED-GCP***", l)
    gsub(/xox[baprs]-[A-Za-z0-9-]+/, "***REDACTED-SLACK***", l)
    gsub(/eyJ[A-Za-z0-9_.=-]+/, "***REDACTED-JWT***", l)
    if (l ~ /BEGIN [A-Z ]*PRIVATE KEY/) l = "***REDACTED-PRIVATE-KEY-BLOCK***"
    low = tolower(l)
    if (low ~ /(api[_-]?key|secret|token|password|passwd|access[_-]?key|client[_-]?secret|private[_-]?key|credential|bearer)/)
      gsub(/"[^"]+"/, "\"***REDACTED***\"", l)
    print l
  }'
}

# Full review surface, bounded by a total-size cap so a huge diff/many files can't blow the prompt.
sr_review_payload() { # $1 = merge-base
  local out totalmax=$((2 * 1024 * 1024))
  out="$(_sr_payload_body "$1" | sr_redact_secrets)"
  if [ "${#out}" -gt "$totalmax" ]; then
    printf '%s\n\n=== payload truncated at %s bytes (total cap) ===\n' "${out:0:$totalmax}" "$totalmax"
  else
    printf '%s\n' "$out"
  fi
}
