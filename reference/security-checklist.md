# Security Review Criteria

Security lens for `/codex:code-review` — actionable review criteria, not prose.
**Scope to the change's surface:** apply only the categories relevant to this code. Don't
flag web-only items (CSP, cookies, CORS) on a CLI/library/script; treat the project's own
runtime risks (shell/path/temp-file injection for CLIs) as in-scope. Treat external input
as hostile, secrets as sacred, authorization as mandatory.

## Authentication & passwords
- Hash passwords with bcrypt/scrypt/argon2, salt rounds ≥ 12; never plaintext.
- Rate-limit login endpoints (stricter than general API, e.g. 10 attempts / 15 min).
- Password-reset tokens must expire.

## Sessions & cookies (web)
- Auth/session cookies: httpOnly + secure (HTTPS) + sameSite; never tokens in localStorage.
- Session secrets from environment, never hardcoded.

## Authorization
- Every protected endpoint/action validates permissions; resources scoped to the authed user.
- Admin actions verify admin role explicitly.
- Responses omit fields the user lacks permission to see.

## Input validation
- Validate all external input at system entry points (schema lib, e.g. Zod; type coercion).
- Enforce input length limits; restrict file uploads by MIME type and size.

## Injection / XSS
- Parameterize all DB queries (ORM safe methods); never concatenate user input into SQL/NoSQL.
- Encode output per context; rely on framework auto-escaping; never `innerHTML`/`eval()` user data.
- Sanitize with DOMPurify only when raw HTML is unavoidable.

## Systems / language-level (CLI, libraries, scripts)
- Shell/command injection: never interpolate untrusted data into shell, `eval`, or subprocess
  args; use argument arrays / fixed commands.
- Path traversal: validate/normalize untrusted file paths; reject `..` and absolute escapes;
  confine to an intended root.
- Archive extraction: guard against zip-slip (entries escaping the target dir) and
  decompression bombs.
- Deserialization: never deserialize untrusted data into executable types; use safe
  formats / allowlists.
- Insecure temp files / TOCTOU: create temp files with `mktemp` (unpredictable names); avoid
  check-then-use races on shared paths.
- Resource exhaustion: bound input size, recursion depth, and regex backtracking (ReDoS).

## SSRF
- Server-side fetch of user-influenced URLs: allowlist scheme (https) + host, reject
  private/reserved IP ranges, disable redirects.

## CORS & security headers (web)
- CORS origin restricted to known domains; reject wildcard `*`; credentials flag set deliberately.
- Set CSP, HSTS, X-Frame-Options, X-Content-Type-Options=nosniff (helmet or equivalent).

## Secrets & data exposure
- Never commit secrets to VCS; `.env` gitignored; `.env.example` holds placeholders only.
- API keys/tokens from environment; fail if missing.
- Sensitive fields (passwords, tokens, reset codes) excluded from API responses.
- PII encrypted at rest if stored; never expose stack traces / internal errors to users.

## Logging & monitoring
- Log security-relevant events (authn, authz failures, admin actions); never log secrets/PII
  or full credit-card numbers.
- Don't silently swallow security errors — failures must be detectable; alert on anomalies
  where applicable.

## Dependencies (human-review signals; CVEs handled by the command's local audit step)
- Lockfile committed; `npm ci` in CI (not `npm install`).
- New deps vetted for maintenance/trust; assess typosquatting; flag `postinstall` scripts in
  unfamiliar packages.

## AI / LLM (if present)
- Never pass model output to eval/SQL/shell/innerHTML/paths; validate against a schema; encode per context.
- Assume prompts can be hijacked — enforce permissions in code, not the prompt.
- Keep secrets and cross-tenant data out of prompts; scope tool permissions to the minimum.
- Destructive agent actions require explicit confirmation; bound token consumption.
- Partition vector stores per tenant in RAG systems.

## Security Review Checklist
- [ ] All user input validated + length-limited at the boundary; uploads MIME/size restricted.
- [ ] SQL parameterized; no string-built queries.
- [ ] No shell/command/path injection; untrusted paths confined; temp files created safely.
- [ ] HTML output encoded/escaped (web).
- [ ] Server-side URL fetches allowlisted; redirects disabled (no SSRF).
- [ ] No secrets in code, logs, or version control.
- [ ] Sensitive fields excluded from API responses; PII encrypted at rest.
- [ ] AuthN/AuthZ checked on every protected endpoint/action; admin role verified.
- [ ] Rate limiting on auth + general endpoints (web).
- [ ] Security headers present; CORS restricted to known origins (web).
- [ ] Security-relevant events logged; no secrets in logs; failures detectable.
- [ ] Dependencies audited (local audit step); lockfile committed; new deps vetted.
- [ ] External data treated as untrusted; validated at system boundaries.
- [ ] LLM/model output validated + encoded before use; agent permissions scoped (if AI present).

## Severity guidance
critical/high = exploitable in the change's deployment context → fix before approval.
medium = fix this cycle. low = track. Reachability + trust boundary decide severity.
