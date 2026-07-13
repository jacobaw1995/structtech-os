import Link from "next/link";
import {
  updateEstimateContact,
  voidEstimate,
  deleteEstimate,
} from "@/lib/estimating/actions";
import { estimateStatusLabel, estimateStatusClasses } from "@/lib/estimating/status";
import type { Database } from "@/lib/supabase/database.types";

type Estimate = Database["public"]["Tables"]["estimates"]["Row"];

// Contact fields are copied from the deal by create_estimate_from_deal
// (SCOPE.md "no re-entry") but stay editable here for the typo/correction
// case — update_estimate_contact() is deliberately separate from
// update_estimate_details() (step 2) so fixing a phone number can never
// accidentally advance preliminary -> validated. squares/pitch/site_address
// are new fields the deal never captured — they start blank and get filled
// in step 2 on-roof, not here.
//
// Delete is only offered before a signature can exist (status !== 'signed')
// — delete_estimate() itself guards on signatures/work_orders existing and
// is the real enforcement; this is just the same rule surfaced client-side
// so the button isn't there to click in the first place. Void has no such
// restriction: voiding a signed-then-cancelled job is the case that needs
// to keep working at any status.
export function StepPreliminary({
  orgId,
  estimate,
}: {
  orgId: string;
  estimate: Estimate;
}) {
  const isVoid = estimate.status === "void";
  const canDelete = estimate.status !== "signed" && !isVoid;

  return (
    <div className="flex flex-col gap-4 rounded-2xl border-2 border-border bg-surface p-4 group-data-[outdoor=true]/flow:border-white group-data-[outdoor=true]/flow:bg-black">
      <div className="flex items-start justify-between gap-2">
        <p className="text-xs uppercase tracking-wide text-muted group-data-[outdoor=true]/flow:text-white/60">
          Preliminary estimate
        </p>
        {isVoid && (
          <span
            className={`rounded-full px-2 py-0.5 text-xs font-medium ${estimateStatusClasses(
              estimate.status
            )}`}
          >
            {estimateStatusLabel(estimate.status)}
          </span>
        )}
      </div>

      <div>
        <p className="text-lg font-semibold text-text group-data-[outdoor=true]/flow:text-white">
          {estimate.company || estimate.contact_name || "Untitled"}
        </p>
        {estimate.company && estimate.contact_name && (
          <p className="text-sm text-muted group-data-[outdoor=true]/flow:text-white/70">
            {estimate.contact_name}
          </p>
        )}
      </div>

      <div className="flex flex-col gap-1 font-mono text-sm text-text group-data-[outdoor=true]/flow:text-white">
        {estimate.phone && <span>{estimate.phone}</span>}
        {estimate.email && <span>{estimate.email}</span>}
      </div>

      <p className="text-xs text-muted group-data-[outdoor=true]/flow:text-white/60">
        No measurements yet — squares, pitch, and site address get entered
        on-site in the next step.
      </p>

      <details className="rounded-lg border border-border group-data-[outdoor=true]/flow:border-white/30">
        <summary className="cursor-pointer select-none px-3 py-2 text-sm font-medium text-text group-data-[outdoor=true]/flow:text-white">
          Edit contact details
        </summary>
        <form
          action={updateEstimateContact}
          className="flex flex-col gap-2 border-t border-border p-3 group-data-[outdoor=true]/flow:border-white/30"
        >
          <input type="hidden" name="orgId" value={orgId} />
          <input type="hidden" name="estimateId" value={estimate.id} />
          <label className="flex flex-col gap-1 text-xs">
            <span className="text-muted group-data-[outdoor=true]/flow:text-white/70">
              Contact name
            </span>
            <input
              name="contact_name"
              defaultValue={estimate.contact_name ?? ""}
              className="rounded-md border border-border bg-bg px-2 py-1.5 text-sm text-text outline-none focus:border-accent group-data-[outdoor=true]/flow:border-white/40 group-data-[outdoor=true]/flow:bg-black group-data-[outdoor=true]/flow:text-white"
            />
          </label>
          <label className="flex flex-col gap-1 text-xs">
            <span className="text-muted group-data-[outdoor=true]/flow:text-white/70">
              Company
            </span>
            <input
              name="company"
              defaultValue={estimate.company ?? ""}
              className="rounded-md border border-border bg-bg px-2 py-1.5 text-sm text-text outline-none focus:border-accent group-data-[outdoor=true]/flow:border-white/40 group-data-[outdoor=true]/flow:bg-black group-data-[outdoor=true]/flow:text-white"
            />
          </label>
          <label className="flex flex-col gap-1 text-xs">
            <span className="text-muted group-data-[outdoor=true]/flow:text-white/70">
              Phone
            </span>
            <input
              name="phone"
              defaultValue={estimate.phone ?? ""}
              className="rounded-md border border-border bg-bg px-2 py-1.5 text-sm text-text outline-none focus:border-accent group-data-[outdoor=true]/flow:border-white/40 group-data-[outdoor=true]/flow:bg-black group-data-[outdoor=true]/flow:text-white"
            />
          </label>
          <label className="flex flex-col gap-1 text-xs">
            <span className="text-muted group-data-[outdoor=true]/flow:text-white/70">
              Email
            </span>
            <input
              name="email"
              defaultValue={estimate.email ?? ""}
              className="rounded-md border border-border bg-bg px-2 py-1.5 text-sm text-text outline-none focus:border-accent group-data-[outdoor=true]/flow:border-white/40 group-data-[outdoor=true]/flow:bg-black group-data-[outdoor=true]/flow:text-white"
            />
          </label>
          <button
            type="submit"
            className="mt-1 self-end rounded-md bg-accent-strong px-3 py-1.5 text-xs font-medium text-white"
          >
            Save
          </button>
        </form>
      </details>

      <Link
        href={`/w/${orgId}/estimating/${estimate.id}?step=2`}
        className="flex min-h-14 items-center justify-center rounded-lg bg-accent-strong text-base font-medium text-white"
      >
        Start on-site visit
      </Link>

      <div className="mt-auto flex gap-2 border-t border-border pt-3 group-data-[outdoor=true]/flow:border-white/30">
        {!isVoid && (
          <form action={voidEstimate} className="flex-1">
            <input type="hidden" name="orgId" value={orgId} />
            <input type="hidden" name="estimateId" value={estimate.id} />
            <button
              type="submit"
              className="w-full rounded-lg border border-warn px-3 py-2 text-xs font-medium text-warn"
            >
              Void estimate
            </button>
          </form>
        )}
        {canDelete && (
          <form action={deleteEstimate} className="flex-1">
            <input type="hidden" name="orgId" value={orgId} />
            <input type="hidden" name="estimateId" value={estimate.id} />
            <button
              type="submit"
              className="w-full rounded-lg border border-warn px-3 py-2 text-xs font-medium text-warn"
            >
              Delete estimate
            </button>
          </form>
        )}
      </div>
    </div>
  );
}
