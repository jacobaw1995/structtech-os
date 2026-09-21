import Link from "next/link";
import { requireModuleAccess } from "@/lib/workspace/context";
import { cookies } from "next/headers";
import { FieldShell } from "@/components/field/FieldShell";
import { OUTDOOR_COOKIE, parseOutdoorCookie } from "@/lib/field/outdoor";
import { scheduleBlockStatus } from "@/lib/field/today";
import { todayInNewYork } from "@/lib/home/model";
import { EmptyDay, type LastJob } from "@/components/field/EmptyDay";

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
  ready_by_conflict: boolean;
  ready_by_conflict_reason: string | null;
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
  // U-W1.16 — THE PROJECT'S DAY, NOT UTC'S. This read
  // `new Date().toISOString().slice(0, 10)`, which is the UTC date: from 8 PM
  // EDT onward a crew's "Today" asked fetch_field_jobs for TOMORROW, so a job
  // ending today dropped off the list that evening. CLAUDE.md's timezone rule,
  // on the one screen a crew opens first.
  const todayIso = todayInNewYork();

  // end_date >= today keeps this to in-progress + upcoming jobs; past jobs drop
  // off. Voided work orders are excluded inside the RPC — a cancelled job
  // should simply stop showing up for a crew to check into.
  //
  // U-W1.25 (2026-09-21) — A FAILED READ IS NOT AN EMPTY DAY. This read
  // destructured `data` only and dropped `error`, so a failed call and a day
  // with nothing on it rendered the SAME card: "No jobs scheduled". That is
  // "cannot see" rendered as "does not exist" on the first screen a crew opens.
  // Now three states, and the screen says which.
  const { data: jobsData, error: jobsError } = await supabase.rpc("fetch_field_jobs", {
    p_org_id: params.orgId,
    p_today: todayIso,
  });
  const jobs: FieldJob[] | null = jobsError || !Array.isArray(jobsData) ? null : (jobsData as unknown as FieldJob[]);

  // THE EMPTY DAY — measured 2026-09-21: of the last 30 days, this screen had
  // anything on it for THREE (2026-09-17 from 8:29 PM, when the org's only
  // schedule row was created, through 2026-09-19, when it ended). On the other
  // 27 a crew member opened the app and learned nothing. Nothing on the
  // schedule is the COMMON day, so the screen is designed for it.
  //
  // What is true and useful on that day, from reads a crew can actually make:
  // the job they were last on, and that they can still add to it. Checked
  // against the functions rather than assumed: create_check_in and
  // add_check_in_photo have no date or schedule check at all, so a late
  // check-in and a late photo on a finished job both land.
  //
  // WHY THIS READ MAY SAY NOTHING BUT MAY NEVER SAY "NONE". It is a direct
  // table read under the caller's own RLS, not a definer function. Measured as
  // the crew account on 2026-09-21 it saw 1 of 1 of the org's schedule rows —
  // but "saw every row today" is a measurement, not a guarantee. So an empty or
  // failed result renders NOTHING about the past: no "you have no past jobs",
  // no "nothing was ever scheduled". The section is simply absent.
  const lastJob = jobs && jobs.length === 0 ? await readLastJob(supabase, params.orgId, todayIso) : null;

  return (
    <FieldShell initialOutdoor={parseOutdoorCookie(cookies().get(OUTDOOR_COOKIE)?.value)}>
      <div>
        <p className="text-2xl font-bold text-text group-data-[outdoor=true]/field:text-white">
          Today
        </p>
        <p className="font-mono text-sm text-muted group-data-[outdoor=true]/field:text-white/80">
          {/* Parsed and printed in UTC on purpose: todayIso is already the New
              York calendar date, so no second timezone shift may touch it. */}
          {new Date(`${todayIso}T00:00:00Z`).toLocaleDateString("en-US", {
            weekday: "short",
            month: "short",
            day: "numeric",
            timeZone: "UTC",
          })}
        </p>
      </div>

      {jobs === null ? (
        /* COULD NOT READ. Said as that, and never as an empty day. */
        <div
          role="alert"
          className="flex flex-col gap-1 rounded-2xl border border-border p-4 group-data-[outdoor=true]/field:border-white/40"
        >
          <p className="text-base font-semibold text-[var(--warn-strong)] group-data-[outdoor=true]/field:text-white">
            Couldn&apos;t load the schedule
          </p>
          <p className="text-sm text-muted group-data-[outdoor=true]/field:text-white/80">
            That doesn&apos;t mean there&apos;s no work. Pull down to reload, or try again in a minute.
          </p>
        </div>
      ) : jobs.length === 0 ? (
        <EmptyDay orgId={params.orgId} lastJob={lastJob} />
      ) : (
        <div className="flex flex-col gap-3">
          {jobs.map((job) => {
            const jobTitle = job.job_title || "Untitled job";
            const status = scheduleBlockStatus(job.start_date, job.end_date, todayIso);
            const active = status.state === "active" && !job.ready_by_conflict;

            return (
              <Link
                key={job.schedule_block_id}
                href={`/w/${params.orgId}/field/${job.work_order_id}?tab=check-in`}
                // U-W1.4 — `opacity-70` removed from the inactive cards. Seen
                // in outdoor mode at 375px, dimming the content is the one
                // thing you must not do on a screen whose spec is "bright
                // sun": it took the address and crew line of every upcoming
                // job to a contrast a phone in daylight cannot hold. The
                // active job is still unmistakable — 2px accent border versus
                // 1.5px, plus the only Open job button on the screen — which
                // is emphasis by weight rather than by making everything else
                // harder to read.
                className={
                  active
                    ? "flex flex-col gap-3 rounded-2xl border-2 border-accent p-4"
                    : "flex flex-col gap-1 rounded-2xl border-[1.5px] border-border p-4 group-data-[outdoor=true]/field:border-white/40"
                }
              >
                <div>
                  <p className="text-base font-semibold text-text group-data-[outdoor=true]/field:text-white">
                    {jobTitle}
                  </p>
                  {/* 14px, not 12px, and white/80 rather than white/60 in
                      outdoor mode. The address is what a driver reads and
                      "Day 2 of 3" is what a crew checks; both were the
                      smallest, faintest text on a screen specified for
                      gloves and daylight. */}
                  {job.site_address && (
                    <p className="text-sm text-muted group-data-[outdoor=true]/field:text-white/80">
                      {job.site_address}
                    </p>
                  )}
                  <p className="font-mono text-sm text-muted group-data-[outdoor=true]/field:text-white/80">
                    {job.crew_name} · {status.label}
                  </p>
                </div>

                {job.ready_by_conflict && (
                  <p className="rounded-md bg-warn-soft px-2 py-1 text-xs text-text">
                    {job.ready_by_conflict_reason ?? "materials are not ready yet"}
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

/**
 * The most recent schedule row that ended before today, on a live trade job.
 * Returns null — never "none" — when the read fails or finds nothing: see the
 * note at the call site. Voided jobs are excluded, the same rule
 * fetch_field_jobs applies, so a cancelled job is never offered as "your last
 * job".
 */
async function readLastJob(
  supabase: Awaited<ReturnType<typeof requireModuleAccess>>["supabase"],
  orgId: string,
  todayIso: string
): Promise<LastJob | null> {
  const { data, error } = await supabase
    .from("schedule_blocks")
    .select(
      "work_order_id, crew_name, end_date, work_order:work_orders!inner(kind, voided_at, job:jobs(service_address_street, service_address_city, service_address_state, service_address_zip))"
    )
    .eq("org_id", orgId)
    .lt("end_date", todayIso)
    .eq("work_order.kind", "trade")
    .is("work_order.voided_at", null)
    .order("end_date", { ascending: false })
    .limit(1);
  const row = !error && data ? data[0] : undefined;
  if (!row) return null;

  const job = row.work_order?.job;
  const address = job
    ? [job.service_address_street, job.service_address_city, job.service_address_state, job.service_address_zip]
        .filter((p): p is string => Boolean(p && p.trim()))
        .join(", ")
    : "";

  const { data: checkIns, error: checkInError } = await supabase
    .from("check_ins")
    .select("check_in_date")
    .eq("work_order_id", row.work_order_id)
    .order("check_in_date", { ascending: false })
    .limit(1);

  return {
    workOrderId: row.work_order_id,
    endDate: row.end_date,
    crewName: row.crew_name,
    address,
    lastCheckIn: !checkInError && checkIns?.[0] ? checkIns[0].check_in_date : null,
  };
}
