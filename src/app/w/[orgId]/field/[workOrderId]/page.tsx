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

// No dollar values rendered anywhere below: `estimate` is fetched via the
// shared fetch_estimate RPC (which does return subtotal/presented_total —
// no RPC excludes them), but this file never destructures or passes those
// fields into JSX or a client component, so nothing $-shaped reaches the
// rendered HTML or the client bundle. See field/page.tsx's header comment
// for the belt-and-suspenders reasoning.
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
        <div className="flex flex-col gap-4">
          {checkIns.map((checkIn) => (
            <CheckInRow
              key={checkIn.id}
              orgId={params.orgId}
              workOrderId={workOrder.id}
              checkIn={checkIn}
            />
          ))}
          <AddCheckInForm
            orgId={params.orgId}
            workOrderId={workOrder.id}
            defaultCrewName={lastCrewName}
          />
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
