import { RESET_COPY, WEAK_REASON_COPY, type ResetState } from "@/lib/auth/reset-states";

// Renders one named reset state. The copy comes only from reset-states.ts, so a
// page cannot say something different about the same cause. `data-reset-state`
// is the contract a check reads — never the sentence, which will be reworded.
// `reasons` must already be filtered through weakReasons(); only fixed copy renders.
export function ResetStateBanner({ state, reasons = [] }: { state: ResetState; reasons?: string[] }) {
  const copy = RESET_COPY[state];
  return (
    <div
      role={copy.tone === "warn" ? "alert" : "status"}
      data-reset-state={state}
      className={`mt-4 rounded-md px-3 py-2 text-sm text-text ${copy.tone === "warn" ? "bg-warn-soft" : "bg-accent-soft"}`}
    >
      <p className="font-medium">{copy.title}</p>
      <p className="mt-1 text-muted">{copy.body}</p>
      {reasons.map((r) => (
        <p key={r} className="mt-1 text-muted">
          {WEAK_REASON_COPY[r]}
        </p>
      ))}
    </div>
  );
}
