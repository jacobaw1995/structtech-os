import { redirect } from "next/navigation";
import { requireModuleAccess } from "@/lib/workspace/context";
import { cookies } from "next/headers";
import { FieldShell } from "@/components/field/FieldShell";
import { OUTDOOR_COOKIE, parseOutdoorCookie } from "@/lib/field/outdoor";
import { CheckInRow } from "@/components/field/CheckInRow";
import { AddCheckInForm } from "@/components/field/AddCheckInForm";
import { SpecialTripPanel } from "@/components/field/SpecialTripPanel";
import { ActionForm } from "@/components/field/ActionForm";
import { recordSpecialTrip, deleteSpecialTrip } from "@/lib/field/special-trip-actions";
import { specialTripReason } from "@/lib/field/special-trip";
import { ProductionPacketView } from "@/components/field/ProductionPacketView";
import { todayInNewYork } from "@/lib/home/model";
import { FIELD_ERROR_COPY, isFieldError, FIELD_NOTICE_COPY, isFieldNotice } from "@/lib/field/field-errors";
import { MaterialsList, type FieldMaterial } from "@/components/field/MaterialsList";
import { WorkOrderFiles } from "@/components/files/WorkOrderFiles";
import { FieldReadyBeacon } from "@/components/field/FieldReadyBeacon";
import { QcPanel } from "@/components/field/QcPanel";
import { fetchQcRows, photoRef } from "@/lib/field/qc-data";
import { isQcResult } from "@/lib/field/qc";
import { recordFieldEvent } from "@/lib/observability/field-events";
import { isFilesStateFor } from "@/lib/storage/work-order-files-states";
import type { Database } from "@/lib/supabase/database.types";

type WorkOrder = Database["public"]["Tables"]["work_orders"]["Row"];
type CheckIn = Database["public"]["Tables"]["check_ins"]["Row"];
type ProductionPacket = Database["public"]["Tables"]["production_packets"]["Row"];

// U-W1.16 (2026-09-15) — NO MONEY BY CONSTRUCTION, NOT BY FILTERING. What the
// paragraphs below describe was true and was still filtering: this page called
// fetch_estimate(), which returns the WHOLE `estimates` row (SETOF estimates)
// and blanks subtotal, presented_total, tax_rate and tax_amount for a caller
// without view_financials. The money columns were in the type, in the payload
// shape, and one changed branch away from being filled — and the row also
// carried the customer's email, phone and notes_terms, none of which a crew
// needs. The page no longer calls it. The header now comes from
// fetch_field_jobs(), whose jsonb has no money key to fill, and from the job's
// service address. A price cannot arrive here because nothing this page reads
// has a place to put one.
//
// A1.5 — no dollar values reach this page, and that is now enforced below the
// UI rather than promised by it. fetch_estimate() returns subtotal,
// presented_total, tax_rate and tax_amount as NULL to any caller who fails
// can_view_financials(), and `estimates` is closed to a crew-tier member by a
// RESTRICTIVE policy, so a crew cannot reach a price through this RPC, through
// a direct table read, or through an edit to the JSX below.
//
// A2.0 (2026-08-24) — can_view_financials() is now a THIN WRAPPER over
// has_capability(org, 'view_financials') rather than a second implementation
// of the same idea. Everything above still holds; what changed is that it can
// no longer disagree with has_capability(), which it did for a crew-tier
// member until today (can_view_financials false, has_capability true). Both
// now answer from one closed-default body. Constraint 7 is enforced by the
// crew's SEEDED permissions row (view_financials false), not by a role test
// buried in the read path.
//
// A crew landing on a MASTER's URL: fetch_work_order() applies the same crew
// gate as the RLS policy, so it returns zero rows and the guard below redirects
// to /field. A clean redirect, not a stack trace and not an empty shell.
export default async function FieldJobPage({
  params,
  searchParams,
}: {
  params: { orgId: string; workOrderId: string };
  searchParams: { tab?: string; error?: string; files?: string; qc?: string; saved?: string };
}) {
  const ctx = await requireModuleAccess(params.orgId, "field");
  const supabase = ctx.supabase;
  const tab =
    searchParams.tab === "packet" ? "packet" : searchParams.tab === "materials" ? "materials" : "check-in";

  // Single-record fetch RPC (CLAUDE.md rule 4), same pattern as
  // coordination's fetch_work_order.
  const { data: fetchedWorkOrder } = await supabase.rpc("fetch_work_order", {
    p_work_order_id: params.workOrderId,
  });
  const workOrder = fetchedWorkOrder?.[0] as WorkOrder | undefined;

  // Covers three cases with one redirect: no such work order, a work order in
  // another of this user's orgs, and — after A1.5 — a master that this role is
  // not allowed to see at all.
  if (!workOrder || workOrder.org_id !== params.orgId) {
    redirect(`/w/${params.orgId}/field`);
  }

  // X-W1.19: the open, durably — started now, awaited below, bounded at 800 ms and
  // run alongside the page's own queries, so it adds no latency in the normal case
  // and can never fail the page.
  const opened = recordFieldEvent(supabase, {
    orgId: params.orgId,
    event: tab === "packet" ? "packet_opened" : "work_order_opened",
    workOrderId: workOrder.id,
  });

  const [{ data: fieldJobsData }, { data: jobRows }, { data: checkInsData }, materialsRes, tripsRes] = await Promise.all([
    // The same money-free read the Today list uses. It covers a work order with
    // a schedule block ending today or later; a work order with no such block
    // falls back to the job's address below, and says so rather than guessing
    // a title.
    supabase.rpc("fetch_field_jobs", { p_org_id: params.orgId, p_today: todayInNewYork() }),
    // List query (rule 5), filtered to this job. The job's service address is a
    // deliberate crew copy (A1.5); nothing on `jobs` is money.
    supabase
      .from("jobs")
      .select("service_address_street, service_address_city, service_address_state, service_address_zip")
      .eq("id", workOrder.job_id ?? "")
      .eq("org_id", params.orgId),
    supabase
      .from("check_ins")
      .select("*")
      .eq("work_order_id", workOrder.id)
      .order("check_in_date", { ascending: false })
      .order("created_at", { ascending: false }),
    // U-W1.22 — this trade's materials. FOUR COLUMNS, and material_items has no
    // money column at all (checked 2026-09-19), so there is nothing to filter.
    // List query (rule 5); the crew's own RLS scopes it to their org.
    supabase
      .from("material_items")
      .select("id, name, quantity, unit, ready_by, ready_by_source", { count: "exact" })
      .eq("work_order_id", workOrder.id)
      .order("sort_order", { ascending: true }),
    // U-W1.42 — the trips already recorded on this job. List query (rule 5);
    // the crew's own RLS scopes it. Nothing here is money.
    supabase
      .from("special_trips")
      .select("id, reason_code, occurred_on, note")
      .eq("work_order_id", workOrder.id)
      .order("occurred_on", { ascending: false }),
  ]);

  type FieldJob = { work_order_id: string; job_title: string | null; site_address: string | null; squares: number | null; pitch: string | null; crew_name: string | null };
  const header = ((fieldJobsData ?? []) as unknown as FieldJob[]).find((j) => j.work_order_id === workOrder.id);
  const job = (jobRows ?? [])[0];
  const jobAddress = job
    ? [job.service_address_street, job.service_address_city, job.service_address_state, job.service_address_zip]
        .filter((p): p is string => Boolean(p && p.trim()))
        .join(", ")
    : "";
  const checkIns = (checkInsData ?? []) as CheckIn[];
  // An unreadable trip list renders as NO list rather than as "no trips" — the
  // same rule the materials tab and the QC panel already follow.
  const trips = (!tripsRes.error && tripsRes.data ? tripsRes.data : []) as {
    id: string;
    reason_code: string;
    occurred_on: string;
    note: string | null;
  }[];
  // A read that came back short is not a read (PostgREST max_rows): the count and
  // the rows must agree, or the tab says it could not be read.
  const materials =
    !materialsRes.error && materialsRes.data && materialsRes.count === materialsRes.data.length
      ? (materialsRes.data as FieldMaterial[])
      : null;
  const jobTitle = header?.job_title || "Job";
  const siteAddress = header?.site_address || jobAddress || null;
  // WHAT THE CREW BOX STARTS WITH, in order, and why that order (2026-10-04).
  // 1. the crew named on the LAST check-in on this job — what the people
  //    actually doing this work called themselves, most recently;
  // 2. failing that, the crew on the SCHEDULE BLOCK — which is the same name
  //    the crew just read on the job card they tapped to get here, so the box
  //    agrees with the screen they came from rather than introducing a name;
  // 3. failing both, EMPTY, with its placeholder. Not a guess, and not a
  //    blocked submit: the server refuses a blank by name (crew_required).
  // TWO LIMITS OF (2), stated because the fallback looks more complete than it
  // is. It comes from fetch_field_jobs, which keeps a job from creation until
  // end_date — so after end_date `header` is undefined and the box is empty
  // again. And that RPC projects sb.crew_name RAW, with no coalesce onto the
  // crews record, so a block attached by crew_id alone (crew_name null) gives
  // nothing here even though the crew has a name. Both land on (3), which is
  // safe; neither is fixed by this change.
  const lastCrewName = checkIns[0]?.crew_name ?? header?.crew_name ?? undefined;

  // get_or_create is idempotent (migration header note) — only called when
  // the Packet tab is actually open, not on every visit to the job.
  let packet: ProductionPacket | undefined;
  if (tab === "packet") {
    const { data: packetId } = await supabase.rpc("get_or_create_production_packet", {
      p_work_order_id: workOrder.id,
    });
    if (packetId) {
      const { data: fetchedPacket } = await supabase.rpc("fetch_production_packet", {
        p_production_packet_id: packetId,
      });
      packet = fetchedPacket?.[0] as ProductionPacket | undefined;
    }
  }

  const allPhotos = checkIns.flatMap((c) => c.photos);

  // X-W1.20 (A4.3) — the required checks. The photo references are computed from
  // the photos that exist on this job right now, so a QC row whose photo was
  // deleted reads "photo removed" instead of "done".
  const qc = tab === "check-in" ? await fetchQcRows(supabase, workOrder.id) : null;
  const photoRefs = new Set(qc ? allPhotos.map((p) => photoRef(p)) : []);
  await opened;

  return (
    <FieldShell
      initialOutdoor={parseOutdoorCookie(cookies().get(OUTDOOR_COOKIE)?.value)}
      backHref={`/w/${params.orgId}/field`}
      backLabel="← Today"
      tabs={[
        {
          label: "Check-in",
          href: `/w/${params.orgId}/field/${workOrder.id}?tab=check-in`,
          active: tab === "check-in",
        },
        {
          label: "Materials",
          href: `/w/${params.orgId}/field/${workOrder.id}?tab=materials`,
          active: tab === "materials",
        },
        {
          label: "Packet",
          href: `/w/${params.orgId}/field/${workOrder.id}?tab=packet`,
          active: tab === "packet",
        },
      ]}
    >
      <FieldReadyBeacon orgId={params.orgId} workOrderId={workOrder.id} />
      <p className="text-lg font-bold text-text group-data-[outdoor=true]/field:text-white">
        {tab === "check-in" ? `Check-in · ${jobTitle}` : jobTitle}
      </p>

      {/* U-W1.20 — a CODE, looked up; an unknown value renders nothing. Before
          this, any link could put any words in this banner on a crew screen. */}
      {isFieldError(searchParams.error) && (
        <p role="alert" className="rounded-md bg-warn-soft px-3 py-2 text-sm text-text">
          {FIELD_ERROR_COPY[searchParams.error]}
        </p>
      )}

      {/* U-W1.52 — IT SAYS IT WORKED, in the same place a failure appears and
          deliberately NOT in the same clothes: status on accent-soft, where a
          failure is alert on warn-soft. A failure that reads like a success is
          worse than either. The count beside it is the honest second half — it
          is read from the list, so if it says 3 there are 3, and a roofer who
          tapped twice can SEE that he did. */}
      {!isFieldError(searchParams.error) && isFieldNotice(searchParams.saved) && (
        <p role="status" data-saved={searchParams.saved} className="rounded-md bg-accent-soft px-3 py-2 text-sm text-accent-strong">
          {FIELD_NOTICE_COPY[searchParams.saved]} {checkIns.length}{" "}
          {checkIns.length === 1 ? "check-in" : "check-ins"} on this job.
        </p>
      )}

      {tab === "check-in" && (
        /* U-W1.10 — THE NEW CHECK-IN COMES FIRST. Measured at 375x812 with
           four past check-ins: the form sat 2,224px down, 3.01 SCREENS of
           scroll, because history rendered above it. A crew member opens this
           screen to record today, not to read last Tuesday — and they open it
           standing on a roof.

           History stays fully visible underneath, not collapsed: reading what
           was logged yesterday is how you know what is left, and it costs no
           tap. Same call as the PO line editor — collapse the FORM you are not
           using, never the FACTS you came to read; here the form IS what they
           came for, so it is the history that moves down. */
        <div className="flex flex-col gap-4">
          {/* U-W1.42 — MOUNTED. Held on 2026-09-23 and 09-25 because the log did
              not exist; S landed 20260929025035 and the hold is released. The
              seven codes were verified against the APPLIED CHECK constraint
              before this was wired: 7 of 7, same strings, same order. */}
          <SpecialTripPanel orgId={params.orgId} workOrderId={workOrder.id} action={recordSpecialTrip} />

          {/* §2.6 — what a crew can record, a crew can remove. A trip is a
              COUNTED thing, so a mis-tap nobody can undo becomes a number
              somebody defends in a meeting later. */}
          {trips.length > 0 && (
            <div className="flex flex-col gap-2">
              <p className="text-sm font-semibold uppercase tracking-wide text-muted group-data-[outdoor=true]/field:text-white/80">
                Special trips on this job · {trips.length}
              </p>
              {trips.map((trip) => (
                <div
                  key={trip.id}
                  data-special-trip={trip.reason_code}
                  className="flex flex-wrap items-center justify-between gap-2 rounded-lg border border-border p-3 group-data-[outdoor=true]/field:border-white/40"
                >
                  <div className="min-w-0">
                    <p className="text-base font-medium text-text group-data-[outdoor=true]/field:text-white">
                      {specialTripReason(trip.reason_code)?.label ?? "Reason not recognised"}
                    </p>
                    <p className="font-mono text-sm text-muted group-data-[outdoor=true]/field:text-white/80">
                      {trip.occurred_on}
                    </p>
                  </div>
                  <ActionForm
                    action={deleteSpecialTrip}
                    label="Remove"
                    pendingLabel="Removing…"
                    buttonClassName="min-h-14 rounded-lg border border-border px-3 text-sm font-medium text-text group-data-[outdoor=true]/field:border-white/60 group-data-[outdoor=true]/field:text-white"
                  >
                    <input type="hidden" name="orgId" value={params.orgId} />
                    <input type="hidden" name="workOrderId" value={workOrder.id} />
                    <input type="hidden" name="specialTripId" value={trip.id} />
                  </ActionForm>
                </div>
              ))}
            </div>
          )}

          {/* 2026-09-21 — OFF RENDERS NOTHING. A screen says what the person can
              do; when the checklist does not exist here it has nothing to offer, so
              the section is absent rather than explaining a feature flag. */}
          {qc && qc.state !== "not_enabled" && (
            <QcPanel
              orgId={params.orgId}
              workOrderId={workOrder.id}
              trade={workOrder.trade}
              read={qc}
              photoRefs={photoRefs}
              latestCheckInId={checkIns[0]?.id ?? null}
              result={isQcResult(searchParams.qc) ? searchParams.qc : null}
            />
          )}
          <AddCheckInForm
            orgId={params.orgId}
            workOrderId={workOrder.id}
            defaultCrewName={lastCrewName}
            checkInCount={checkIns.length}
          />
          {checkIns.length > 0 && (
            <p className="text-sm font-semibold uppercase tracking-wide text-muted group-data-[outdoor=true]/field:text-white/80">
              Earlier check-ins · {checkIns.length}
            </p>
          )}
          {checkIns.map((checkIn) => (
            <CheckInRow
              key={checkIn.id}
              orgId={params.orgId}
              workOrderId={workOrder.id}
              checkIn={checkIn}
            />
          ))}
        </div>
      )}

      {tab === "materials" &&
        (materials ? (
          <MaterialsList items={materials} todayIso={todayInNewYork()} />
        ) : (
          <p className="text-base text-[var(--warn-strong)] group-data-[outdoor=true]/field:text-white">
            The material list could not be read just now. That is not the same as there being none — pull to
            reload.
          </p>
        ))}

      {/* X-W1.15 (A4.7) — roof data and photos from the office, view only. */}
      {tab === "packet" && (
        <WorkOrderFiles
          orgId={params.orgId}
          workOrderId={workOrder.id}
          canManage={false}
          /* U-W1.48 — the crew set, not the whole map: a hand-typed URL must not
             put a sentence about uploading on a screen with no upload. */
          state={isFilesStateFor("field", searchParams.files) ? searchParams.files : null}
          outdoor
          surface="field"
        />
      )}

      {tab === "packet" && packet && (
        <ProductionPacketView
          orgId={params.orgId}
          workOrderId={workOrder.id}
          jobTitle={jobTitle}
          siteAddress={siteAddress}
          squares={header?.squares ?? null}
          pitch={header?.pitch ?? null}
          photos={allPhotos}
          packet={packet}
        />
      )}
    </FieldShell>
  );
}
