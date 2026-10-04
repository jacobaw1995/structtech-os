import { TwoTapDelete } from "@/components/field/TwoTapDelete";
import {
  personAvailability,
  personAvailabilityText,
  vehicleText,
  type RosterPerson,
  type RosterCrew,
} from "@/lib/crews/model";
import {
  createCrewPerson,
  updateCrewPerson,
  setCrewPersonArchived,
  deleteCrewPerson,
  addUnavailability,
  deleteUnavailability,
} from "@/lib/crews/actions";

// ONE PERSON ON THE ROSTER. Track U, U-W1.23, 2026-09-19.
//
// SCOPE §2.8 — AVAILABILITY IS A VISIBLE STATE, NEVER A BLOCK. Somebody away
// today is SAID so, in the same place as their phone number and their vehicle.
// Nothing on this card, and nothing on the crew card, disables a control
// because of it: an away person can still be put on a crew, and their crew can
// still be assigned to a work order. The office is told; the office decides.
//
// Disclosure is <details>/<summary>, so this stays a server component — same
// pattern as PoLineRow, and the FACTS are never what collapses. The card's
// standing facts are always on screen; it is the FORM that hides.

const input =
  "min-h-14 w-full rounded-md border border-border bg-bg px-2 text-base text-text outline-none focus:border-accent sm:h-10 sm:min-h-0 sm:text-sm";
const label = "text-[11px] font-semibold uppercase tracking-wide text-muted";
const primary =
  "min-h-14 rounded-md bg-accent-strong px-4 text-sm font-medium text-white sm:h-10 sm:min-h-0";
const summary =
  "flex min-h-14 cursor-pointer list-none items-center gap-2 rounded-md border border-border px-3 text-sm font-medium text-text sm:h-10 sm:min-h-0 sm:w-fit [&::-webkit-details-marker]:hidden";

function Chip({ text, warn }: { text: string; warn?: boolean }) {
  return (
    <span
      className={`rounded-full px-2 py-0.5 text-[11px] font-medium ${
        warn ? "bg-warn-soft text-[var(--warn-strong)]" : "bg-surface2 text-muted"
      }`}
    >
      {text}
    </span>
  );
}

export function PersonCard({
  orgId,
  person,
  crews,
  todayIso,
  orgMembers,
  membersReadable,
  attachedUserId,
  takenUserIds,
}: {
  orgId: string;
  person: RosterPerson;
  crews: RosterCrew[];
  todayIso: string;
  /** Everyone who has ACCEPTED their invite to this workspace. */
  orgMembers: { user_id: string; full_name: string | null }[];
  /** False = the member list could not be read. Not the same as nobody works here. */
  membersReadable: boolean;
  attachedUserId: string | null;
  takenUserIds: Set<string>;
}) {
  const availability = personAvailability(person, todayIso);
  const onCrews = crews.filter((c) => person.crew_ids.includes(c.id));

  return (
    <div id={`person-${person.id}`} className="border-b border-border px-4 py-3 last:border-0">
      <div className="flex flex-col gap-2 sm:flex-row sm:items-start sm:justify-between">
        <div className="min-w-0">
          <p className="font-medium text-text">{person.full_name}</p>
          <div className="mt-1 flex flex-wrap items-center gap-1.5">
            {person.archived && <Chip text="Archived" warn />}
            {availability.kind === "away_today" && <Chip text="Away today" warn />}
            {availability.kind === "away_later" && <Chip text={`Away from ${availability.from}`} />}
            <Chip text={vehicleText(person)} warn={person.has_vehicle === false} />
            <Chip text={person.has_login ? "Has a login" : "No login"} />
          </div>
          <p className="mt-1 text-xs text-muted">{personAvailabilityText(availability)}</p>
          <p className="mt-1 text-xs text-muted">
            {person.phone ? <span className="tabular-nums">{person.phone}</span> : "No phone recorded"}
            {person.preferred_language ? ` · speaks ${person.preferred_language}` : ""}
            {person.skills?.length ? ` · ${person.skills.join(", ")}` : ""}
          </p>
          <p className="mt-1 text-xs text-muted">
            {onCrews.length > 0
              ? `On ${onCrews.map((c) => c.name).join(", ")}`
              : "Not on a crew yet."}
          </p>
        </div>
      </div>

      <details className="group mt-2">
        <summary className={summary}>
          <span className="text-muted transition-transform group-open:rotate-90">›</span>
          Edit {person.full_name}
        </summary>

        <div className="mt-2 flex flex-col gap-3 rounded-md border border-border p-3">
          {/* ONLY WHAT CHANGED IS SENT — see updateCrewPerson. Each box carries
              what was on screen, so a form saved without an edit writes nothing
              and never calls the database. */}
          <form action={updateCrewPerson} className="flex flex-col gap-2">
            <input type="hidden" name="orgId" value={orgId} />
            <input type="hidden" name="personId" value={person.id} />
            <input type="hidden" name="full_name_was" value={person.full_name} />
            <input type="hidden" name="phone_was" value={person.phone ?? ""} />
            <input type="hidden" name="preferred_language_was" value={person.preferred_language ?? ""} />
            <input type="hidden" name="skills_was" value={person.skills?.join(", ") ?? ""} />
            <input type="hidden" name="has_vehicle_was" value={vehicleValue(person.has_vehicle)} />
            <input type="hidden" name="vehicle_note_was" value={person.vehicle_note ?? ""} />
            <input type="hidden" name="user_id_was" value={attachedUserId ?? ""} />

            <label className="flex flex-col gap-1">
              <span className={label}>Name</span>
              <input name="full_name" defaultValue={person.full_name} className={input} />
            </label>
            <div className="flex flex-col gap-2 sm:flex-row">
              <label className="flex flex-1 flex-col gap-1">
                <span className={label}>Phone</span>
                <input name="phone" defaultValue={person.phone ?? ""} className={input} />
              </label>
              <label className="flex flex-1 flex-col gap-1">
                <span className={label}>Language</span>
                <input
                  name="preferred_language"
                  defaultValue={person.preferred_language ?? ""}
                  placeholder="en"
                  className={input}
                />
              </label>
            </div>
            <label className="flex flex-col gap-1">
              <span className={label}>Skills, separated by commas</span>
              <input name="skills" defaultValue={person.skills?.join(", ") ?? ""} className={input} />
            </label>
            {/* U-W1.49 (2026-10-02) — ATTACHING A LOGIN, WHICH IS WHAT CREW
                SCOPING KEYS ON.
                Crew scoping reads crew_people.user_id. A crew person with no
                linked login is a name in a table: the scoping refusal fires
                forever and reads as a bug. The create form deliberately omits
                it — crew_check_login refuses a login that is not yet a member —
                and its own design note says a login is attached by EDITING the
                person. This is that control, and until today it did not exist.

                NOBODY TYPES A USER ID. The list is the workspace's own members,
                minus logins already attached to somebody else. The person's
                current login stays in the list so it can be seen and so
                detaching is a choice rather than a disappearance.

                `_was` CARRIES IT like every other field: a resubmitted value is
                not a deliberate write, and update_crew_person's contract is
                "key PRESENT = set, key ABSENT = leave". A form nobody touched
                sends no p_user_id at all. */}
            <label className="flex flex-col gap-1">
              <span className={label}>Login for this person</span>
              {membersReadable ? (
                <>
                  <select name="user_id" defaultValue={attachedUserId ?? ""} className={input}>
                    <option value="">No login attached</option>
                    {orgMembers
                      .filter((m) => m.user_id === attachedUserId || !takenUserIds.has(m.user_id))
                      .map((m) => (
                        <option key={m.user_id} value={m.user_id}>
                          {m.full_name?.trim() || "Unnamed member"}
                          {m.user_id === attachedUserId ? " — attached now" : ""}
                        </option>
                      ))}
                  </select>
                  {/* THE COMMON CASE, SAID BEFORE IT BECOMES A REFUSAL. Somebody
                      invited but not yet accepted is NOT in org_members, so they
                      simply are not in this list — and an office user staring at
                      a list that lacks the person they just invited needs to be
                      told why, not left to conclude the control is broken. */}
                  <span className="text-xs text-muted">
                    Only people who have accepted their invite to this workspace appear here. If you don&apos;t
                    see someone, invite them first and come back.
                  </span>
                </>
              ) : (
                <span className="text-sm text-[var(--warn-strong)]">
                  The list of people in this workspace couldn&apos;t be read just now, so there is nobody to
                  choose from. That isn&apos;t the same as there being nobody — reload and try again.
                </span>
              )}
            </label>

            <div className="flex flex-col gap-2 sm:flex-row">
              <label className="flex flex-col gap-1 sm:w-48">
                <span className={label}>Vehicle</span>
                {/* THREE VALUES, because the column has three. "Not recorded"
                    is not "no", and a two-way toggle would turn every person
                    nobody has asked yet into a person without a truck. */}
                <select name="has_vehicle" defaultValue={vehicleValue(person.has_vehicle)} className={input}>
                  <option value="">Not recorded</option>
                  <option value="true">Has a vehicle</option>
                  <option value="false">No vehicle</option>
                </select>
              </label>
              <label className="flex flex-1 flex-col gap-1">
                <span className={label}>Vehicle note</span>
                <input name="vehicle_note" defaultValue={person.vehicle_note ?? ""} className={input} />
              </label>
            </div>
            <button type="submit" className={`${primary} sm:w-fit`}>
              Save changes
            </button>
          </form>

          {/* TIME OFF. Recording it marks a state; it removes nobody from a
              crew and refuses no assignment. */}
          <div className="border-t border-border pt-3">
            <p className={label}>Time off</p>
            {person.unavailable.length === 0 ? (
              <p className="mt-1 text-xs text-muted">No upcoming time off recorded.</p>
            ) : (
              <ul className="mt-1 space-y-0.5">
                {person.unavailable.map((u) => (
                  <li key={u.id} className="flex items-center justify-between gap-2 text-xs text-muted">
                    <span className="tabular-nums">
                      {u.starts_on} → {u.ends_on}
                      {u.reason ? ` · ${u.reason}` : ""}
                    </span>
                    <form action={deleteUnavailability}>
                      <input type="hidden" name="orgId" value={orgId} />
                      <input type="hidden" name="personId" value={person.id} />
                      <input type="hidden" name="unavailabilityId" value={u.id} />
                      <button type="submit" className="min-h-14 px-3 text-xs text-muted hover:text-warn sm:min-h-0 sm:py-1">
                        Remove
                      </button>
                    </form>
                  </li>
                ))}
              </ul>
            )}
            <form action={addUnavailability} className="mt-2 flex flex-col gap-2 sm:flex-row sm:items-end">
              <input type="hidden" name="orgId" value={orgId} />
              <input type="hidden" name="personId" value={person.id} />
              <label className="flex flex-col gap-1">
                <span className={label}>First day</span>
                <input type="date" name="starts_on" className={input} />
              </label>
              <label className="flex flex-col gap-1">
                <span className={label}>Last day</span>
                <input type="date" name="ends_on" className={input} />
              </label>
              <label className="flex flex-1 flex-col gap-1">
                <span className={label}>Reason</span>
                <input name="reason" className={input} />
              </label>
              <button type="submit" className={primary}>
                Mark away
              </button>
            </form>
          </div>

          {/* §2.6 — what the user made, the user can fix or remove. Archive is
              the reversible one and is offered first. */}
          <div className="flex flex-col gap-2 border-t border-border pt-3 sm:flex-row sm:items-center">
            <form action={setCrewPersonArchived}>
              <input type="hidden" name="orgId" value={orgId} />
              <input type="hidden" name="personId" value={person.id} />
              <input type="hidden" name="archived" value={person.archived ? "false" : "true"} />
              <button
                type="submit"
                className="min-h-14 rounded-md border border-border px-3 text-sm font-medium text-text sm:h-10 sm:min-h-0"
              >
                {person.archived ? "Restore" : "Archive"}
              </button>
            </form>
            <div className="sm:w-72">
              <TwoTapDelete
                action={deleteCrewPerson}
                fields={{ orgId, personId: person.id }}
                label="Delete permanently"
                confirmLabel="Delete"
                question={`Delete ${person.full_name}? Their crew memberships and time off go with them.`}
              />
            </div>
          </div>
        </div>
      </details>
    </div>
  );
}

function vehicleValue(v: boolean | null): string {
  return v === true ? "true" : v === false ? "false" : "";
}

/** Add a person. Deliberately short: a name is the only thing S requires. */
export function AddPersonForm({ orgId }: { orgId: string }) {
  return (
    <form action={createCrewPerson} className="flex flex-col gap-2 px-4 py-3 sm:flex-row sm:items-end">
      <input type="hidden" name="orgId" value={orgId} />
      <label className="flex flex-1 flex-col gap-1">
        <span className={label}>Name</span>
        <input name="full_name" placeholder="Full name" className={input} />
      </label>
      <label className="flex flex-col gap-1 sm:w-40">
        <span className={label}>Phone</span>
        <input name="phone" className={input} />
      </label>
      <label className="flex flex-col gap-1 sm:w-40">
        <span className={label}>Vehicle</span>
        <select name="has_vehicle" defaultValue="" className={input}>
          <option value="">Not recorded</option>
          <option value="true">Has a vehicle</option>
          <option value="false">No vehicle</option>
        </select>
      </label>
      <button type="submit" className={primary}>
        Add person
      </button>
    </form>
  );
}
