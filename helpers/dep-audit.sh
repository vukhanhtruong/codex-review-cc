# Dependency-audit summary — auxiliary, non-blocking.

# One-line dependency-audit summary. rc 0 always.
# Captures rc explicitly (a piped `tail` would mask audit failure).
sr_audit_summary() {
  local out rc
  # capture rc with if-form so a nonzero/timeout audit never aborts a `set -e` caller
  if   [ -f package-lock.json ]; then if out="$(timeout 60 npm audit --omit=dev 2>&1)"; then rc=0; else rc=$?; fi
  elif [ -f pnpm-lock.yaml ];    then if out="$(timeout 60 pnpm audit 2>&1)";          then rc=0; else rc=$?; fi
  elif [ -f requirements.txt ] || [ -f poetry.lock ]; then if out="$(timeout 60 pip-audit 2>&1)"; then rc=0; else rc=$?; fi
  else echo "dep-audit: skipped (no lockfile)"; return 0
  fi
  if   [ "$rc" -eq 124 ]; then echo "dep-audit: unavailable (timeout)"
  elif [ "$rc" -ne 0 ];   then echo "dep-audit: unavailable (rc=$rc)"
  else echo "dep-audit: $(printf '%s' "$out" | tr '\n' ' ' | tail -c 200)"
  fi
  return 0
}
