# StructTech OS — Internal Sales Pipeline + CRM (v1)

**Decision log (7/3/26):**
- The Field (BMR app) = client's production tool. Reference only — we adopt its concepts, not its code.
- StructTech OS = one unified system, growing schema by schema.
- V1 serves STRUCTTECH's internal funnel (getting clients), not client sales processes.
- V1 CRM layer: proposals/quotes, automated sequences, files. (Comms log = later.)

## Concepts adopted from The Field
- Dual-track: kanban stages + guided next-action inside the deal panel
- Coach's Calls → "Today" action queue (later phase)
- Append-only activity + notes
- Checklist/automation gates (our version: scan data auto-creates deals; stage changes cancel/schedule follow-ups)

## StructTech funnel stages (fixed, internal)
| Stage | Meaning | Automation |
|---|---|---|
| `new_scan` | Scan submitted, not yet contacted | Auto-created from audit_leads. Day-2 + day-5 follow-up emails auto-scheduled |
| `contacted` | Jacob reached out | |
| `call_booked` | Strategy call on calendar | Pending follow-ups auto-cancelled |
| `call_done` | Call happened, working proposal | |
| `proposal_sent` | Proposal delivered | |
| `negotiating` | Terms back-and-forth | |
| `closed_won` | Client! | Roadmap goes live, engagement starts |
| `closed_lost` | Lost (requires reason) | Kept forever — coaching data |

Manual deals (referrals, network) can be added without a scan.

## Data model (crm_v1.sql)
- `deals` — id, lead_id→audit_leads, contact fields, value, stage, lost_reason, timestamps
- `deal_notes` — append-only
- `deal_activity` — append-only audit (stage_changed, value_set, note_added, created…)
- `follow_ups` — deal_id, send_at, subject, body, status (pending/sent/cancelled)
  - Trigger: new deal from scan → schedule day-2 + day-5 emails
  - Trigger: stage advances past contacted → cancel pending
- Storage bucket `deal-files` — photos, contracts, docs per deal
- Proposals: v1 uses simple fields on deal panel (tier, price, notes) via existing `proposals` table pattern; full builder in Phase 2

## Sequences architecture
Static frontend can't send scheduled email. Sender = **Make scheduled scenario** (hourly):
1. GET follow_ups where status=pending and send_at <= now
2. Send via Gmail (jacob@structtek.com)
3. PATCH status=sent
Cancellation is DB-side (stage trigger), so Make never sends stale follow-ups.

## Phases
1. **Now:** schema + Pipeline kanban tab + deal panel (stage, value, notes, won/lost, scan/roadmap links, pending follow-ups)
2. Proposal builder (feeds Present Mode investment slide) + files UI
3. "Today" action queue (Coach's Calls for Jacob) on a dashboard tab
4. Real Supabase Auth (replaces password gate) — REQUIRED before any team member gets access
5. Present Mode (see PRESENT_MODE_PLAN.md)

## Future: client-facing version
Multi-tenant configurable stages/checklists — informed by using ours daily. Not v1.
