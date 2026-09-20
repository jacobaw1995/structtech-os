import Link from "next/link";
import { requireModuleAccess } from "@/lib/workspace/context";
import { PersonCard, AddPersonForm } from "@/components/crews/PersonCard";
import { CrewCard, AddCrewForm, type AssignableWorkOrder } from "@/components/crews/CrewCard";
import { parseRoster, type AssignmentState } from "@/lib/crews/model";
import { CREW_HINT_COPY, isCrewHint } from "@/lib/crews/crew-states";
import { jobLabel } from "@/lib/purchasing/model";
import { todayInNewYork } from "@/lib/home/model";

// THE CREW SCREEN, OFFICE SIDE. Track U, U-W1.23, 2026-09-19.
//
// ONE READ FOR THE ROSTER. fetch_crew_roster(org) returns people (with their
// crews and their live time off) and crews (with their members and their
// assignments) as one jsonb document. There is no per-row follow-up anywhere on
// this page. Two further list reads sit beside it and do not grow with the
// roster: crew_assignment_states, for the two states that depend on the
// SCHEDULE and so cannot be in the roster document, and the live trade work
// orders the assign picker offers.
//
// SCOPE §2.8, today's condition, applied throughout: availability and vehicle
// are STATES. Nothing here disables a control because somebody is away, because
// a crew has no members, or because nobody on it has a truck. The office is
// told, in Track S's words, and the office decides.

export default async function CrewsPage({
  params,
  searchParams,
}: {
  params: { orgId: string };
  searchParams: { e?: string };
}) {
  const ctx = await requireModuleAccess(params.orgId, "coordination");
  const supabase = ctx.supabase;
  const today = todayInNewYork();

  const [{ data: rosterData }, { data: stateRows }, { data: woRows }, { data: canSchedule }] =
    await Promise.all([
      supabase.rpc("fetch_crew_roster", { p_org_id: params.orgId }),
      // S's view, security_invoker — the caller's own RLS scopes it.
      supabase.from("crew_assignment_states").select("*").eq("org_id", params.orgId),
      // What the assign picker may offer: live TRADE work orders in this org,
      // which is exactly what work_order_crew_assignments_validate accepts.
      supabase
        .from("work_orders")
        .select(
          "id, trade, job:jobs(created_at, service_address_street, service_address_city, service_address_state, service_address_zip, estimate:estimates(company, contact_name))"
        )
        .eq("org_id", params.orgId)
        .eq("kind", "trade")
        .is("voided_at", null)
        .order("created_at", { ascending: false }),
      supabase.rpc("has_capability", { p_org_id: params.orgId, p_capability: "schedule" }),
    ]);

  const roster = parseRoster(rosterData);
  const states = (stateRows ?? []) as unknown as AssignmentState[];
  const workOrders: AssignableWorkOrder[] = (woRows ?? []).map((w) => {
    const job = w.job as
      | (Parameters<typeof jobLabel>[0] & { estimate: Parameters<typeof jobLabel>[1] })
      | null;
    return {
      id: w.id,
      trade: w.trade,
      jobLabel: job ? jobLabel(job, job.estimate ?? null) : "Work order",
    };
  });

  return (
    <div className="flex flex-col gap-6 p-4 sm:p-6">
      <div>
        <Link href={`/w/${params.orgId}/coordination`} className="text-sm text-muted hover:text-text">
          ← Coordination
        </Link>
        <h1 className="mt-1 text-xl font-semibold text-text">Crews</h1>
        <p className="mt-1 text-sm text-muted">
          Who works here, which crew they are on, when they are away, and which work orders each crew is on.
        </p>
      </div>

      {/* A CODE, LOOKED UP — never the URL's own text (controller ruling
          2026-09-15). The sentence is Track S's, via its hint. */}
      {isCrewHint(searchParams.e) && (
        <p role="alert" className="rounded-md bg-warn-soft px-3 py-2 text-sm text-text">
          {CREW_HINT_COPY[searchParams.e]}
        </p>
      )}

      {/* A ROSTER THAT COULD NOT BE READ IS NOT AN EMPTY ROSTER. */}
      {!roster ? (
        <p className="rounded-md border border-border px-4 py-3 text-sm text-[var(--warn-strong)]">
          The roster could not be read for your account. That is not the same as there being nobody on it —
          reload, and tell the office if it keeps happening.
        </p>
      ) : (
        <>
          {canSchedule !== true && (
            <p className="rounded-md bg-surface2 px-3 py-2 text-sm text-muted">
              {CREW_HINT_COPY.no_schedule_capability} You can read the roster below; saving a change will be
              refused.
            </p>
          )}

          <section id="people" className="rounded-xl border border-border bg-surface">
            <div className="flex flex-wrap items-baseline justify-between gap-x-3 border-b border-border px-4 py-3">
              <h2 className="text-sm font-semibold uppercase tracking-wide text-muted">People</h2>
              <p className="text-xs tabular-nums text-muted">
                {roster.people.filter((p) => !p.archived).length} on the roster
                {roster.people.some((p) => p.archived)
                  ? ` · ${roster.people.filter((p) => p.archived).length} archived`
                  : ""}
              </p>
            </div>
            <AddPersonForm orgId={params.orgId} />
            {roster.people.length === 0 ? (
              <p className="border-t border-border px-4 py-3 text-sm text-muted">
                Nobody has been added yet. Add the first person above.
              </p>
            ) : (
              <div className="border-t border-border">
                {roster.people.map((person) => (
                  <PersonCard
                    key={person.id}
                    orgId={params.orgId}
                    person={person}
                    crews={roster.crews}
                    todayIso={today}
                  />
                ))}
              </div>
            )}
          </section>

          <section id="crews" className="rounded-xl border border-border bg-surface">
            <div className="flex flex-wrap items-baseline justify-between gap-x-3 border-b border-border px-4 py-3">
              <h2 className="text-sm font-semibold uppercase tracking-wide text-muted">Crews</h2>
              <p className="text-xs tabular-nums text-muted">
                {roster.crews.filter((c) => !c.archived).length} live
              </p>
            </div>
            <AddCrewForm orgId={params.orgId} />
            {roster.crews.length === 0 ? (
              <p className="border-t border-border px-4 py-3 text-sm text-muted">
                No crews yet. A crew is a named group of the people above; a work order is assigned to a crew,
                not to a person.
              </p>
            ) : (
              <div className="border-t border-border">
                {roster.crews.map((crew) => (
                  <CrewCard
                    key={crew.id}
                    orgId={params.orgId}
                    crew={crew}
                    people={roster.people}
                    states={states}
                    workOrders={workOrders}
                    todayIso={today}
                  />
                ))}
              </div>
            )}
          </section>
        </>
      )}
    </div>
  );
}
