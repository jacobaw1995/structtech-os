import Link from "next/link";
import { requireModuleAccess } from "@/lib/workspace/context";
import { createJobFromEstimate } from "@/lib/coordination/actions";
import type { Database } from "@/lib/supabase/database.types";

// More specific than the [moduleKey] placeholder route — see crm/page.tsx's
// comment for why Next resolves this static segment first.

// A1.6 — this index is a JOB list. Before A1.6 it listed every work_orders
// row flat, so a master and its trades rendered identically and side by
// side; per D1 the job is the container, so the job is the row and the work
// orders are reached by opening it.
type JobRow = Database["public"]["Tables"]["jobs"]["Row"] & {
  estimate: Pick<
    Database["public"]["Tables"]["estimates"]["Row"],
    "company" | "contact_name"
  > | null;
  work_orders: Pick<
    Database["public"]["Tables"]["work_orders"]["Row"],
    "id" | "kind" | "voided_at"
  >[];
};
type Estimate = Database["public"]["Tables"]["estimates"]["Row"];

// Same "structured, joined by commas, nothing to fall back to" shape as
// ProspectDataPanel's formatServiceAddress — a job's address is copied from
// the deal's structured columns by create_job_from_estimate, so there is no
// legacy free-text leg to fall back to here either.
function formatServiceAddress(job: JobRow): string {
  return [
    job.service_address_street,
    job.service_address_city,
    job.service_address_state,
    job.service_address_zip,
  ]
    .filter((part): part is string => Boolean(part && part.trim()))
    .join(", ");
}

export default async function CoordinationPage({
  params,
}: {
  params: { orgId: string };
}) {
  const ctx = await requireModuleAccess(params.orgId, "coordination");
  const supabase = ctx.supabase;

  // List queries — fine direct per CLAUDE.md rule 5. One row per job: the
  // embedded work_orders(...) resolves off work_orders.job_id, so the trade
  // count and the master's id come back with the job instead of costing a
  // round trip per row — and, structurally, a work order can only ever
  // appear nested inside its job, never as a sibling of one.
  const [{ data: jobs }, { data: signedEstimates }] = await Promise.all([
    supabase
      .from("jobs")
      .select(
        "*, estimate:estimates(company, contact_name), work_orders(id, kind, voided_at)"
      )
      .eq("org_id", params.orgId)
      .order("created_at", { ascending: false }),
    supabase
      .from("estimates")
      .select("*")
      .eq("org_id", params.orgId)
      .eq("status", "signed")
      .order("signed_at", { ascending: false }),
  ]);

  const jobList = (jobs ?? []) as JobRow[];

  // A1.6 — the strip's condition changed from "signed estimate with no WORK
  // ORDER" to "signed estimate with no JOB". They are not the same set: an
  // estimate can carry a job whose master was deleted (nothing deletes a
  // `jobs` row — see §1 carried debt), and under the old condition that
  // estimate reappeared here as "ready". Acting on it would have called
  // create_job_from_estimate, which find-or-creates on jobs.estimate_id and
  // would have handed back the existing masterless job.
  const jobbedEstimateIds = new Set(jobList.map((j) => j.estimate_id));
  const unjobbedSigned = ((signedEstimates ?? []) as Estimate[]).filter(
    (e) => !jobbedEstimateIds.has(e.id)
  );

  return (
    <div className="flex h-full flex-col gap-6">
      <div>
        <h1 className="text-2xl font-semibold text-text">Coordination</h1>
        <p className="text-sm text-muted">{ctx.active.org_name}</p>
      </div>

      {unjobbedSigned.length > 0 && (
        <div className="flex flex-col gap-2">
          <h2 className="text-xs font-semibold uppercase tracking-wide text-muted">
            Signed — ready for a job
          </h2>
          {unjobbedSigned.map((estimate) => (
            <form
              key={estimate.id}
              action={createJobFromEstimate}
              className="flex items-center justify-between gap-4 rounded-lg border border-border bg-surface px-4 py-3"
            >
              <input type="hidden" name="orgId" value={params.orgId} />
              <input type="hidden" name="estimateId" value={estimate.id} />
              <div>
                <p className="text-sm font-semibold text-text">
                  {estimate.company || estimate.contact_name || "Untitled"}
                </p>
                {estimate.site_address && (
                  <p className="text-xs text-muted">{estimate.site_address}</p>
                )}
              </div>
              <button
                type="submit"
                className="flex min-h-11 items-center justify-center rounded-lg bg-accent-strong px-4 text-sm font-medium text-white"
              >
                Create job →
              </button>
            </form>
          ))}
        </div>
      )}

      <div className="flex flex-col gap-2">
        <h2 className="text-xs font-semibold uppercase tracking-wide text-muted">
          Jobs
        </h2>
        {jobList.length === 0 ? (
          <div className="flex h-40 flex-col items-center justify-center gap-1 rounded-lg border border-border bg-surface text-center">
            <p className="text-sm font-semibold text-text">No jobs yet</p>
            <p className="text-xs text-muted">
              A job appears once a signed estimate is converted.
            </p>
          </div>
        ) : (
          <div className="flex flex-col gap-2">
            {jobList.map((job) => (
              <JobRowCard key={job.id} job={job} orgId={params.orgId} />
            ))}
          </div>
        )}
      </div>
    </div>
  );
}

function JobRowCard({ job, orgId }: { job: JobRow; orgId: string }) {
  const workOrders = job.work_orders ?? [];
  const master = workOrders.find((w) => w.kind === "master") ?? null;
  const trades = workOrders.filter((w) => w.kind === "trade");
  const liveTrades = trades.filter((t) => t.voided_at === null);
  const voidedTradeCount = trades.length - liveTrades.length;

  const address = formatServiceAddress(job);
  const client = job.estimate?.company || job.estimate?.contact_name || null;

  const body = (
    <>
      <div className="min-w-0">
        <p className="truncate text-sm font-semibold text-text">
          {address || client || "Untitled job"}
        </p>
        <p className="truncate text-xs text-muted">
          {address ? client ?? "No client on the estimate" : "No service address"}
        </p>
      </div>
      <div className="flex shrink-0 flex-col items-end">
        <span className="text-xs text-muted">
          {liveTrades.length === 0
            ? "No trades yet"
            : `${liveTrades.length} ${liveTrades.length === 1 ? "trade" : "trades"}`}
        </span>
        {voidedTradeCount > 0 && (
          <span className="text-xs text-muted">
            {voidedTradeCount} voided
          </span>
        )}
      </div>
    </>
  );

  // Opening the job means opening its master — A1.3a already made the master
  // page the job's hub (trade list, sign-off, roll-up), so there is no second
  // /jobs/[id] surface to keep in sync with it (decision, §10 2026-08-21).
  // A job with no master is reachable only through the deletion gap in §1's
  // carried debt; it renders as a non-link rather than as a dead link, and
  // says why, because SCOPE §2.8 forbids a control that silently does nothing.
  if (!master) {
    return (
      <div className="flex items-center justify-between gap-4 rounded-lg border border-border border-dashed bg-surface px-4 py-3">
        {body}
        <span className="shrink-0 text-xs text-warn">No master work order</span>
      </div>
    );
  }

  return (
    <Link
      href={`/w/${orgId}/coordination/${master.id}`}
      className="flex items-center justify-between gap-4 rounded-lg border border-border bg-surface px-4 py-3 hover:border-accent"
    >
      {body}
    </Link>
  );
}
