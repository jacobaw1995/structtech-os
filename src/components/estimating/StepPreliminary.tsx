import Link from "next/link";
import type { Database } from "@/lib/supabase/database.types";

type Estimate = Database["public"]["Tables"]["estimates"]["Row"];

// Read-only shell (SCOPE.md "no re-entry"): every field here is copied from
// the deal by create_estimate_from_deal, not re-typed. site_address/squares/
// pitch are new fields the deal never captured (see the Stage 3 migration
// header) — they start blank and get filled in step 2 on-roof, not here.
export function StepPreliminary({
  orgId,
  estimate,
}: {
  orgId: string;
  estimate: Estimate;
}) {
  return (
    <div className="flex flex-col gap-4 rounded-2xl border-2 border-border bg-surface p-4 group-data-[outdoor=true]/flow:border-white group-data-[outdoor=true]/flow:bg-black">
      <p className="text-xs uppercase tracking-wide text-muted group-data-[outdoor=true]/flow:text-white/60">
        Preliminary estimate
      </p>

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

      <Link
        href={`/w/${orgId}/estimating/${estimate.id}?step=2`}
        className="mt-auto flex min-h-14 items-center justify-center rounded-lg bg-accent-strong text-base font-medium text-white"
      >
        Start on-site visit
      </Link>
    </div>
  );
}
