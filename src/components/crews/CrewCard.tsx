import { TwoTapDelete } from "@/components/field/TwoTapDelete";
import type { RosterCrew, RosterPerson, AssignmentState } from "@/lib/crews/model";
import { personAvailability } from "@/lib/crews/model";
import {
  VEHICLE_STATE_COPY,
  AVAILABILITY_STATE_COPY,
  needsAttention,
  type VehicleState,
  type AvailabilityState,
} from "@/lib/crews/crew-states";
import {
  createCrew,
  renameCrew,
  setCrewArchived,
  deleteCrew,
  addCrewMember,
  removeCrewMember,
  assignCrewToWorkOrder,
  unassignCrewFromWorkOrder,
} from "@/lib/crews/actions";

// ONE CREW. Track U, U-W1.23, 2026-09-19.
//
// THE STATES ARE TRACK S's, AND THEY ARE STATES. crew_assignment_states answers
// vehicle_state and availability_state per assignment;
// assign_crew_to_work_order returns both and refuses on NEITHER. So this card
// SHOWS them — next to the assignment they belong to, where they stay visible —
// and offers the same controls whatever they say. A crew with nobody on it can
// still be assigned. A crew with somebody away during the scheduled days can
// still be assigned. SCOPE §2.8.
//
// WHY THE PICKER ONLY OFFERS LIVE TRADE WORK ORDERS.
// work_order_crew_assignments_validate refuses a master, a voided work order
// and a cross-org work order — all three WITHOUT a hint (reported to S), so
// they would arrive here as the generic "that wasn't saved". Offering only what
// the trigger accepts keeps those three unreachable. It is a mitigation, not a
// fix: the hints are S's to add.

const input =
  "min-h-14 w-full rounded-md border border-border bg-bg px-2 text-base text-text outline-none focus:border-accent sm:h-10 sm:min-h-0 sm:text-sm";
const label = "text-[11px] font-semibold uppercase tracking-wide text-muted";
const primary =
  "min-h-14 rounded-md bg-accent-strong px-4 text-sm font-medium text-white sm:h-10 sm:min-h-0";
const summary =
  "flex min-h-14 cursor-pointer list-none items-center gap-2 rounded-md border border-border px-3 text-sm font-medium text-text sm:h-10 sm:min-h-0 sm:w-fit [&::-webkit-details-marker]:hidden";

export type AssignableWorkOrder = { id: string; trade: string | null; jobLabel: string };

function StateLine({ state, copy }: { state: string | null; copy: string | undefined }) {
  if (!copy) return null;
  return (
    <p className={`text-xs ${state && needsAttention(state as VehicleState) ? "text-[var(--warn-strong)]" : "text-muted"}`}>
      {copy}
    </p>
  );
}

export function CrewCard({
  orgId,
  crew,
  people,
  states,
  workOrders,
  todayIso,
}: {
  orgId: string;
  crew: RosterCrew;
  people: RosterPerson[];
  states: AssignmentState[];
  workOrders: AssignableWorkOrder[];
  todayIso: string;
}) {
  const byId = new Map(people.map((p) => [p.id, p]));
  const members = crew.members
    .map((m) => ({ ...m, person: byId.get(m.person_id) }))
    .filter((m): m is { person_id: string; is_lead: boolean; person: RosterPerson } => Boolean(m.person));
  const awayToday = members.filter((m) => personAvailability(m.person, todayIso).kind === "away_today");
  // Archived people keep their membership rows but are not counted by S's view,
  // so they are not counted here either — one arithmetic, not two.
  const liveMembers = members.filter((m) => !m.person.archived);
  const notMembers = people.filter((p) => !p.archived && !crew.members.some((m) => m.person_id === p.id));
  const assignedIds = new Set(crew.assignments.map((a) => a.work_order_id));

  return (
    <div id={`crew-${crew.id}`} className="border-b border-border px-4 py-3 last:border-0">
      <div className="flex flex-wrap items-baseline justify-between gap-x-3">
        <p className="font-medium text-text">
          {crew.name}
          {crew.archived && <span className="ml-2 text-xs font-normal text-[var(--warn-strong)]">Archived</span>}
        </p>
        <p className="text-xs tabular-nums text-muted">
          {liveMembers.length} {liveMembers.length === 1 ? "member" : "members"}
          {awayToday.length > 0 ? ` · ${awayToday.length} away today` : ""}
        </p>
      </div>

      <p className="mt-1 text-xs text-muted">
        {liveMembers.length === 0
          ? "Nobody is on this crew yet."
          : liveMembers
              .map((m) => `${m.person.full_name}${m.is_lead ? " (lead)" : ""}`)
              .join(", ")}
      </p>

      {/* ASSIGNMENTS, with the states beside them. */}
      <div className="mt-2">
        <p className={label}>Work orders</p>
        {crew.assignments.length === 0 ? (
          <p className="mt-1 text-xs text-muted">Not assigned to any work order.</p>
        ) : (
          <ul className="mt-1 space-y-2">
            {crew.assignments.map((a) => {
              const s = states.find((x) => x.assignment_id === a.assignment_id);
              const wo = workOrders.find((w) => w.id === a.work_order_id);
              return (
                <li key={a.assignment_id} className="rounded-md bg-surface2 px-3 py-2">
                  <div className="flex flex-wrap items-baseline justify-between gap-x-3">
                    <span className="text-sm font-medium text-text">
                      {wo?.jobLabel ?? "Work order"}
                      {s?.trade ? ` · ${s.trade}` : wo?.trade ? ` · ${wo.trade}` : ""}
                    </span>
                    <span className="text-xs tabular-nums text-muted">
                      {s?.start_date ? `${s.start_date} → ${s.end_date ?? s.start_date}` : "Not scheduled"}
                    </span>
                  </div>
                  {a.task && <p className="text-xs text-muted">{a.task}</p>}
                  <StateLine
                    state={s?.availability_state ?? null}
                    copy={s?.availability_state ? AVAILABILITY_STATE_COPY[s.availability_state as AvailabilityState] : undefined}
                  />
                  <StateLine
                    state={s?.vehicle_state ?? null}
                    copy={s?.vehicle_state ? VEHICLE_STATE_COPY[s.vehicle_state as VehicleState] : undefined}
                  />
                  <form action={unassignCrewFromWorkOrder}>
                    <input type="hidden" name="orgId" value={orgId} />
                    <input type="hidden" name="crewId" value={crew.id} />
                    <input type="hidden" name="assignmentId" value={a.assignment_id} />
                    <button type="submit" className="min-h-14 text-xs text-muted hover:text-warn sm:min-h-0 sm:py-1">
                      Unassign
                    </button>
                  </form>
                </li>
              );
            })}
          </ul>
        )}
      </div>

      <details className="group mt-2">
        <summary className={summary}>
          <span className="text-muted transition-transform group-open:rotate-90">›</span>
          Manage {crew.name}
        </summary>

        <div className="mt-2 flex flex-col gap-3 rounded-md border border-border p-3">
          {/* MEMBERS */}
          <div>
            <p className={label}>Members</p>
            {members.length === 0 ? (
              <p className="mt-1 text-xs text-muted">Nobody yet.</p>
            ) : (
              <ul className="mt-1 space-y-0.5">
                {members.map((m) => (
                  <li key={m.person_id} className="flex items-center justify-between gap-2 text-xs text-muted">
                    <span>
                      {m.person.full_name}
                      {m.is_lead ? " · lead" : ""}
                      {m.person.archived ? " · archived" : ""}
                      {personAvailability(m.person, todayIso).kind === "away_today" ? " · away today" : ""}
                    </span>
                    <form action={removeCrewMember}>
                      <input type="hidden" name="orgId" value={orgId} />
                      <input type="hidden" name="crewId" value={crew.id} />
                      <input type="hidden" name="personId" value={m.person_id} />
                      <button type="submit" className="min-h-14 px-3 text-xs text-muted hover:text-warn sm:min-h-0 sm:py-1">
                        Remove
                      </button>
                    </form>
                  </li>
                ))}
              </ul>
            )}
            {notMembers.length > 0 && (
              <form action={addCrewMember} className="mt-2 flex flex-col gap-2 sm:flex-row sm:items-end">
                <input type="hidden" name="orgId" value={orgId} />
                <input type="hidden" name="crewId" value={crew.id} />
                <label className="flex flex-1 flex-col gap-1">
                  <span className={label}>Add someone</span>
                  {/* U-W1.32 (2026-09-23) — NOBODY IS CHOSEN UNTIL SOMEBODY
                      CHOOSES. This select had no placeholder, so it rested on
                      the first person in the list and pressing "Add to crew"
                      untouched put a REAL person on a REAL crew that nobody
                      picked. Same class as "No predecessor" on the new-trade
                      row, and mine, shipped 2026-09-19. The empty option is
                      the resting state and `required` stops the submit. */}
                  <select name="personId" defaultValue="" required className={input}>
                    <option value="">Choose a person…</option>
                    {notMembers.map((p) => (
                      <option key={p.id} value={p.id}>
                        {p.full_name}
                        {personAvailability(p, todayIso).kind === "away_today" ? " — away today" : ""}
                      </option>
                    ))}
                  </select>
                </label>
                <label className="flex min-h-14 items-center gap-2 rounded-md border border-border px-3 text-sm text-text sm:h-10 sm:min-h-0">
                  <input type="checkbox" name="is_lead" value="true" className="h-5 w-5" />
                  Lead
                </label>
                <button type="submit" className={primary}>
                  Add to crew
                </button>
              </form>
            )}
          </div>

          {/* ASSIGN */}
          <div className="border-t border-border pt-3">
            {workOrders.length === 0 ? (
              <p className="text-xs text-muted">
                There are no live trade work orders in this workspace to assign a crew to yet.
              </p>
            ) : (
              <form action={assignCrewToWorkOrder} className="flex flex-col gap-2 sm:flex-row sm:items-end">
                <input type="hidden" name="orgId" value={orgId} />
                <input type="hidden" name="crewId" value={crew.id} />
                <label className="flex flex-1 flex-col gap-1">
                  <span className={label}>Assign to a work order</span>
                  {/* U-W1.32 — same defect, heavier consequence: untouched,
                      this booked a crew onto whichever job happened to sort
                      first. */}
                  <select name="workOrderId" defaultValue="" required className={input}>
                    <option value="">Choose a work order…</option>
                    {workOrders.map((w) => (
                      <option key={w.id} value={w.id}>
                        {w.jobLabel}
                        {w.trade ? ` · ${w.trade}` : ""}
                        {assignedIds.has(w.id) ? " — already assigned" : ""}
                      </option>
                    ))}
                  </select>
                </label>
                <label className="flex flex-1 flex-col gap-1">
                  <span className={label}>What they are doing</span>
                  <input name="task" className={input} />
                </label>
                <button type="submit" className={primary}>
                  Assign
                </button>
              </form>
            )}
          </div>

          {/* RENAME · ARCHIVE · DELETE (§2.6) */}
          <form action={renameCrew} className="flex flex-col gap-2 border-t border-border pt-3 sm:flex-row sm:items-end">
            <input type="hidden" name="orgId" value={orgId} />
            <input type="hidden" name="crewId" value={crew.id} />
            <input type="hidden" name="name_was" value={crew.name} />
            <label className="flex flex-1 flex-col gap-1">
              <span className={label}>Crew name</span>
              <input name="name" defaultValue={crew.name} className={input} />
            </label>
            <button type="submit" className={primary}>
              Rename
            </button>
          </form>

          <div className="flex flex-col gap-2 border-t border-border pt-3 sm:flex-row sm:items-center">
            <form action={setCrewArchived}>
              <input type="hidden" name="orgId" value={orgId} />
              <input type="hidden" name="crewId" value={crew.id} />
              <input type="hidden" name="archived" value={crew.archived ? "false" : "true"} />
              <button
                type="submit"
                className="min-h-14 rounded-md border border-border px-3 text-sm font-medium text-text sm:h-10 sm:min-h-0"
              >
                {crew.archived ? "Restore" : "Archive"}
              </button>
            </form>
            <div className="sm:w-72">
              <TwoTapDelete
                action={deleteCrew}
                fields={{ orgId, crewId: crew.id }}
                label="Delete permanently"
                confirmLabel="Delete"
                question={`Delete ${crew.name}? Its members go back to the roster; the people are not deleted.`}
              />
            </div>
          </div>
        </div>
      </details>
    </div>
  );
}

export function AddCrewForm({ orgId }: { orgId: string }) {
  return (
    <form action={createCrew} className="flex flex-col gap-2 px-4 py-3 sm:flex-row sm:items-end">
      <input type="hidden" name="orgId" value={orgId} />
      <label className="flex flex-1 flex-col gap-1">
        <span className={label}>Crew name</span>
        <input name="name" placeholder="e.g. Tear-off crew" className={input} />
      </label>
      <button type="submit" className={primary}>
        Add crew
      </button>
    </form>
  );
}
