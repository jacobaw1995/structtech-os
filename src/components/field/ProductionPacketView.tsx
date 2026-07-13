import {
  updateProductionPacketNotes,
  deleteProductionPacket,
} from "@/lib/field/actions";
import { AddCalloutForm } from "@/components/field/AddCalloutForm";
import { CalloutRow } from "@/components/field/CalloutRow";
import { parseCallouts } from "@/lib/field/callouts";
import type { Database } from "@/lib/supabase/database.types";

type ProductionPacket = Database["public"]["Tables"]["production_packets"]["Row"];

// "Built from work order + sign-off photos" (wireframe 3a) — job details
// and photos are read-only here, pulled from the estimate/check-ins passed
// in, never re-keyed (SCOPE.md §6). Only notes + callouts are this
// component's own editable state (migration header note 2/3). Trim map /
// boot-vent placement layers are deferred — BACKLOG.md.
export function ProductionPacketView({
  orgId,
  workOrderId,
  jobTitle,
  siteAddress,
  squares,
  pitch,
  photos,
  packet,
}: {
  orgId: string;
  workOrderId: string;
  jobTitle: string;
  siteAddress: string | null;
  squares: number | null;
  pitch: string | null;
  photos: string[];
  packet: ProductionPacket;
}) {
  const callouts = parseCallouts(packet.callouts);

  return (
    <div className="flex flex-col gap-4">
      <div className="rounded-2xl border-2 border-border p-4 group-data-[outdoor=true]/field:border-white/30">
        <p className="text-lg font-semibold text-text group-data-[outdoor=true]/field:text-white">
          {jobTitle} — production packet
        </p>
        {siteAddress && (
          <p className="text-sm text-muted group-data-[outdoor=true]/field:text-white/60">
            {siteAddress}
          </p>
        )}
        {squares != null && (
          <p className="font-mono text-xs text-muted group-data-[outdoor=true]/field:text-white/60">
            {squares} sq{pitch ? ` · ${pitch} pitch` : ""}
          </p>
        )}
      </div>

      <div>
        <p className="mb-2 text-xs font-semibold uppercase tracking-wide text-muted group-data-[outdoor=true]/field:text-white/60">
          Photos
        </p>
        {photos.length === 0 ? (
          <p className="text-sm text-muted group-data-[outdoor=true]/field:text-white/60">
            No check-in photos yet.
          </p>
        ) : (
          <div className="grid grid-cols-3 gap-2">
            {photos.map((photo, i) => (
              // eslint-disable-next-line @next/next/no-img-element
              <img
                key={i}
                src={photo}
                alt=""
                className="aspect-square rounded-lg border border-border object-cover group-data-[outdoor=true]/field:border-white/30"
              />
            ))}
          </div>
        )}
      </div>

      <form
        action={updateProductionPacketNotes}
        className="flex flex-col gap-2 rounded-2xl border border-border p-4 group-data-[outdoor=true]/field:border-white/30"
      >
        <input type="hidden" name="orgId" value={orgId} />
        <input type="hidden" name="workOrderId" value={workOrderId} />
        <input type="hidden" name="productionPacketId" value={packet.id} />
        <p className="text-xs font-semibold uppercase tracking-wide text-muted group-data-[outdoor=true]/field:text-white/60">
          Notes
        </p>
        <textarea
          name="notes"
          defaultValue={packet.notes ?? ""}
          rows={2}
          placeholder="General packet notes…"
          className="min-h-14 rounded-lg border border-border bg-bg px-3 py-2 text-sm text-text outline-none focus:border-accent group-data-[outdoor=true]/field:border-white/40 group-data-[outdoor=true]/field:bg-black group-data-[outdoor=true]/field:text-white"
        />
        <button
          type="submit"
          className="flex min-h-12 items-center justify-center rounded-lg bg-accent-strong text-sm font-medium text-white"
        >
          Save notes
        </button>
      </form>

      <div>
        <p className="mb-2 text-xs font-semibold uppercase tracking-wide text-muted group-data-[outdoor=true]/field:text-white/60">
          Custom detail callouts
        </p>
        {callouts.length === 0 && (
          <p className="mb-2 text-sm text-muted group-data-[outdoor=true]/field:text-white/60">
            No callouts yet.
          </p>
        )}
        {callouts.map((callout, i) => (
          <CalloutRow
            key={callout.id}
            orgId={orgId}
            workOrderId={workOrderId}
            productionPacketId={packet.id}
            callout={callout}
            index={i}
          />
        ))}
        <AddCalloutForm orgId={orgId} workOrderId={workOrderId} productionPacketId={packet.id} />
        <p className="mt-2 font-mono text-xs text-muted group-data-[outdoor=true]/field:text-white/50">
          Trim map / boot-vent placement layer — deferred (BACKLOG.md).
        </p>
      </div>

      <form action={deleteProductionPacket}>
        <input type="hidden" name="orgId" value={orgId} />
        <input type="hidden" name="workOrderId" value={workOrderId} />
        <input type="hidden" name="productionPacketId" value={packet.id} />
        <button
          type="submit"
          className="flex min-h-12 items-center justify-center rounded-lg border border-warn text-sm font-medium text-warn"
        >
          Reset packet
        </button>
      </form>
    </div>
  );
}
