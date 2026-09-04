# Failure-path proof — in the real environment

**Track X · X-W1.1 · 2026-09-02 (America/New_York)**
**Run:** [33689124327](https://github.com/jacobaw1995/structtech-os/actions/runs/33689124327) · branch `track-x` · both jobs green
**Environment:** GitHub Actions `ubuntu-24.04` (image `20260823.283.1`), **node v22.23.2**, Azure eastus

> **This document, not the monitor, is the deliverable.** A monitor that
> reports content-missing because its own fetch broke reads exactly like a
> monitor that found a real outage. What follows is the evidence that this one
> can tell those apart, taken in the environment it will actually run in.

---

## The failure being guarded against

Material Matrix shipped a deploy-drift guard that reported all six pairs
drifted, because the build image had neither `cmp` nor `diff`. The failure
surfaced as `command not found`. It failed **closed**, correctly, and would
have blocked every deployment they ever made while looking like a working
guard that had found a real problem.

> A guard that fails closed for the wrong reason is indistinguishable from a
> guard that works, right up until it is indistinguishable from an outage.

## Two structural defences, both asserted in the runner

**1 · The monitor cannot shell out.** It is Node built-ins only — no `curl`,
no `jq`, no `cmp`, no `diff`, no `npm install`. There is no binary for an
image to be missing. The workflow asserts this on every run rather than
trusting it: a step greps the source for `child_process`/`execSync`/`spawnSync`
and fails the job if any appears. Runner output:

```
node v22.23.2; no shell-outs; no npm install
```

**2 · ERROR is minted at the transport boundary, before any grading.**
Every exception — DNS, TLS, timeout, abort, unreadable body, missing config —
is converted to `Undetermined` inside `probe()`. The classifiers are pure
functions over a well-formed HTTP response and **cannot return anything but
PASS or FAIL**. MM's failure mode is not unlikely here; it is unreachable.

---

## The evidence

### A · The real doors, from the runner

```
VERDICT: HEALTHY   (7 pass · 0 fail · 0 undetermined)
```

with, notably:

```
[PASS ] D2.3  (audit.structtek.com · live write path)
         HTTP 400 / 22P02 — privilege check passed, Postgres evaluated the row
         and rejected it on data. Grant intact, no row written.
[PASS ] D3.2  (supabase/postgrest · anon closure invariant)
         HTTP 401 / 42501 "permission denied for table deals" — rule 11 FORM 1.
```

### B · Fault injection — five modes, each graded in the real runner

Exit codes: **0** healthy · **1** FAIL (an outage claim) · **2** ERROR (undetermined).

| mode | what it simulates | verdict | exit | wanted |
|---|---|---|---|---|
| *(none)* | the real doors | `HEALTHY` 7 pass | 0 | 0 |
| `content` | real hosts, real 200s, required content gone | `OUTAGE` **4 fail · 3 undetermined** | 1 | 1 |
| `network` | unresolvable host | `UNDETERMINED` 7 undetermined | 2 | 2 |
| `timeout` | the monitor too slow (1 ms budget) | `UNDETERMINED` 7 undetermined | 2 | 2 |
| `noconfig` | no target configured at all | `UNDETERMINED` 7 undetermined | 2 | 2 |

```
All fault modes graded correctly in the real runner.
```

**The `content` row is the one that carries the argument.** Four checks had a
well-formed 200 in hand with the required content absent, and said **FAIL** —
an outage claim. The three checks that depend on a write path the failing door
never yielded said **ERROR**, not FAIL: *nothing was tested*, stated as such.
The monitor drew the line between "the door is broken" and "I could not tell"
**inside a single run**, which is precisely the line MM's guard could not draw.

The `network` and `timeout` rows are the MM case proper: the monitor is blind
and the doors may be perfectly healthy. Both come back **undetermined**.
Neither can ever page you for an outage that is not happening.

### C · Classifier self-test — the branches production must never reach

These are the branches an outage would take, so they cannot be induced against
live doors — and shipping them untested is shipping an unproven guard. Same
functions, synthetic responses, run in the same runner: **10/10 correct**,
including the three that CLAUDE.md rule 11 exists to separate —

```
ok  expected FAIL got FAIL  write probe · 401 + 42501 (grant revoked, leads lost)
ok  expected FAIL got FAIL  anon closure · 200 [] (form 2 — grant is BACK)
ok  expected FAIL got FAIL  anon closure · 401 naming my_org_ids (form 3)
```

### D · The live write probe is non-destructive — measured, not reasoned

`D2.3` POSTs to the production `audit_leads` endpoint on every run. It writes
nothing, and that is a measurement:

| | `count(*)` | `source='frontdoor-monitor'` | `max(created_at)` |
|---|---|---|---|
| before any probe | 7 | 0 | 2026-07-17 23:23:32+00 |
| after **4** live probe executions | 7 | 0 | 2026-07-17 23:23:32+00 |

**Mechanism:** `audit_leads.score` is `integer`; the probe sends a non-numeric
value, so coercion fails before any trigger fires — and Postgres checks the
INSERT privilege before it evaluates the row. Grant intact → `400 / 22P02`.
Grant gone → `401 / 42501`. The two are cleanly separable and neither leaves
a row.

---

## What is NOT proven, stated plainly

- **The schedule has never fired.** GitHub runs `schedule` on the **default
  branch only**. Everything above was triggered by `push` on `track-x`. The
  15-minute cadence begins when this lands on `main` — until then **nothing is
  being watched**, and that is Track S's merge, not a monitor defect.
- **`os.structtek.com` has no authenticated check.** D1.1/D1.2 cover the shell
  and the build; nothing covers what Isaac actually sees after login. That
  needs a monitor credential — see the report's Track S section.
- **Silence is not proven safe.** A red run emails the owner; a run that never
  happens emails nobody. That gap is item 1 of the account inventory.
