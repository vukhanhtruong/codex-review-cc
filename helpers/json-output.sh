# JSON-output mode for /codex:code-review: parse Codex's --output-schema response.
# Requires a JSON parser (node). These functions mirror the contracts in findings.sh
# (sr_parse_verdict / sr_round_findings / sr_finding_ids) so the command's adjudication
# logic stays parser-agnostic — only the function names swap. codex validates the schema
# on its side; sr_json_validate re-checks structure here (defense in depth, fail-closed).

# rc 0 if JSON-output mode is usable (a JSON parser is on PATH).
sr_have_json() { command -v node >/dev/null 2>&1; }

# Structural contract check. rc 0 ok, rc 1 fail. Rejects: invalid JSON; verdict not in
# enum; coverage missing any of the 5 lenses (int>=0); findings not an array; a finding
# id not matching R<n>F<n>; duplicate ids; CHANGES_REQUESTED with zero findings.
sr_json_validate() { # $1 = json file
  node -e '
    const fs = require("fs");
    let d; try { d = JSON.parse(fs.readFileSync(process.argv[1], "utf8")); } catch { process.exit(1); }
    if (typeof d !== "object" || d === null) process.exit(1);
    if (!["APPROVED", "CHANGES_REQUESTED"].includes(d.verdict)) process.exit(1);
    const L = ["correctness", "security", "reliability", "simplification", "performance"];
    if (typeof d.coverage !== "object" || d.coverage === null) process.exit(1);
    for (const l of L) if (!Number.isInteger(d.coverage[l]) || d.coverage[l] < 0) process.exit(1);
    if (!Array.isArray(d.findings)) process.exit(1);
    const ids = new Set();
    for (const f of d.findings) {
      if (typeof f !== "object" || f === null) process.exit(1);
      if (typeof f.id !== "string" || !/^R[0-9]+F[0-9]+$/.test(f.id)) process.exit(1);
      if (ids.has(f.id)) process.exit(1);
      ids.add(f.id);
    }
    if (d.verdict === "CHANGES_REQUESTED" && d.findings.length === 0) process.exit(1);
    process.exit(0);
  ' "$1"
}

# Print APPROVED | CHANGES_REQUESTED (assumes already validated). Empty if unreadable.
sr_json_verdict() { # $1 = json file
  node -e 'process.stdout.write((JSON.parse(require("fs").readFileSync(process.argv[1],"utf8")).verdict)||"")' "$1" 2>/dev/null
}

# One "id status" line per finding (status defaults to "open"). Mirrors sr_round_findings.
sr_json_round_findings() { # $1 = json file
  node -e 'for(const f of (JSON.parse(require("fs").readFileSync(process.argv[1],"utf8")).findings||[])) console.log(f.id, f.status||"open")' "$1" 2>/dev/null
}

# Finding ids, one per line. Mirrors sr_finding_ids.
sr_json_finding_ids() { # $1 = json file
  node -e 'for(const f of (JSON.parse(require("fs").readFileSync(process.argv[1],"utf8")).findings||[])) console.log(f.id)' "$1" 2>/dev/null
}

# Human summary rows for the terminate report: "id | lens | severity | confidence | file:start-end".
sr_json_table() { # $1 = json file
  node -e 'for(const f of (JSON.parse(require("fs").readFileSync(process.argv[1],"utf8")).findings||[])) console.log([f.id,f.lens,f.severity,f.confidence,(f.file||"")+":"+(f.line_start||"?")+"-"+(f.line_end||"?")].join(" | "))' "$1" 2>/dev/null
}
