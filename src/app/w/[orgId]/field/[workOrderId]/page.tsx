import { redirect } from "next/navigation";
import { requireModuleAccess } from "@/lib/workspace/context";
import { FieldShell } from "@/components/field/FieldShell";
import { CheckInRow } from "@/components/field/CheckInRow";
import { AddCheckInForm } from "@/components/field/AddCheckInForm";
import { ProductionPacketView } from "@/components/field/ProductionPacketView";
import type { Database } from "@/lib/supabase/database.types";

type WorkOrder = Database["public"]["Tables"]["work_orders"]["Row"];
type Estimate = Database["public"]["Tables"]["estimates"]["Row"];
type CheckIn = Database["public"]["Tables"]["check_ins"]["Row"];
type ProductionPacket = Database["public"]["Tables"]["production_packets"]["Row"];

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
  searchParams: { tab?: string; error?: string };
}) {
  const ctx = await requireModuleAccess(params.orgId, "field");
  const supabase = ctx.supabase;
  const tab = searchParams.tab === "packet" ? "packet" : "check-in";

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

  const [{ data: fetchedEstimate }, { data: checkInsData }] = await Promise.all([
    supabase.rpc("fetch_estimate", { p_estimate_id: workOrder.estimate_id }),
    supabase
      .from("check_ins")
      .select("*")
      .eq("work_order_id", workOrder.id)
      .order("check_in_date", { ascending: false })
      .order("created_at", { ascending: false }),
  ]);

  const estimate = fetchedEstimate?.[0] as Estimate | undefined;
  const checkIns = (checkInsData ?? []) as CheckIn[];
  const jobTitle = estimate?.company || estimate?.contact_name || "Job";
  const lastCrewName = checkIns[0]?.crew_name;

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

  return (
    <FieldShell
      backHref={`/w/${params.orgId}/field`}
      backLabel="← Today"
      tabs={[
        {
          label: "Check-in",
          href: `/w/${params.orgId}/field/${workOrder.id}?tab=check-in`,
          active: tab === "check-in",
        },
        {
          label: "Packet",
          href: `/w/${params.orgId}/field/${workOrder.id}?tab=packet`,
          active: tab === "packet",
        },
      ]}
    >
      <p className="text-lg font-bold text-text group-data-[outdoor=true]/field:text-white">
        {tab === "check-in" ? `Check-in · ${jobTitle}` : jobTitle}
      </p>

      {searchParams.error && (
        <p className="rounded-md bg-warn-soft px-3 py-2 text-sm text-text">
          {searchParams.error}
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
          <AddCheckInForm
            orgId={params.orgId}
            workOrderId={workOrder.id}
            defaultCrewName={lastCrewName}
          />
          {checkIns.length > 0 && (
            <p className="text-xs font-semibold uppercase tracking-wide text-muted group-data-[outdoor=true]/field:text-white/60">
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

      {tab === "packet" && packet && (
        <ProductionPacketView
          orgId={params.orgId}
          workOrderId={workOrder.id}
          jobTitle={jobTitle}
          siteAddress={estimate?.site_address ?? null}
          squares={estimate?.squares ?? null}
          pitch={estimate?.pitch ?? null}
          photos={allPhotos}
          packet={packet}
        />
      )}
    </FieldShell>
  );
}
