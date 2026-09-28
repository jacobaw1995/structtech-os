import { addProductionPacketCallout } from "@/lib/field/actions";
import { ROOF_PLACES } from "@/lib/field/roof-callouts";

// U-W1.36 (2026-09-27) — ONE PLACE VOCABULARY, RECONCILED WITH WHAT IS STORED.
//
// U-W1.35 built ROOF_PLACES on 2026-09-25 against a shape that did not exist
// yet. What DOES exist is this: production_packets.callouts jsonb, rows of
// `{ id, label, detail }`, written by add_production_packet_callout. Rather
// than ship a second vocabulary or ask for a migration, the places are offered
// HERE as suggestions for `label` — so "Valleys" is stored in the column that
// already exists, and parseRoofCallouts recognises it as a place on the way
// back out. One list, one store, no migration.
//
// A DATALIST, NOT A SELECT, ON PURPOSE (SCOPE §2.8: never block the user).
// Every callout ever written is free text, and a roof has details no list
// anticipates. The vocabulary guides; it does not refuse.
export function AddCalloutForm({
  orgId,
  workOrderId,
  productionPacketId,
  returnTo,
}: {
  orgId: string;
  workOrderId: string;
  productionPacketId: string;
  returnTo?: string;
}) {
  return (
    <form
      action={addProductionPacketCallout}
      className="flex flex-col gap-2 border-t border-border pt-2 group-data-[outdoor=true]/field:border-white/30"
    >
      <input type="hidden" name="orgId" value={orgId} />
      <input type="hidden" name="workOrderId" value={workOrderId} />
      <input type="hidden" name="productionPacketId" value={productionPacketId} />
      {returnTo && <input type="hidden" name="returnTo" value={returnTo} />}
      <datalist id="roof-places">
        {ROOF_PLACES.map((p) => (
          <option key={p.code} value={p.label} />
        ))}
      </datalist>
      <input
        name="label"
        required
        list="roof-places"
        placeholder="Where on the roof…"
        className="min-h-14 rounded-lg border border-border bg-bg px-3 text-base text-text outline-none focus:border-accent group-data-[outdoor=true]/field:border-white/40 group-data-[outdoor=true]/field:bg-black group-data-[outdoor=true]/field:text-white"
      />
      <input
        name="detail"
        placeholder="What goes there (optional)"
        className="min-h-14 rounded-lg border border-border bg-bg px-3 text-base text-text outline-none focus:border-accent group-data-[outdoor=true]/field:border-white/40 group-data-[outdoor=true]/field:bg-black group-data-[outdoor=true]/field:text-white"
      />
      <button
        type="submit"
        className="flex min-h-14 items-center justify-center rounded-lg bg-accent-strong text-base font-medium text-white"
      >
        + Add callout
      </button>
    </form>
  );
}
