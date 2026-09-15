import {
  updateProductionPacketNotes,
  deleteProductionPacket,
} from "@/lib/field/actions";
import { AddCalloutForm } from "@/components/field/AddCalloutForm";
import { CalloutRow } from "@/components/field/CalloutRow";
import { parseCallouts } from "@/lib/field/callouts";
import { TwoTapDelete } from "@/components/field/TwoTapDelete";
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
          <p className="text-sm text-muted group-data-[outdoor=true]/field:text-white/80">
            {siteAddress}
          </p>
        )}
        {squares != null && (
          <p className="font-mono text-sm text-muted group-data-[outdoor=true]/field:text-white/80">
            {squares} sq{pitch ? ` · ${pitch} pitch` : ""}
          </p>
        )}
      </div>

      <div>
        <p className="mb-2 text-sm font-semibold uppercase tracking-wide text-muted group-data-[outdoor=true]/field:text-white/80">
          Photos
        </p>
        {photos.length === 0 ? (
          <p className="text-sm text-muted group-data-[outdoor=true]/field:text-white/80">
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
        <p className="text-sm font-semibold uppercase tracking-wide text-muted group-data-[outdoor=true]/field:text-white/80">
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
          className="flex min-h-14 items-center justify-center rounded-lg bg-accent-strong text-base font-medium text-white"
        >
          Save notes
        </button>
      </form>

      <div>
        <p className="mb-2 text-sm font-semibold uppercase tracking-wide text-muted group-data-[outdoor=true]/field:text-white/80">
          Custom detail callouts
        </p>
        {callouts.length === 0 && (
          <p className="mb-2 text-sm text-muted group-data-[outdoor=true]/field:text-white/80">
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
        {/* Was "— deferred (BACKLOG.md)": a build note, in 12px at 5.3:1 in
            outdoor mode, on a crew screen. Said plainly instead. */}
        <p className="mt-2 text-sm text-muted group-data-[outdoor=true]/field:text-white/80">
          This packet has no trim map or boot-vent layer yet.
        </p>
      </div>

      {/* U-W1.16 — Reset deletes the packet's notes and every callout. It was a
          48px button that did that on ONE tap, in text-warn at 4.1:1 on black. */}
      <TwoTapDelete
        action={deleteProductionPacket}
        fields={{ orgId, workOrderId, productionPacketId: packet.id }}
        label="Reset packet"
        question="Reset this packet? Its notes and every callout are deleted."
        confirmLabel="Reset"
      />
    </div>
  );
}
