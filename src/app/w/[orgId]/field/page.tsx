import Link from "next/link";
import { requireModuleAccess } from "@/lib/workspace/context";
import { FieldShell } from "@/components/field/FieldShell";
import { scheduleBlockStatus } from "@/lib/field/today";

// More specific than the [moduleKey] placeholder route — see crm/page.tsx's
// comment for why Next resolves this static segment first.
//
// A1.5 — this page no longer reads `estimates` at all. It used to embed an
// explicit non-money column list through schedule_blocks; that was a promise
// the UI made, not a guarantee the database enforced, and a crew-role user
// could still have selected subtotal/presented_total directly. Constraint 7
// says no dollars in the field, enforced at RPC and RLS — so `estimates` is now
// closed to a crew-tier member by a RESTRICTIVE policy, and the non-money job
// header a crew actually needs comes from fetch_field_jobs(), a security-definer
// RPC whose select list contains no money column at all. Nothing $-shaped can
// reach this page even if someone later edits the JSX.
//
// fetch_field_jobs also returns TRADE work orders only, so a crew never sees a
// master here.

// Shape of fetch_field_jobs()'s jsonb. Declared here because a jsonb-returning
// RPC is `Json` to the generated types — the contract lives in the migration,
// and this is the one place that reads it. Note what is absent: there is no
// price, total or cost field to render, by construction.
type FieldJob = {
  schedule_block_id: string;
  work_order_id: string;
  crew_name: string | null;
  start_date: string;
  end_date: string;
  blocked: boolean;
  blocked_reason: string | null;
  job_title: string | null;
  site_address: string | null;
  squares: number | null;
  pitch: string | null;
};

export default async function FieldTodayPage({
  params,
}: {
  params: { orgId: string };
}) {
  const ctx = await requireModuleAccess(params.orgId, "field");
  const supabase = ctx.supabase;
  const todayIso = new Date().toISOString().slice(0, 10);

  // end_date >= today keeps this to in-progress + upcoming jobs; past jobs drop
  // off. Voided work orders are excluded inside the RPC — a cancelled job
  // should simply stop showing up for a crew to check into.
  const { data: jobsData } = await supabase.rpc("fetch_field_jobs", {
    p_org_id: params.orgId,
    p_today: todayIso,
  });
  const jobs = (jobsData ?? []) as unknown as FieldJob[];

  return (
    <FieldShell>
      <div>
        <p className="text-2xl font-bold text-text group-data-[outdoor=true]/field:text-white">
          Today
        </p>
        <p className="font-mono text-xs text-muted group-data-[outdoor=true]/field:text-white/60">
          {new Date(`${todayIso}T00:00:00`).toLocaleDateString("en-US", {
            weekday: "short",
            month: "short",
            day: "numeric",
          })}
        </p>
      </div>

      {jobs.length === 0 ? (
        <div className="flex h-40 flex-col items-center justify-center gap-1 rounded-2xl border border-border text-center group-data-[outdoor=true]/field:border-white/30">
          <p className="text-sm font-semibold text-text group-data-[outdoor=true]/field:text-white">
            No jobs scheduled
          </p>
          <p className="text-xs text-muted group-data-[outdoor=true]/field:text-white/60">
            Jobs appear here once coordination schedules a crew.
          </p>
        </div>
      ) : (
        <div className="flex flex-col gap-3">
          {jobs.map((job) => {
            const jobTitle = job.job_title || "Untitled job";
            const status = scheduleBlockStatus(job.start_date, job.end_date, todayIso);
            const active = status.state === "active" && !job.blocked;

            return (
              <Link
                key={job.schedule_block_id}
                href={`/w/${params.orgId}/field/${job.work_order_id}?tab=check-in`}
                className={
                  active
                    ? "flex flex-col gap-3 rounded-2xl border-2 border-accent p-4"
                    : "flex flex-col gap-1 rounded-2xl border-[1.5px] border-border p-4 opacity-70 group-data-[outdoor=true]/field:border-white/30"
                }
              >
                <div>
                  <p className="text-base font-semibold text-text group-data-[outdoor=true]/field:text-white">
                    {jobTitle}
                  </p>
                  {job.site_address && (
                    <p className="text-xs text-muted group-data-[outdoor=true]/field:text-white/60">
                      {job.site_address}
                    </p>
                  )}
                  <p className="font-mono text-xs text-muted group-data-[outdoor=true]/field:text-white/60">
                    {job.crew_name} · {status.label}
                  </p>
                </div>

                {job.blocked && (
                  <p className="rounded-md bg-warn-soft px-2 py-1 text-xs text-text">
                    {job.blocked_reason ?? "blocked on materials"}
                  </p>
                )}

                {active && (
                  <span className="flex min-h-14 items-center justify-center rounded-lg bg-accent-strong text-base font-semibold text-white">
                    Open job
                  </span>
                )}
              </Link>
            );
          })}
        </div>
      )}
    </FieldShell>
  );
}
