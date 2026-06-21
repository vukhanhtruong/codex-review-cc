#!/usr/bin/env bash
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
. "$ROOT/codex-lib.sh"

pass=0; fail=0
assert_eq() { # $1=desc $2=expected $3=actual
  if [ "$2" = "$3" ]; then pass=$((pass+1));
  else fail=$((fail+1)); printf 'FAIL: %s\n  expected: [%s]\n  actual:   [%s]\n' "$1" "$2" "$3"; fi
}
assert_rc() { # $1=desc $2=expected_rc $3=actual_rc
  if [ "$2" = "$3" ]; then pass=$((pass+1));
  else fail=$((fail+1)); printf 'FAIL: %s\n  expected rc: %s actual rc: %s\n' "$1" "$2" "$3"; fi
}

# --- sr_sanitize_name ---
assert_eq "sanitize spaces/slashes/bang" "a-b-c-" "$(sr_sanitize_name 'a b/c!')"
assert_eq "sanitize keeps dot dash under" "ok._-name" "$(sr_sanitize_name 'ok._-name')"
assert_eq "sanitize strips path sep" "x-y" "$(sr_sanitize_name 'x/y')"

# --- sr_log_path ---
assert_eq "log path" \
  "/tmp/spec-review-ces-harness-creator-spec-review-command.log" \
  "$(sr_log_path ces-harness-creator spec-review-command)"

# --- sr_derive_slug (spec basename -> slug) ---
assert_eq "spec slug strips date+design" "spec-review-command" \
  "$(sr_derive_slug '2026-06-17-spec-review-command-design.md')"
assert_eq "spec slug no design suffix" "evals-dataset" \
  "$(sr_derive_slug '2026-06-09-evals-dataset.md')"

# --- sr_plan_slug (plan basename -> slug) ---
assert_eq "plan slug strips date+md" "subproject-claude-md-v2" \
  "$(sr_plan_slug '2026-06-16-subproject-claude-md-v2.md')"

# --- target resolution ---
T="$(mktemp -d)"; mkdir -p "$T/specs" "$T/plans"
: > "$T/specs/2026-01-01-alpha-design.md"
: > "$T/specs/2026-02-02-beta-design.md"
: > "$T/plans/2026-02-10-beta.md"

assert_eq "resolve auto -> plan for newest w/ plan" \
  "plan	$T/plans/2026-02-10-beta.md	$T/specs/2026-02-02-beta-design.md" \
  "$(sr_resolve_target "$T/specs" "$T/plans" '' '')"

assert_eq "resolve name=alpha -> spec (no plan)" \
  "spec	$T/specs/2026-01-01-alpha-design.md" \
  "$(sr_resolve_target "$T/specs" "$T/plans" '' alpha)"

assert_eq "resolve force spec" \
  "spec	$T/specs/2026-02-02-beta-design.md" \
  "$(sr_resolve_target "$T/specs" "$T/plans" spec '')"

: > "$T/plans/2026-03-03-beta.md"
sr_resolve_target "$T/specs" "$T/plans" '' '' >/dev/null 2>&1
assert_rc "resolve ambiguous plan -> rc3" 3 "$?"
amb="$(sr_resolve_target "$T/specs" "$T/plans" '' '' 2>/dev/null)"
case "$amb" in *2026-03-03-beta.md*) assert_eq "ambiguous plan lists candidates" "ok" "ok";; *) assert_eq "ambiguous plan lists candidates" "ok" "missing";; esac
rm "$T/plans/2026-03-03-beta.md"

# name 'a' matches both alpha and beta -> ambiguous spec, candidates printed
ambs="$(sr_resolve_target "$T/specs" "$T/plans" '' a 2>/dev/null)"
case "$ambs" in
  *alpha-design.md*beta-design.md*|*beta-design.md*alpha-design.md*) assert_eq "ambiguous spec lists candidates" "ok" "ok";;
  *) assert_eq "ambiguous spec lists candidates" "ok" "missing";;
esac

sr_resolve_target "$T/specs" "$T/plans" '' nonesuch >/dev/null 2>&1
assert_rc "resolve no spec -> rc4" 4 "$?"

# zero-match emits candidates to stderr
err="$(sr_select_spec "$T/specs" nonesuch 2>&1 >/dev/null || true)"
case "$err" in *alpha-design.md*) assert_eq "zero-match lists candidates" "ok" "ok";; *) assert_eq "zero-match lists candidates" "ok" "missing";; esac

# --- sr_parse_verdict (exactly one verdict line, and it is last non-empty) ---
V="$(mktemp)"
printf 'noise\n\nVERDICT: APPROVED\n\n' > "$V"
assert_eq "verdict approved (trailing blanks)" "APPROVED" "$(sr_parse_verdict "$V")"
printf 'stuff\nVERDICT: CHANGES_REQUESTED\n' > "$V"
assert_eq "verdict changes" "CHANGES_REQUESTED" "$(sr_parse_verdict "$V")"
printf 'VERDICT: CHANGES_REQUESTED\ntail\nVERDICT: APPROVED\n' > "$V"
out="$(sr_parse_verdict "$V")"; rc=$?
assert_eq "two verdicts -> PARSE_FAIL" "PARSE_FAIL" "$out"
assert_rc "two verdicts rc1" 1 "$rc"
printf 'verdict: approved\n' > "$V"
assert_eq "verdict lowercase -> PARSE_FAIL" "PARSE_FAIL" "$(sr_parse_verdict "$V")"
printf 'no verdict here\n' > "$V"
sr_parse_verdict "$V" >/dev/null; assert_rc "verdict missing rc1" 1 "$?"
rm -f "$V"

rm -rf "$T"
# --- sr_stamp_marker (upsert frontmatter reviewed: key) ---
D="$(mktemp)"
printf '# Title\n\nbody\n' > "$D"
sr_stamp_marker "$D" "codex-approved 2026-06-17"
assert_eq "marker created (line1)" "---" "$(sed -n 1p "$D")"
assert_eq "marker created (line2)" "reviewed: codex-approved 2026-06-17" "$(sed -n 2p "$D")"
assert_eq "marker created (line3 close)" "---" "$(sed -n 3p "$D")"
assert_eq "body preserved after block" "# Title" "$(sed -n 4p "$D")"

printf -- '---\ntitle: x\n---\n# T\n' > "$D"
sr_stamp_marker "$D" "codex-approved 2026-06-17"
assert_eq "existing fm keeps title" "title: x" "$(grep -m1 '^title:' "$D")"
assert_eq "existing fm gains reviewed" "reviewed: codex-approved 2026-06-17" "$(grep -m1 '^reviewed:' "$D")"

printf -- '---\nreviewed: old\n---\n# T\n' > "$D"
sr_stamp_marker "$D" "codex-approved 2026-06-17"
assert_eq "reviewed replaced value" "reviewed: codex-approved 2026-06-17" "$(grep -m1 '^reviewed:' "$D")"
assert_eq "reviewed not duplicated" "1" "$(grep -c '^reviewed:' "$D")"
rm -f "$D"

# --- sr_version_ge ---
sr_version_ge 0.140.0 0.140.0; assert_rc "ver equal -> ge" 0 "$?"
sr_version_ge 0.141.2 0.140.0; assert_rc "ver newer -> ge" 0 "$?"
sr_version_ge 0.139.9 0.140.0; assert_rc "ver older -> not ge" 1 "$?"

# --- sr_finding_ids ---
FN="$(mktemp)"
printf '## Finding F1\nx\n## Finding 2\ny\n' > "$FN"
assert_eq "finding ids" "F1 2" "$(sr_finding_ids "$FN" | tr '\n' ' ' | sed 's/ $//')"
rm -f "$FN"

# --- sr_open_findings (reads last OPEN: line from a log) ---
LG="$(mktemp)"
printf 'OPEN: F1 F2\nstuff\nOPEN: F3\n' > "$LG"
assert_eq "open findings last line" "F3" "$(sr_open_findings "$LG")"
printf 'no open marker\n' > "$LG"
assert_eq "open findings none -> empty" "" "$(sr_open_findings "$LG")"
rm -f "$LG"

# unclosed frontmatter (opening --- but no close) must still get the marker
D2="$(mktemp)"
printf -- '---\ntitle: x\nno close here\n' > "$D2"
sr_stamp_marker "$D2" "codex-approved 2026-06-17"
assert_eq "unclosed fm still gets reviewed" "reviewed: codex-approved 2026-06-17" "$(grep -m1 '^reviewed:' "$D2")"
rm -f "$D2"

# --- sr_finding_ids multi-word header ---
FN2="$(mktemp)"
printf '## Finding F1 extra words here\n## Finding 2\n' > "$FN2"
assert_eq "finding id first token only" "F1 2" "$(sr_finding_ids "$FN2" | tr '\n' ' ' | sed 's/ $//')"
rm -f "$FN2"

# --- command bash blocks must parse ---
CMD="$ROOT/commands/spec-review.md"
if [ -f "$CMD" ]; then
  bb="$(awk '/^```bash$/{f=1;next} /^```$/{f=0} f' "$CMD")"
  printf '%s\n' "$bb" | bash -n - 2>/dev/null
  assert_rc "command bash blocks parse" 0 "$?"
else
  assert_eq "command file exists" "exists" "missing"
fi

# --- FIX 1+2: stamp preserves the doc's file mode (no /tmp 0600 leak) ---
D2="$(mktemp)"; chmod 644 "$D2"; printf '# T\n' > "$D2"
sr_stamp_marker "$D2" "codex-approved 2026-06-17"
assert_eq "stamp preserves mode 644" "644" "$(stat -c %a "$D2")"
assert_eq "stamp still applied" "reviewed: codex-approved 2026-06-17" "$(grep -m1 '^reviewed:' "$D2")"
rm -f "$D2"

# --- FIX 3: open_findings rc0 on no-match ---
LG3="$(mktemp)"; printf 'no markers here\n' > "$LG3"
sr_open_findings "$LG3" >/dev/null; assert_rc "open_findings rc0 on no-match" 0 "$?"
rm -f "$LG3"

# --- FIX 4: sr_version_ge additional cases ---
sr_version_ge 1.0.0 0.140.0; assert_rc "ver major newer -> ge" 0 "$?"
sr_version_ge 0.140 0.140.0; assert_rc "ver short equal -> ge" 0 "$?"

# --- sr_root_hash ---
h1="$(sr_root_hash)"; h2="$(sr_root_hash)"
assert_eq "root hash stable" "$h1" "$h2"
assert_eq "root hash is 8 hex" "1" "$(printf '%s' "$h1" | grep -cE '^[0-9a-f]{8}$')"

# --- sr_diff_scope (operates on CWD git) ---
G="$(mktemp -d)"
git init -q -b main "$G"
git -C "$G" config user.email t@t; git -C "$G" config user.name t
echo a > "$G/f"; git -C "$G" add f; git -C "$G" commit -qm base
git -C "$G" checkout -q -b feat
echo b >> "$G/f"; git -C "$G" add f; git -C "$G" commit -qm work
mb="$(git -C "$G" merge-base main HEAD)"
cd "$G"
assert_eq "diff_scope base+branch" "$mb	feat" "$(sr_diff_scope main)"
sr_diff_scope nope >/dev/null 2>&1; assert_rc "diff_scope bad base rc3" 3 "$?"
git checkout -q --detach HEAD
case "$(sr_diff_scope main 2>/dev/null)" in
  *"	detached-"*) assert_eq "diff_scope detached label" "ok" "ok";;
  *) assert_eq "diff_scope detached label" "ok" "missing";;
esac
# orphan history -> no merge-base -> rc4
git checkout -q --orphan orphan; git rm -rfq .; echo z > z; git add z; git commit -qm orphan
sr_diff_scope main >/dev/null 2>&1; assert_rc "diff_scope no merge-base rc4" 4 "$?"
cd - >/dev/null; rm -rf "$G"
NR="$(mktemp -d)"; cd "$NR"
sr_diff_scope main >/dev/null 2>&1; assert_rc "diff_scope not-a-repo rc2" 2 "$?"
cd - >/dev/null; rm -rf "$NR"

# --- sr_open_findings: last contiguous FINDING block only ---
LB="$(mktemp)"
# an older block (R1) then a header then the latest block (R2) that omits R1F1
printf 'FINDING R1F1 STATUS=open\n=== iteration 2 ===\nFINDING R1F2 STATUS=open\nFINDING R1F3 STATUS=resolved\n' > "$LB"
assert_eq "open from last block only" "R1F2" "$(sr_open_findings "$LB")"
printf 'FINDING R1F1 STATUS=open\nFINDING R1F2 STATUS=open\n' > "$LB"
assert_eq "open both in block" "R1F1 R1F2" "$(sr_open_findings "$LB")"
rm -f "$LB"


# --- sr_review_payload (committed + working + untracked contents) ---
P="$(mktemp -d)"
git init -q -b main "$P"
git -C "$P" config user.email t@t; git -C "$P" config user.name t
echo base > "$P/tracked"; git -C "$P" add tracked; git -C "$P" commit -qm base
git -C "$P" checkout -q -b feat
echo more >> "$P/tracked"; git -C "$P" add tracked; git -C "$P" commit -qm work
echo NEWFILECONTENT > "$P/brand_new"     # untracked
mbp="$(git -C "$P" merge-base main HEAD)"
cd "$P"
pl="$(sr_review_payload "$mbp")"
case "$pl" in *"+more"*) assert_eq "payload has committed diff" ok ok;; *) assert_eq "payload has committed diff" ok missing;; esac
case "$pl" in *"untracked: brand_new"*) assert_eq "payload has untracked header" ok ok;; *) assert_eq "payload has untracked header" ok missing;; esac
case "$pl" in *"NEWFILECONTENT"*) assert_eq "payload has untracked contents" ok ok;; *) assert_eq "payload has untracked contents" ok missing;; esac
cd - >/dev/null; rm -rf "$P"

# --- sr_audit_summary (no lockfile -> skipped; rc 0) ---
AD="$(mktemp -d)"; cd "$AD"
out="$(sr_audit_summary)"; rc=$?
assert_eq "audit no lockfile -> skipped" "dep-audit: skipped (no lockfile)" "$out"
assert_rc "audit rc0" 0 "$rc"
( set -euo pipefail; . "$ROOT/codex-lib.sh"; cd "$AD"; sr_audit_summary >/dev/null ); assert_rc "audit set-e safe" 0 "$?"
cd - >/dev/null; rm -rf "$AD"

# --- sr_round_findings (id + status per finding) ---
RF="$(mktemp)"
printf '## Finding R1F1\nbody\nSTATUS: open\n## Finding R1F2\nx\nSTATUS: resolved\n' > "$RF"
assert_eq "round findings parse" "R1F1 open
R1F2 resolved" "$(sr_round_findings "$RF")"
rm -f "$RF"

# --- sr_test_cmd (discovery) ---
TC="$(mktemp -d)"; cd "$TC"
printf '{ "scripts": { "test": "node --test" } }' > package.json
assert_eq "test cmd npm" "npm test" "$(sr_test_cmd)"
rm -f package.json; : > Cargo.toml
assert_eq "test cmd cargo" "cargo test" "$(sr_test_cmd)"
rm -f Cargo.toml
assert_eq "test cmd none" "" "$(sr_test_cmd)"
cd - >/dev/null; rm -rf "$TC"

# --- offline checklists present with expected sections ---
SC="$ROOT/reference/security-checklist.md"
assert_eq "security checklist exists" "yes" "$([ -f "$SC" ] && echo yes || echo no)"
assert_eq "security checklist review section" "1" "$([ -f "$SC" ] && grep -c '^## Security Review Checklist' "$SC" || echo 0)"
MC="$ROOT/reference/simplification-checklist.md"
assert_eq "simplification checklist exists" "yes" "$([ -f "$MC" ] && echo yes || echo no)"
assert_eq "simplification checklist verify section" "1" "$([ -f "$MC" ] && grep -c '^## Verification Checklist' "$MC" || echo 0)"
RC="$ROOT/reference/reliability-checklist.md"
assert_eq "reliability checklist exists" "yes" "$([ -f "$RC" ] && echo yes || echo no)"
assert_eq "reliability checklist review section" "1" "$([ -f "$RC" ] && grep -c '^## Reliability Review Checklist' "$RC" || echo 0)"

# --- code-review.md bash blocks must parse ---
CR="$ROOT/commands/code-review.md"
if [ -f "$CR" ]; then
  crbb="$(awk '/^```bash$/{f=1;next} /^```$/{f=0} f' "$CR")"
  printf '%s\n' "$crbb" | bash -n - 2>/dev/null
  assert_rc "code-review bash blocks parse" 0 "$?"
else
  assert_eq "code-review file exists" "exists" "missing"
fi

# --- sr_review_payload safety: skip sensitive / binary / oversized untracked ---
PS="$(mktemp -d)"
git init -q -b main "$PS"; git -C "$PS" config user.email t@t; git -C "$PS" config user.name t
echo base > "$PS/f"; git -C "$PS" add f; git -C "$PS" commit -qm base
git -C "$PS" checkout -q -b feat
printf 'SECRETKEY=abc\n' > "$PS/.env"
printf '\x00\x01\x02binarycontent\n' > "$PS/blob.bin"
head -c 300000 /dev/zero | tr '\0' 'a' > "$PS/big.txt"
echo OKTEXT > "$PS/normal.txt"
mbs="$(git -C "$PS" merge-base main HEAD)"
cd "$PS"
pls="$(sr_review_payload "$mbs")"
case "$pls" in *"SECRETKEY=abc"*) assert_eq "payload omits secret contents" omitted leaked;; *) assert_eq "payload omits secret contents" omitted omitted;; esac
case "$pls" in *"skipped: sensitive filename"*) assert_eq "payload marks sensitive skip" ok ok;; *) assert_eq "payload marks sensitive skip" ok missing;; esac
case "$pls" in *"binarycontent"*) assert_eq "payload omits binary contents" omitted leaked;; *) assert_eq "payload omits binary contents" omitted omitted;; esac
case "$pls" in *"skipped: binary"*) assert_eq "payload marks binary skip" ok ok;; *) assert_eq "payload marks binary skip" ok missing;; esac
case "$pls" in *"OKTEXT"*) assert_eq "payload keeps normal text" ok ok;; *) assert_eq "payload keeps normal text" ok missing;; esac
case "$pls" in *"bytes > cap): big.txt"*) assert_eq "payload marks oversized skip" ok ok;; *) assert_eq "payload marks oversized skip" ok missing;; esac
cd - >/dev/null; rm -rf "$PS"

# --- sr_review_payload safety: nested sensitive path matches on basename ---
PN="$(mktemp -d)"
git init -q -b main "$PN"; git -C "$PN" config user.email t@t; git -C "$PN" config user.name t
echo base > "$PN/f"; git -C "$PN" add f; git -C "$PN" commit -qm base
git -C "$PN" checkout -q -b feat
mkdir -p "$PN/.ssh"; printf 'PRIVATEKEYDATA\n' > "$PN/.ssh/id_rsa"
mbn="$(git -C "$PN" merge-base main HEAD)"
cd "$PN"
pln="$(sr_review_payload "$mbn")"
case "$pln" in *"PRIVATEKEYDATA"*) assert_eq "payload omits nested secret" omitted leaked;; *) assert_eq "payload omits nested secret" omitted omitted;; esac
case "$pln" in *"skipped: sensitive filename): .ssh/id_rsa"*) assert_eq "payload marks nested secret" ok ok;; *) assert_eq "payload marks nested secret" ok missing;; esac
cd - >/dev/null; rm -rf "$PN"

# --- sr_is_sensitive (basename match) ---
if sr_is_sensitive ".env"; then r=yes; else r=no; fi; assert_eq "sensitive .env" yes "$r"
if sr_is_sensitive "config/.env.local"; then r=yes; else r=no; fi; assert_eq "sensitive nested env" yes "$r"
if sr_is_sensitive ".ssh/id_rsa"; then r=yes; else r=no; fi; assert_eq "sensitive id_rsa" yes "$r"
if sr_is_sensitive "src/main.js"; then r=yes; else r=no; fi; assert_eq "non-sensitive js" no "$r"

# --- sr_review_payload: tracked sensitive file redacted in diff ---
PT="$(mktemp -d)"
git init -q -b main "$PT"; git -C "$PT" config user.email t@t; git -C "$PT" config user.name t
echo base > "$PT/f"; git -C "$PT" add f; git -C "$PT" commit -qm base
git -C "$PT" checkout -q -b feat
printf 'TRACKEDSECRET=xyz\n' > "$PT/.env"; git -C "$PT" add .env; git -C "$PT" commit -qm addenv
mbt="$(git -C "$PT" merge-base main HEAD)"
cd "$PT"
plt="$(sr_review_payload "$mbt")"
case "$plt" in *"TRACKEDSECRET=xyz"*) assert_eq "tracked secret redacted" omitted leaked;; *) assert_eq "tracked secret redacted" omitted omitted;; esac
case "$plt" in *"diff (skipped: sensitive filename): .env"*) assert_eq "tracked secret marker" ok ok;; *) assert_eq "tracked secret marker" ok missing;; esac
cd - >/dev/null; rm -rf "$PT"

# --- sr_review_payload: aggregate size cap ---
PA="$(mktemp -d)"
git init -q -b main "$PA"; git -C "$PA" config user.email t@t; git -C "$PA" config user.name t
echo base > "$PA/f"; git -C "$PA" add f; git -C "$PA" commit -qm base
git -C "$PA" checkout -q -b feat
for i in $(seq 1 12); do head -c 250000 /dev/zero | tr '\0' 'a' > "$PA/file$i.txt"; done
mba="$(git -C "$PA" merge-base main HEAD)"
cd "$PA"
pla="$(sr_review_payload "$mba")"
case "$pla" in *"payload truncated"*) assert_eq "aggregate cap marker" ok ok;; *) assert_eq "aggregate cap marker" ok missing;; esac
cd - >/dev/null; rm -rf "$PA"

# --- sr_review_payload: tracked rename from a sensitive name stays redacted ---
PR="$(mktemp -d)"
git init -q -b main "$PR"; git -C "$PR" config user.email t@t; git -C "$PR" config user.name t
printf 'RENAMESECRET=zzz\nkeepline\n' > "$PR/.env"; git -C "$PR" add .env; git -C "$PR" commit -qm base
git -C "$PR" checkout -q -b feat
git -C "$PR" mv .env notes.txt; printf 'EXTRA=1\n' >> "$PR/notes.txt"; git -C "$PR" add notes.txt; git -C "$PR" commit -qm rename-edit
mbr="$(git -C "$PR" merge-base main HEAD)"
cd "$PR"
plr="$(sr_review_payload "$mbr")"
case "$plr" in *"RENAMESECRET=zzz"*) assert_eq "rename secret redacted" omitted leaked;; *) assert_eq "rename secret redacted" omitted omitted;; esac
case "$plr" in *"diff (skipped: sensitive filename)"*) assert_eq "rename redaction marker" ok ok;; *) assert_eq "rename redaction marker" ok missing;; esac
cd - >/dev/null; rm -rf "$PR"

# --- sr_design_docs (branch-slug match + newest fallback) ---
DD="$(mktemp -d)"; mkdir -p "$DD/docs/superpowers/specs" "$DD/docs/superpowers/plans"
: > "$DD/docs/superpowers/specs/2026-01-01-alpha-design.md"
sleep 0.02; : > "$DD/docs/superpowers/specs/2026-02-02-myfeat-design.md"
: > "$DD/docs/superpowers/plans/2026-02-02-myfeat.md"
cd "$DD"
ddm="$(sr_design_docs feat/myfeat)"
case "$ddm" in *"myfeat-design.md	"*"myfeat.md") assert_eq "design docs slug match" ok ok;; *) assert_eq "design docs slug match" ok "[$ddm]";; esac
ddf="$(sr_design_docs feat/unrelated)"
case "$ddf" in *-design.md*) assert_eq "design docs fallback to newest" ok ok;; *) assert_eq "design docs fallback to newest" ok "[$ddf]";; esac
ddn="$(cd /tmp && sr_design_docs feat/whatever)"
assert_eq "design docs none -> empty tab" "$(printf '\t')" "$ddn"
cd - >/dev/null; rm -rf "$DD"

# --- F1: sr_redact_secrets (content-based credential masking) ---
assert_eq "redact sk- provider key" "***REDACTED-KEY***" "$(printf 'sk-live-NORMALFILE-CAFEBABE-7766' | sr_redact_secrets)"
case "$(printf 'const t="sk-live-DEADBEEF-9988";' | sr_redact_secrets)" in *sk-live-DEADBEEF*) assert_eq "redact sk in code" omitted leaked;; *) assert_eq "redact sk in code" omitted omitted;; esac
assert_eq "redact aws key" "***REDACTED-AWS***" "$(printf 'AKIAIOSFODNN7EXAMPLE' | sr_redact_secrets)"
case "$(printf 'tok=eyJhbGci.eyJzdWIi.sIgnAtuRe123' | sr_redact_secrets)" in *eyJzdWIi*) assert_eq "redact jwt" omitted leaked;; *) assert_eq "redact jwt" omitted omitted;; esac
case "$(printf 'password = "hunter2longsecret"' | sr_redact_secrets)" in *hunter2longsecret*) assert_eq "redact keyword quoted value" omitted leaked;; *) assert_eq "redact keyword quoted value" omitted omitted;; esac
assert_eq "non-secret code untouched" 'const TIMEOUT_MS = 500;' "$(printf 'const TIMEOUT_MS = 500;' | sr_redact_secrets)"
case "$(printf -- '-----BEGIN RSA PRIVATE KEY-----' | sr_redact_secrets)" in *REDACTED*) assert_eq "redact pem header" ok ok;; *) assert_eq "redact pem header" ok missing;; esac

# --- F1: secret value in a NORMAL-named tracked file is redacted in payload ---
PC="$(mktemp -d)"
git init -q -b main "$PC"; git -C "$PC" config user.email t@t; git -C "$PC" config user.name t
echo base > "$PC/f"; git -C "$PC" add f; git -C "$PC" commit -qm base
git -C "$PC" checkout -q -b feat
printf 'export const TOKEN = "sk-live-NORMALFILE-CAFEBABE-7766";\n' > "$PC/settings.js"
git -C "$PC" add settings.js; git -C "$PC" commit -qm addtoken
mbc="$(git -C "$PC" merge-base main HEAD)"
cd "$PC"
plc="$(sr_review_payload "$mbc")"
case "$plc" in *"sk-live-NORMALFILE"*) assert_eq "normal-file secret redacted in payload" omitted leaked;; *) assert_eq "normal-file secret redacted in payload" omitted omitted;; esac
case "$plc" in *"settings.js"*) assert_eq "normal-file diff still present" ok ok;; *) assert_eq "normal-file diff still present" ok missing;; esac
cd - >/dev/null; rm -rf "$PC"

# --- F2: spec-review.md resolves plugin root, then project-local, then global ---
SRV="$ROOT/commands/spec-review.md"
assert_eq "spec-review resolves CLAUDE_PLUGIN_ROOT" "1" "$(grep -c 'CLAUDE_PLUGIN_ROOT' "$SRV")"
assert_eq "spec-review resolves project-local" "1" "$(grep -c '.claude/commands/codex' "$SRV")"

# --- F3: codex-lib.sh fails clearly under a non-bash shell ---
assert_eq "non-bash guard line present" "1" "$(grep -c 'requires bash' "$ROOT/codex-lib.sh")"
shisbash="$(sh -c 'echo ${BASH_VERSION:-no}' 2>/dev/null)"
if [ "$shisbash" = "no" ]; then
  nb="$(sh -c ". '$ROOT/codex-lib.sh'" 2>&1)"; nbrc=$?
  case "$nb" in *requires\ bash*) assert_eq "non-bash guard message" ok ok;; *) assert_eq "non-bash guard message" ok "[$nb]";; esac
  assert_rc "non-bash guard rc nonzero" 1 "$nbrc"
else
  assert_eq "non-bash guard (sh is bash; functional test skipped)" skip skip
fi

# --- #3: JSON-output mode (helpers/json-output.sh) ---
SCHEMA="$ROOT/schemas/review-output.schema.json"
assert_eq "schema file exists" "yes" "$([ -f "$SCHEMA" ] && echo yes || echo no)"
if command -v node >/dev/null 2>&1; then
  assert_eq "schema parses as JSON" "ok" "$(node -e 'JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"))' "$SCHEMA" >/dev/null 2>&1 && echo ok || echo bad)"
  assert_rc "sr_have_json true when node present" 0 "$(sr_have_json; echo $?)"
  JT="$(mktemp)"
  COV='"coverage":{"correctness":0,"security":0,"reliability":0,"simplification":0,"performance":0}'
  # valid APPROVED, no findings
  printf '{"verdict":"APPROVED","summary":"ok",%s,"findings":[]}' "$COV" > "$JT"
  assert_rc "validate APPROVED empty ok" 0 "$(sr_json_validate "$JT"; echo $?)"
  assert_eq "verdict APPROVED" "APPROVED" "$(sr_json_verdict "$JT")"
  # valid CHANGES_REQUESTED with one finding
  printf '{"verdict":"CHANGES_REQUESTED","summary":"x",%s,"findings":[{"id":"R1F1","lens":"security","file":"a.js","line_start":1,"line_end":2,"severity":"high","confidence":0.9,"issue":"i","suggestion":"s","status":"open"}]}' "$COV" > "$JT"
  assert_rc "validate CHANGES with finding ok" 0 "$(sr_json_validate "$JT"; echo $?)"
  assert_eq "round findings id+status" "R1F1 open" "$(sr_json_round_findings "$JT")"
  assert_eq "finding ids" "R1F1" "$(sr_json_finding_ids "$JT")"
  # reject: invalid JSON
  printf 'not json' > "$JT"; assert_rc "validate rejects bad json" 1 "$(sr_json_validate "$JT"; echo $?)"
  # reject: bad verdict
  printf '{"verdict":"MAYBE","summary":"x",%s,"findings":[]}' "$COV" > "$JT"
  assert_rc "validate rejects bad verdict" 1 "$(sr_json_validate "$JT"; echo $?)"
  # reject: missing a lens in coverage
  printf '{"verdict":"APPROVED","summary":"x","coverage":{"correctness":0,"security":0,"reliability":0,"simplification":0},"findings":[]}' > "$JT"
  assert_rc "validate rejects missing lens" 1 "$(sr_json_validate "$JT"; echo $?)"
  # reject: CHANGES_REQUESTED with no findings
  printf '{"verdict":"CHANGES_REQUESTED","summary":"x",%s,"findings":[]}' "$COV" > "$JT"
  assert_rc "validate rejects changes+empty" 1 "$(sr_json_validate "$JT"; echo $?)"
  # reject: duplicate finding id
  printf '{"verdict":"CHANGES_REQUESTED","summary":"x",%s,"findings":[{"id":"R1F1","lens":"security","file":"a","line_start":1,"line_end":1,"severity":"low","confidence":0.1,"issue":"i","suggestion":"s"},{"id":"R1F1","lens":"correctness","file":"b","line_start":1,"line_end":1,"severity":"low","confidence":0.1,"issue":"i","suggestion":"s"}]}' "$COV" > "$JT"
  assert_rc "validate rejects dup id" 1 "$(sr_json_validate "$JT"; echo $?)"
  # reject: malformed finding id
  printf '{"verdict":"CHANGES_REQUESTED","summary":"x",%s,"findings":[{"id":"bad","lens":"security","file":"a","line_start":1,"line_end":1,"severity":"low","confidence":0.1,"issue":"i","suggestion":"s"}]}' "$COV" > "$JT"
  assert_rc "validate rejects malformed id" 1 "$(sr_json_validate "$JT"; echo $?)"
  rm -f "$JT"
else
  assert_eq "JSON helper tests (no node; skipped)" skip skip
fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
