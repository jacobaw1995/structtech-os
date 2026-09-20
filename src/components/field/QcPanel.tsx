import { clearQcItem, recordQcItem } from "@/lib/field/qc-actions";
import { QC_RESULT_COPY, qcLines, outstandingBlocking, type QcResult, type QcRow } from "@/lib/field/qc";
import { QcPhotoButton } from "@/components/field/QcPhotoButton";

// The QC checklist for one job. X-W1.20 (A4.3).
//
// EVERY REQUIREMENT IS A ROW, ALWAYS. One that does not apply to this trade says
// so in its own section; one that applies and is not done says THAT. A crew member
// never has to work out which kind of silence they are looking at.
//
// Nothing here blocks a check-in (SCOPE §2.8). Outstanding blocking items are said
// loudly at the top, and that is all.
const STATE_LABEL = {
  satisfied: "Done",
  photo_removed: "Photo removed — take it again",
  outstanding: "Not done yet",
  not_required: "Not required on this job",
} as const;

export function QcPanel({
  orgId,
  workOrderId,
  trade,
  enabled,
  rows,
  photoRefs,
  latestCheckInId,
  result,
}: {
  orgId: string;
  workOrderId: string;
  trade: string | null;
  enabled: boolean;
  rows: QcRow[];
  photoRefs: Set<string>;
  latestCheckInId: string | null;
  result: QcResult | null;
}) {
  const lines = qcLines(trade, rows, photoRefs);
  const applies = lines.filter((l) => l.state !== "not_required");
  const notRequired = lines.filter((l) => l.state === "not_required");
  const blocking = outstandingBlocking(lines);

  return (
    <section id="qc" data-qc-enabled={enabled} className="flex flex-col gap-3 rounded-lg border border-border p-3 group-data-[outdoor=true]/field:border-white/30">
      <p className="text-sm font-semibold uppercase tracking-wide text-muted group-data-[outdoor=true]/field:text-white/80">
        Required checks
      </p>

      {result && (
        <p
          role={QC_RESULT_COPY[result].tone === "warn" ? "alert" : "status"}
          data-qc-result={result}
          className={`rounded-md px-3 py-2 text-sm text-text ${QC_RESULT_COPY[result].tone === "warn" ? "bg-warn-soft" : "bg-accent-soft"}`}
        >
          {QC_RESULT_COPY[result].text}
        </p>
      )}

      {!enabled ? (
        <p data-qc-state="not_enabled" className="text-sm text-text group-data-[outdoor=true]/field:text-white">
          {QC_RESULT_COPY.not_enabled.text}
        </p>
      ) : (
        <>
          {blocking.length > 0 && (
            <p role="status" className="rounded-md bg-warn-soft px-3 py-2 text-sm text-text">
              {blocking.length === 1
                ? "1 required check still to do before you leave:"
                : `${blocking.length} required checks still to do before you leave:`}{" "}
              {blocking.map((l) => l.requirement.label).join(", ")}.
            </p>
          )}

          <ul className="flex flex-col gap-3">
            {applies.map(({ requirement, state, row }) => (
              <li key={requirement.key} data-qc-key={requirement.key} data-qc-state={state} className="flex flex-col gap-2 border-t border-border pt-3 first:border-t-0 first:pt-0 group-data-[outdoor=true]/field:border-white/20">
                <div className="flex items-baseline justify-between gap-2">
                  <span className="text-sm font-medium text-text group-data-[outdoor=true]/field:text-white">
                    {requirement.label}
                    {requirement.blocking && state !== "satisfied" ? " · required" : ""}
                  </span>
                  <span className={`text-xs ${state === "satisfied" ? "text-muted" : "text-warn"} group-data-[outdoor=true]/field:text-white/80`}>
                    {STATE_LABEL[state]}
                    {state === "satisfied" && requirement.kind === "count" && row?.count_value !== null && row?.count_value !== undefined
                      ? ` · ${row.count_value}`
                      : ""}
                  </span>
                </div>
                <p className="text-xs text-muted group-data-[outdoor=true]/field:text-white/70">{requirement.help}</p>

                {requirement.kind === "photo" && (
                  <>
                    <QcPhotoButton
                      orgId={orgId}
                      workOrderId={workOrderId}
                      checkInId={latestCheckInId}
                      requirementKey={requirement.key}
                      label={requirement.label.toLowerCase()}
                      retake={state === "satisfied"}
                    />
                    {!latestCheckInId && (
                      <p className="text-xs text-text group-data-[outdoor=true]/field:text-white">
                        {QC_RESULT_COPY.needs_check_in.text}
                      </p>
                    )}
                  </>
                )}

                {requirement.kind === "count" && (
                  <form action={recordQcItem} className="flex items-center gap-2">
                    <input type="hidden" name="orgId" value={orgId} />
                    <input type="hidden" name="workOrderId" value={workOrderId} />
                    <input type="hidden" name="requirementKey" value={requirement.key} />
                    <input
                      name="count_value"
                      inputMode="numeric"
                      pattern="[0-9]*"
                      defaultValue={row?.count_value ?? ""}
                      aria-label={`${requirement.label} count`}
                      className="min-h-14 w-28 rounded-md border border-border bg-bg px-3 text-base text-text"
                    />
                    <button type="submit" className="min-h-14 rounded-md bg-accent-strong px-4 text-sm font-medium text-white">
                      {state === "satisfied" ? "Update" : "Record"}
                    </button>
                  </form>
                )}

                {requirement.kind === "confirm" && state !== "satisfied" && (
                  <form action={recordQcItem}>
                    <input type="hidden" name="orgId" value={orgId} />
                    <input type="hidden" name="workOrderId" value={workOrderId} />
                    <input type="hidden" name="requirementKey" value={requirement.key} />
                    <button type="submit" className="min-h-14 w-full rounded-md bg-accent-strong px-4 text-sm font-medium text-white">
                      Confirm {requirement.label.toLowerCase()}
                    </button>
                  </form>
                )}

                {state === "satisfied" && (
                  <form action={clearQcItem}>
                    <input type="hidden" name="orgId" value={orgId} />
                    <input type="hidden" name="workOrderId" value={workOrderId} />
                    <input type="hidden" name="requirementKey" value={requirement.key} />
                    <button type="submit" className="min-h-11 text-xs text-muted underline group-data-[outdoor=true]/field:text-white/80">
                      Undo
                    </button>
                  </form>
                )}
              </li>
            ))}
          </ul>

          {notRequired.length > 0 && (
            <div className="border-t border-border pt-2 group-data-[outdoor=true]/field:border-white/20">
              <p className="text-xs text-muted group-data-[outdoor=true]/field:text-white/70">
                Not required on this job: {notRequired.map((l) => l.requirement.label).join(", ")}.
              </p>
            </div>
          )}
        </>
      )}
    </section>
  );
}
