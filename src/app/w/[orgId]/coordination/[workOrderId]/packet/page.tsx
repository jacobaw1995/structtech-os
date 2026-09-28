import Link from "next/link";
import { redirect } from "next/navigation";
import { requireModuleAccess } from "@/lib/workspace/context";
import { ProductionPacketView } from "@/components/field/ProductionPacketView";
import { FIELD_ERROR_COPY, isFieldError } from "@/lib/field/field-errors";
import type { Database } from "@/lib/supabase/database.types";

type WorkOrder = Database["public"]["Tables"]["work_orders"]["Row"];
type ProductionPacket = Database["public"]["Tables"]["production_packets"]["Row"];

// THE OFFICE CAN BUILD A PRODUCTION PACKET. Track U, U-W1.36, 2026-09-27.
//
// D8, golden path run 1 — THE DEFECT THAT STOPPED THE RUN. Every piece of this
// existed except the way in: production_packets with a callouts jsonb, four
// RPCs, a parser, a numbered display, an add form and a two-tap delete — all of
// it reachable ONLY from /w/<org>/field/<work order>?tab=packet. A crew screen.
// The office, who are the people that would actually build a packet before a
// crew arrives, had no route to one, and `production_packets` held 0 rows in
// the whole database. The data layer was never the gap. The door was.
//
// NOTHING HERE IS A SECOND COPY. The view, the actions and the RPCs are the
// ones the crew already uses; this page supplies the route, the coordination
// module guard, and a `returnTo` so a save comes back here instead of bouncing
// an office member off a module they do not have (see returnHref in
// lib/field/actions.ts).
//
// TRADE ONLY, and said rather than hidden: a packet attaches to a trade work
// order — assert_work_order_level('trade') refuses the master inside every one
// of those RPCs. A master gets a sentence and a link to its trades, not a
// disabled page (SCOPE §2.8).
export default async function OfficePacketPage({
  params,
  searchParams,
}: {
  params: { orgId: string; workOrderId: string };
  searchParams: { error?: string };
}) {
  const ctx = await requireModuleAccess(params.orgId, "coordination");
  const supabase = ctx.supabase;
  const backHref = `/w/${params.orgId}/coordination/${params.workOrderId}`;

  const { data: fetchedWorkOrder } = await supabase.rpc("fetch_work_order", {
    p_work_order_id: params.workOrderId,
  });
  const workOrder = fetchedWorkOrder?.[0] as WorkOrder | undefined;
  if (!workOrder || workOrder.org_id !== params.orgId) {
    redirect(`/w/${params.orgId}/coordination`);
  }

  const header = (
    <div className="flex flex-col gap-1">
      <Link href={backHref} className="text-sm text-muted hover:text-text">
        ← Back to the work order
      </Link>
      <h1 className="text-xl font-semibold text-text">Production packet</h1>
    </div>
  );

  if (workOrder.kind !== "trade") {
    return (
      <div className="flex flex-col gap-4 p-4 sm:p-6">
        {header}
        <p className="rounded-md border border-border px-4 py-3 text-sm text-text">
          A packet belongs to one trade, not to the whole job — open the trade the crew will be doing and
          build its packet there.
        </p>
      </div>
    );
  }

  // get_or_create is idempotent (migration header note). Opening this page IS
  // the office asking for a packet, so creating it here is the intent, not a
  // side effect.
  const { data: packetId, error: createError } = await supabase.rpc("get_or_create_production_packet", {
    p_work_order_id: workOrder.id,
  });

  let packet: ProductionPacket | undefined;
  if (!createError && packetId) {
    const { data: fetched } = await supabase.rpc("fetch_production_packet", {
      p_production_packet_id: packetId as unknown as string,
    });
    packet = fetched?.[0] as ProductionPacket | undefined;
  }

  // The job's own facts, for the packet header. List query (rule 5); nothing
  // here is money.
  const { data: jobRows } = await supabase
    .from("jobs")
    .select("service_address_street, service_address_city, service_address_state, service_address_zip")
    .eq("id", workOrder.job_id ?? "")
    .eq("org_id", params.orgId);
  const job = (jobRows ?? [])[0];
  const siteAddress = job
    ? [job.service_address_street, job.service_address_city, job.service_address_state, job.service_address_zip]
        .filter((p): p is string => Boolean(p && p.trim()))
        .join(", ")
    : "";

  return (
    <div className="flex flex-col gap-4 p-4 sm:p-6">
      {header}

      {/* A code, looked up — never the URL's own text. */}
      {isFieldError(searchParams.error) && (
        <p role="alert" className="rounded-md bg-warn-soft px-3 py-2 text-sm text-text">
          {FIELD_ERROR_COPY[searchParams.error]}
        </p>
      )}

      {packet ? (
        <>
          <p className="text-sm text-muted">
            What the crew will see on this job. They can add to it from their phone; you can build it here
            before they arrive.
          </p>
          <ProductionPacketView
            orgId={params.orgId}
            workOrderId={workOrder.id}
            jobTitle={workOrder.trade || "This trade"}
            siteAddress={siteAddress || null}
            squares={null}
            pitch={null}
            // The crew's check-in photos are theirs to take; the office builds
            // the written packet. An empty gallery here is not a claim that the
            // crew has taken none — it is this page not reading them.
            photos={[]}
            packet={packet}
            returnTo={`/w/${params.orgId}/coordination/${workOrder.id}/packet`}
          />
        </>
      ) : (
        <p role="alert" className="rounded-md border border-border px-4 py-3 text-sm text-[var(--warn-strong)]">
          The packet couldn&apos;t be opened just now. That doesn&apos;t mean this job has none — reload, and
          tell us if it keeps happening.
        </p>
      )}
    </div>
  );
}
