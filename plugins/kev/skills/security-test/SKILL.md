---
name: security-test
description: Deep source-level security audit of the repo in the current working directory — hunt for injection sinks, authn/authz gaps, secrets, SSRF, insecure deserialization, crypto misuse, and risky dependencies — then deliver a prioritized findings report. No running target needed; this reads code, not live traffic. Use when the user runs `/security-test`, or asks to "security-audit this repo", "find vulnerabilities in the code", "do a security review of the codebase", or "check this project for security holes".
---

# /security-test — static security audit → prioritized findings report

Audit the source of the project in the current working directory for security vulnerabilities and deliver a ranked, actionable findings report. This is a **static** review: it reads code, configuration, and dependency manifests. It does **not** run the app, send live traffic, or execute exploits — for that, the user wants a live pentest, not this.

The deliverable is one thing: a **findings report** the user can act on, ordered by real-world risk, with each finding tied to a concrete file:line and a fix.

## Operating rules

- **Read-only.** Do not modify project code, install dependencies, run the app, or open PRs. The only thing this skill produces is the on-screen report (and, if asked, a written report file). `git fetch` is fine (read-only); `git pull`/`merge`/`checkout` are not.
- **Inspect, don't execute.** Read code and config to reason about vulnerabilities. Do not run the test suite, build, or any command with side effects as part of the audit.
- **Evidence over speculation.** Every finding must point at a real file:line and explain the actual data flow (source → sink). If you can't trace untrusted input reaching a dangerous sink, mark it clearly as *potential / needs confirmation* rather than asserting it.
- **Synthesize, don't dump.** Use sub-agents to fan out across the codebase so raw grep output stays out of the main thread. The user wants conclusions, not a wall of matches.
- **No real secrets in the report.** If you find a leaked credential, report its location and type — never paste the full secret value into the report or memory. Redact to the last 4 chars.

## Step 1 — Scope the codebase

Build a quick map before hunting, so findings land in context.

- Identify language(s), framework(s), and runtime from the manifest(s): `package.json`, `pyproject.toml`/`requirements*.txt`, `Cargo.toml`, `go.mod`, `pom.xml`/`build.gradle`, `Gemfile`, `composer.json`, `*.csproj`. The stack determines which vuln classes and which sinks matter.
- Find the trust boundaries: HTTP handlers/routes, CLI entry points, message/queue consumers, file/upload handlers, deserialization points, and anything reading env/config. These are where untrusted input enters.
- Note the auth model (sessions, JWT, OAuth, API keys) and where authorization decisions are made.

For anything beyond a small repo, **dispatch parallel `Explore` (or `general-purpose`) sub-agents** — one per vuln class or per subsystem — and have each return a tight list of candidate findings with file:line and a one-line data-flow note. Keep the raw search output inside the sub-agents.

## Step 2 — Hunt by vulnerability class

Work through these systematically. For each, trace whether untrusted input actually reaches the sink — a sink alone isn't a finding.

1. **Injection** — SQL/NoSQL (string-built queries, missing parameterization), command injection (`exec`/`spawn`/`system`/`subprocess` with interpolated input, `shell=True`), template injection (SSTI), LDAP/XPath, and code-eval sinks (`eval`, `Function`, `pickle.loads`, `yaml.load` without `SafeLoader`, deserialization of untrusted data).
2. **AuthN / AuthZ** — missing auth on routes, broken access control (IDOR: object IDs from the request used without an ownership check), privilege escalation, role checks that are absent or trivially bypassable, JWT misuse (`alg:none`, unverified signatures, secrets in the token), session fixation.
3. **Secrets & credentials** — hardcoded API keys, passwords, private keys, tokens in source, config, or committed `.env`/fixtures. Check `git`-tracked files; flag anything that looks live (redact the value).
4. **SSRF & request forgery** — user-controlled URLs passed to server-side fetch/HTTP clients; missing host allowlists; cloud metadata endpoint reachability. Also CSRF on state-changing endpoints lacking tokens/SameSite.
5. **XSS & output handling** — unescaped user data rendered into HTML, `dangerouslySetInnerHTML`/`v-html`/`innerHTML` with untrusted input, missing CSP, reflected/stored sinks.
6. **Crypto & secrets handling** — weak/again-broken algorithms (MD5/SHA1 for passwords, ECB, static IVs), hardcoded keys, insecure randomness (`Math.random` for tokens), missing TLS verification (`verify=False`, `rejectUnauthorized:false`).
7. **Path & file handling** — path traversal (`../` reaching user-controlled paths), arbitrary file read/write/upload, zip-slip, unsafe temp-file creation.
8. **Dependencies & supply chain** — scan the lockfile for known-vulnerable versions where you can reason about it; flag unpinned/`*` versions, abandoned packages, and obviously risky transitive deps. If an audit tool is configured in the project, note its existence but **don't run it** unless the user asks.
9. **Misconfiguration** — debug mode on, permissive CORS (`*` with credentials), verbose error leakage, default credentials, overly broad cloud/IAM policies in IaC, exposed admin endpoints.

This list is a checklist, not a cage — follow the code where it leads.

## Step 3 — Triage & rank

For each confirmed/likely finding, assign:

- **Severity** — Critical / High / Medium / Low, based on impact × exploitability (not just CVSS by rote). An unauthenticated RCE outranks a reflected XSS behind admin auth. Be honest about exploitability: a sink that only handles trusted internal input is Low or Informational, not High.
- **Confidence** — Confirmed (you traced source→sink) vs Potential (suspicious pattern, data flow unverified). Keep these visibly separate so the user knows what to verify.

Drop noise. A finding the user can't act on, or that's plainly not reachable, is clutter — say "no issues found in class X" rather than padding.

## Step 4 — Present the report

Print a skimmable, ranked report. Lead with the headline (how many findings, worst severity), then details:

```
## Security audit — <project name>

**Summary** — <N findings: X critical, Y high, Z medium, W low>. <One-line overall posture.>

### Findings (by severity)

#### [CRITICAL] <short title>
- **Where** — `path/to/file.ext:LINE` (+ related sinks)
- **Issue** — <what's wrong: the untrusted source, the dangerous sink, the data flow between them>
- **Impact** — <what an attacker achieves>
- **Confidence** — Confirmed | Potential (needs live confirmation)
- **Fix** — <the concrete remediation: parameterize the query / add the authz check / pin the version>

#### [HIGH] <next>
…

### Checked, no issues
- <vuln classes you audited and found clean — so the user knows the coverage>
```

Keep each finding tight. If there are many, group Low/Informational into a single condensed list.

## Step 5 — Optional written report

If the user asked for a file (or the audit is large enough that they'll want to reference it), offer to write the report to `SECURITY-AUDIT.md` (or a path they choose) in the repo root. Don't write it unprompted — the on-screen report is the default deliverable.

## Principles

- **Trace, don't pattern-match.** A grep hit is a lead, not a finding. The value is confirming whether untrusted input actually reaches the sink.
- **Rank by real risk.** Impact × exploitability, honestly assessed. Don't inflate severity to look thorough; don't bury a critical under trivia.
- **Separate confirmed from potential.** The user needs to know what's proven vs what to go verify.
- **Actionable fixes.** Every finding ends with a concrete remediation, not "consider reviewing this."
- **State your coverage.** Name the classes you checked and found clean, so "no findings" means "audited," not "skipped."
- **Static only.** No running the app, no live exploits, no traffic. If confirming a finding needs a live target, say so and stop at "Potential."

## Distribution / maintenance (for the skill author)

This skill ships in the `kev` plugin of `proton-pidgeon/claude-skills` (marketplace `kevdunn`). It reaches other hosts on `/plugin marketplace update kevdunn` (+ restart) — plugin code is intentionally **not** auto-pulled by the SessionStart sync hook.
