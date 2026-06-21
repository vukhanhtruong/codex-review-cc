# Parse Codex output: verdict, finding IDs, per-finding status, and resume state.

# Verdict = the single VERDICT line, which must also be the last non-empty line.
# Prints APPROVED | CHANGES_REQUESTED | PARSE_FAIL (rc 1 on failure).
sr_parse_verdict() { # $1 = file with codex stdout
  local n last
  n="$(grep -c '^VERDICT: ' "$1")"
  last="$(sed -e 's/[[:space:]]*$//' "$1" | sed '/^$/d' | tail -1)"
  if [ "$n" -ne 1 ]; then printf 'PARSE_FAIL'; return 1; fi
  case "$last" in
    'VERDICT: APPROVED')          printf 'APPROVED' ;;
    'VERDICT: CHANGES_REQUESTED') printf 'CHANGES_REQUESTED' ;;
    *)                            printf 'PARSE_FAIL'; return 1 ;;
  esac
}

# Print finding IDs from "## Finding <ID>" headers, one per line.
sr_finding_ids() { # $1 = file
  grep -E '^## Finding ' "$1" | sed -E 's/^## Finding +([^[:space:]]+).*/\1/'
}

# Parse a Codex round: one "id status" line per "## Finding <id>" block.
sr_round_findings() { # $1 = roundfile
  awk '
    /^## Finding /{ if(id!="") print id, st; id=$3; st=""; next }
    /^STATUS:/{ st=$2 }
    END{ if(id!="") print id, st }
  ' "$1"
}

# Still-open finding IDs from the LAST contiguous FINDING block (latest status per id,
# sorted); falls back to the last 'OPEN: <ids>' line. rc 0 always (set -e safe).
sr_open_findings() { # $1 = log file
  [ -f "$1" ] || return 0
  if grep -qE '^FINDING ' "$1" 2>/dev/null; then
    awk '
      /^FINDING /{ if(!inblock){ delete status; inblock=1 }
                   st=""; for(i=1;i<=NF;i++) if($i ~ /^STATUS=/) st=substr($i,8); status[$2]=st; next }
      { inblock=0 }
      END{ for(k in status) if(status[k]=="open") print k }
    ' "$1" | sort | tr '\n' ' ' | sed 's/ $//'
    return 0
  fi
  grep -E '^OPEN: ' "$1" 2>/dev/null | tail -1 | sed -E 's/^OPEN: //'
  return 0
}
