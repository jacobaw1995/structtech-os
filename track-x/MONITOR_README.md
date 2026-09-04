# Front-door monitor

**Track X · X-W1.1 · 2026-09-02**

- `scripts/monitor/frontdoor-monitor.mjs` — the monitor. Zero dependencies,
  zero external binaries, no secrets.
- `.github/workflows/frontdoor-monitor.yml` — the runner. Every 15 minutes,
  plus a `failure-path-proof` job that runs whenever the monitor changes.

## Run it

```
node scripts/monitor/frontdoor-monitor.mjs        # check the real doors
MONITOR_SELFTEST=1 node scripts/monitor/frontdoor-monitor.mjs
MONITOR_FAULT=content node scripts/monitor/frontdoor-monitor.mjs
```

Exit codes: **0** healthy · **1** FAIL (a door answered and the content that
proves it works was absent) · **2** UNDETERMINED (the monitor could not tell).
1 and 2 are never collapsed. That distinction is the entire design.

## What it asserts, per door

| id | door | asserts on | why it is not chrome |
|---|---|---|---|
| D1.1 | os.structtek.com | `Sign in to your workspace.` + `name="password"` | shallow **by admission** — proves Vercel serves this build, not a deployment-not-found page. Not evidence the app works. |
| D1.2 | os.structtek.com | every `/_next/static/…` asset the served HTML references resolves 200, non-empty | the hashes are emitted by the build. Fresh HTML + missing chunks = 200 page, `ChunkLoadError` in every browser (CLAUDE.md App-Router pattern 8). |
| D2.1 | audit.structtek.com | `START MY FREE SCAN` | funnel entry, chrome. |
| D2.2 | audit.structtek.com | `results.html` still contains `/rest/v1/audit_leads`, `'Prefer': 'return=minimal'`, `SUPA_URL`, `SUPA_KEY` | **the capture machinery itself.** A static page renders identically whether the backend lives or dies; the only non-chrome thing on this door is the fetch that turns a scan into a row. |
| D2.3 | audit.structtek.com | live POST returns **400 / 22P02**, not 42501 | exercises the real write path with the real key. Grades on the **message**, per CLAUDE.md rule 11 — form 1 and form 3 are both `42501`. |
| D3.1 | supabase/auth | `"email":true` from `/auth/v1/settings` | the project's real auth config, and the only enabled sign-in method. If it flips, nobody can log in while `/login` still returns a perfect 200. |
| D3.2 | supabase/postgrest | anon `GET /rest/v1/deals` returns **401 / 42501 permission denied for table deals** | turns the 2026-08-29 closure into a **continuously asserted invariant**. A `200 []` here is rule 11 **form 2** and is graded FAIL — the grant came back. |

## Why D2.3 writes nothing

`audit_leads.score` is `integer`. The probe sends a non-numeric value, so
Postgres fails coercion **before any trigger fires**, and the privilege check
fires before that. Grant intact → `400 / 22P02`. Grant gone → `401 / 42501`.

Verified by measurement on 2026-09-02, not by reasoning: after running the
probe, `count(*) where source = 'frontdoor-monitor'` on `audit_leads` = **0**.
