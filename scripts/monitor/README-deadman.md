# The dead-man's ping — what it is for, and how to turn it on

## Why it exists

The front-door monitor emails you when a run goes **red**. It cannot email you
when a run does not **happen**. Those are different failures and only one of
them is covered today.

Two controls now sit in `frontdoor-monitor.yml`:

| control | catches | blind to |
|---|---|---|
| `schedule-drift.mjs` | the schedule **degrading** — gaps beyond 6 h | the schedule **stopping**, because it only runs inside a run |
| the dead-man's ping | the schedule **stopping** | nothing here — it is the backstop |

The ping step is already written and already in the workflow. It **skips with a
visible notice** until the secret below exists, so nothing breaks in the
meantime and no second edit is needed later.

This matters more than it did on 2026-09-04. Measured over two comparable
~19½-hour windows, changing the cron from `*/15` to hourly did **not** change
the delivered cadence: mean gap 193 min before, 197 min after. GitHub delivers
a run roughly every 3¼ hours on this repo whatever we ask for. An external
watcher is not a nice-to-have any more; it is the only thing that would notice
if that became "never".

## What Jacob does — about five minutes

Any of these work on a free tier. **Healthchecks.io** is the suggestion because
its free tier has no card and its grace period is configurable to the minute.

1. Go to **https://healthchecks.io** and sign in. (Creating the account is
   yours to do — I do not create accounts or handle credentials.)
2. **Add Check.**
   - Name: `structtech front-door monitor`
   - Schedule: **Period 1 hour**, **Grace 3 hours**
   - Why 3 h and not 1 h: the *delivered* worst gap measured on this repo is
     4 h 33 m under the hourly cron and 5 h 10 m under `*/15`. A 1-hour grace
     would page you several times a day about GitHub's queue rather than about
     your site. Three hours is deliberately loose — it is watching for
     *death*, not lateness. If the delivered cadence ever improves, tighten it.
3. Copy the check's **Ping URL** (it looks like `https://hc-ping.com/<uuid>`).
   **Do not paste it into a chat, a commit, or any file in this repo** — it is
   a capability: anyone holding it can silence the alarm.
4. Go to the repo's secret settings:
   **https://github.com/jacobaw1995/structtech-os/settings/secrets/actions**
   → **New repository secret**
   - Name: `DEADMAN_PING_URL` (exactly this — the workflow reads that name)
   - Secret: paste the ping URL
   - **Add secret**
5. Confirm the alert destination on the Healthchecks side (email is on by
   default for the account address).

## Confirming it actually works — do not skip this

A dead-man's switch you have not seen fire is a belief, not a control.

1. **Prove the ping arrives.** In the repo's **Actions** tab, open
   *front-door monitor* → **Run workflow**. Note: a manual run is
   `workflow_dispatch`, not `schedule`, and the step is scoped to `schedule`,
   so **it will not ping**. To see it fire, wait for the next scheduled run
   (up to ~4 h) and check that Healthchecks shows the check as **up** with a
   recent ping.
2. **Prove the alarm fires.** On Healthchecks, use **Pause** on the check, or
   simply wait: if no ping arrives within period + grace, it alerts. Confirm
   you receive that email. Until you have seen this email once, the control is
   unproven.

## What this does not cover

- **A GitHub-wide incident** takes out the monitor *and* `audit.structtek.com`
  (GitHub Pages) together, and Healthchecks would correctly alert on the
  monitor's silence while telling you nothing about the doors.
- **The ping fires on `success()` only** — deliberately. Pinging after a failed
  door check would report "alive" at the exact moment the monitor is claiming
  an outage. A red run emails you; this handles silence.
- **A broken ping URL fails the step loudly** (`set -euo pipefail` plus
  `curl --fail`), which was not true of the first draft: exercised locally, a
  URL that would not resolve printed "ping delivered" and exited 0. It now
  exits non-zero.
