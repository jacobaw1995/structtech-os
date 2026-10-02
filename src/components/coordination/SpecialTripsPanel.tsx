import { SPECIAL_TRIP_REASONS, specialTripReason } from "@/lib/field/special-trip";
import { deleteSpecialTrip } from "@/lib/field/special-trip-actions";

// THE OFFICE VIEW OF SPECIAL TRIPS. Track U, U-W1.47, 2026-10-01.
//
// A4.2's remaining gap, verified before building: every reference to
// special_trips in src/ was on the FIELD surface — the job page, the panel and
// its action. Zero under coordination/. The crew could record a trip and
// nobody in the office could see it.
//
// A COUNT AND A LIST, NOT A SECOND RECORDING SURFACE. The office does not
// record trips; the crew does, standing on the roof, in two taps. What the
// office needs is the thing the log exists for, argued in
// lib/field/special-trip.ts's own header: "we made nine trips back for missing
// material last month" is a number somebody can act on; nine paragraphs in nine
// check-ins is not. So the count by reason comes FIRST and the list second.
//
// ONE VOCABULARY. The reason labels are the same SPECIAL_TRIP_REASONS the crew
// taps, and the delete is the same RPC the crew uses — not a second copy of
// either. Only the place to return to differs (see returnHref).
//
// DELETION IS OFFERED, NOT GATED (SCOPE §2.8). delete_special_trip refuses
// anyone who is not the author or the office, by name, and field-errors.ts
// already carries that sentence. Hiding the control would mean guessing the
// answer the database gives for certain.

export type OfficeTrip = {
  id: string;
  reason_code: string;
  occurred_on: string;
  note: string | null;
  recorded_by: string | null;
};

export function SpecialTripsPanel({
  orgId,
  workOrderId,
  trips,
  memberName,
}: {
  orgId: string;
  workOrderId: string;
  /**
   * null = THE LIST COULD NOT BE READ. Not an empty list, and never rendered as
   * one — a failed read says nothing about how many trips this job has had.
   */
  trips: OfficeTrip[] | null;
  memberName: (id: string | null) => string | null;
}) {
  const returnTo = `/w/${orgId}/coordination/${workOrderId}`;

  if (trips === null) {
    return (
      <div className="rounded-lg border border-border bg-surface p-3">
        <h2 className="mb-2 text-xs font-semibold uppercase tracking-wide text-muted">Special trips</h2>
        <p role="alert" className="text-sm text-[var(--warn-strong)]">
          The special trips couldn&apos;t be read just now, so this can&apos;t show how many there have been.
          That is not the same as there having been none — reload before you rely on it.
        </p>
      </div>
    );
  }

  // Only reasons that actually happened. A row of zeros would read as a
  // measured finding — "weather: 0" asserts somebody checked the weather — when
  // it is only the absence of a record.
  const counts = SPECIAL_TRIP_REASONS.map((r) => ({
    label: r.label,
    n: trips.filter((t) => t.reason_code === r.code).length,
  })).filter((c) => c.n > 0);

  return (
    <div className="rounded-lg border border-border bg-surface p-3">
      <h2 className="mb-2 text-xs font-semibold uppercase tracking-wide text-muted">Special trips</h2>

      {trips.length === 0 ? (
        <p className="py-2 text-sm text-muted">No special trips recorded on this job.</p>
      ) : (
        <>
          {/* THE NUMBER THE LOG EXISTS FOR, first. */}
          <p className="text-sm font-medium text-text">
            {trips.length} {trips.length === 1 ? "trip" : "trips"} back to this job
          </p>
          <p className="mb-2 text-xs text-muted">
            {counts.map((c) => `${c.label} · ${c.n}`).join("  ·  ")}
          </p>

          <ul className="divide-y divide-border">
            {trips.map((trip) => {
              const who = memberName(trip.recorded_by);
              return (
                <li
                  key={trip.id}
                  data-special-trip={trip.reason_code}
                  className="flex flex-wrap items-start justify-between gap-2 py-2"
                >
                  <div className="min-w-0">
                    <p className="text-sm font-medium text-text">
                      {specialTripReason(trip.reason_code)?.label ?? "Reason not recognised"}
                    </p>
                    <p className="text-xs text-muted">
                      <span className="font-mono tabular-nums">{trip.occurred_on}</span>
                      {/* A missing name is said, not guessed at. */}
                      {who ? ` · ${who}` : trip.recorded_by ? " · recorded by somebody not on this workspace now" : ""}
                    </p>
                    {trip.note && <p className="mt-0.5 text-xs text-muted">{trip.note}</p>}
                  </div>
                  <form action={deleteSpecialTrip}>
                    <input type="hidden" name="orgId" value={orgId} />
                    <input type="hidden" name="workOrderId" value={workOrderId} />
                    <input type="hidden" name="specialTripId" value={trip.id} />
                    <input type="hidden" name="returnTo" value={returnTo} />
                    <button
                      type="submit"
                      className="min-h-14 rounded-md px-3 text-xs text-muted hover:text-warn sm:min-h-0 sm:py-1"
                    >
                      Remove
                    </button>
                  </form>
                </li>
              );
            })}
          </ul>
        </>
      )}
    </div>
  );
}
