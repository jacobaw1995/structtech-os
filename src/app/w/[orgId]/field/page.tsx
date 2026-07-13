import Link from "next/link";
import { requireModuleAccess } from "@/lib/workspace/context";
import { FieldShell } from "@/components/field/FieldShell";
import { scheduleBlockStatus } from "@/lib/field/today";
import type { Database } from "@/lib/supabase/database.types";

// More specific than the [moduleKey] placeholder route — see crm/page.tsx's
// comment for why Next resolves this static segment first.
//
// No dollar values queried: the embedded estimate select below is an
// explicit column list (contact_name/company/site_address/squares/pitch),
// never estimates(*) — subtotal/presented_total never leave the database
// for this role. requireModuleAccess already keeps a field-role user off
// crm/estimating/coordination entirely (modulesVisibleForRole); this page
// is the second, belt-and-suspenders guarantee that even the one module
// they DO see never surfaces a price.

type JobEstimate = {
  id: string;
  contact_name: string | null;
  company: string | null;
  site_address: string | null;
  squares: number | null;
  pitch: string | null;
};

type JobWorkOrder = {
  id: string;
  voided_at: string | null;
  estimate: JobEstimate | null;
};

type JobScheduleBlock = Database["public"]["Tables"]["schedule_blocks"]["Row"] & {
  work_order: JobWorkOrder | null;
};

export default async function FieldTodayPage({
  params,
}: {
  params: { orgId: string };
}) {
  const ctx = await requireModuleAccess(params.orgId, "field");
  const supabase = ctx.supabase;
  const todayIso = new Date().toISOString().slice(0, 10);

  // List query — fine direct per CLAUDE.md rule 5. end_date >= today keeps
  // this to in-progress + upcoming jobs; past jobs drop off the list.
  const { data: scheduleBlocks } = await supabase
    .from("schedule_blocks")
    .select(
      "*, work_order:work_orders(id, voided_at, estimate:estimates(id, contact_name, company, site_address, squares, pitch))"
    )
    .eq("org_id", params.orgId)
    .gte("end_date", todayIso)
    .order("start_date", { ascending: true })
    .limit(20);

  // Filtered here rather than via a PostgREST embedded-resource filter —
  // the result set is already capped at 20, and a cancelled job (voided
  // work order) should simply stop showing up for a crew to check into.
  const jobs = (
    (scheduleBlocks ?? []) as unknown as JobScheduleBlock[]
  ).filter((job) => !job.work_order?.voided_at);

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
            const workOrder = job.work_order;
            const estimate = workOrder?.estimate;
            const jobTitle = estimate?.company || estimate?.contact_name || "Untitled job";
            const status = scheduleBlockStatus(job.start_date, job.end_date, todayIso);
            const active = status.state === "active" && !job.blocked;

            if (!workOrder) return null;

            return (
              <Link
                key={job.id}
                href={`/w/${params.orgId}/field/${workOrder.id}?tab=check-in`}
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
                  {estimate?.site_address && (
                    <p className="text-xs text-muted group-data-[outdoor=true]/field:text-white/60">
                      {estimate.site_address}
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
