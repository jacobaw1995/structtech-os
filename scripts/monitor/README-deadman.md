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
   - Schedule: **Period 1 hour**, **Grace 7 hours**
   - Why 7 h and not 1 h: the *delivered* worst gap measured on this repo is
     **6 h 06 m** (n=34 over 126 h, mean 3 h 35 m — refreshed 2026-09-09; the
     worst gap, which is the number this grace rests on, has not moved since
     it was first measured). A 1-hour grace would page
     you several times a day about GitHub's queue rather than about your site.
     Seven hours is deliberately loose — it is watching for *death*, not
     lateness. If the delivered cadence ever improves, tighten it.
   - This was 3 hours until 2026-09-07. It was raised on controller decision
     after the in-workflow drift check went red at 366 min against a 360 min
     threshold with every door green — a live demonstration that a grace
     narrower than the observed worst gap alarms on the platform, not on us.
3. **Put the ping URL straight into the repository secret, from a terminal.**
   The value goes from the Healthchecks page to a hidden prompt and nowhere
   else — not a chat, not a file, not an argument, not shell history.
   Run, then leave the prompt waiting:
   `gh secret set DEADMAN_PING_URL --repo jacobaw1995/structtech-os`
   (With no `--body`, `gh` reads the value from an interactive paste prompt —
   `gh secret set --help`. Never add `--body`: that puts the value in history.)
4. On the check's page, use the copy button beside its **Ping URL**
   (`https://hc-ping.com/…`), paste at the prompt, press Enter, then clear the
   clipboard with `pbcopy < /dev/null`. The URL is a capability: anyone holding
   it can silence the alarm.
5. Confirm the alert destination on the Healthchecks side (email is on by
   default for the account address).

## Confirming it actually works — do not skip this

A dead-man's switch you have not seen fire is a belief, not a control.

1. **Prove the switch is ARMED — delivery, not presence.** The ping step only
   runs on `schedule` (a manual "Run workflow" never pings), so wait for the next
   scheduled run (~3.7 h apart on average), then:
   `GITHUB_TOKEN="$(gh auth token)" DEADMAN_ARMED_SINCE=<the time you set it, ISO-8601> node scripts/monitor/verify-deadman.mjs`
   `ARMED` (exit 0) means a scheduled run delivered a ping and the URL answered
   2xx. `NOT ARMED` (exit 1) means the step ran and the secret was absent or the
   URL was refused. `UNDETERMINED` (exit 2) means no scheduled run has exercised
   it yet. The script ignores the step's echoed script text on purpose: the log
   of a run with NO secret contains the words "ping delivered" (see its header).
2. **Prove the alarm FIRES — only after step 1 says ARMED**, so the check has
   received a real ping. On Healthchecks, edit the check's schedule and set
   **Period and Grace to the smallest values the form allows**. The docs define
   grace as "the additional time to wait before sending an alert when a check is
   late", so with no ping due for hours the check goes late, then down, within
   minutes — confirm the email arrives, then **restore Period 1 hour / Grace 7
   hours**. Until you have seen that email once, the control is unproven.
   **Do not use Pause for this.** An earlier version of this file said to. The
   docs describe pausing as the way "to avoid unwanted alerts about a known
   issue" — it is the one action most likely to prove nothing.

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
