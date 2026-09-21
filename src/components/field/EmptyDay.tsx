import Link from "next/link";
import { formatDateOnly } from "@/lib/coordination/stage";

// THE EMPTY DAY. Track U, U-W1.25, 2026-09-21. Rendered by the field Today
// page when fetch_field_jobs answered and the answer was "nothing today or
// later" — never when the read failed (the page says that separately).
//
// Measured before it was built: of the last 30 days, the crew's Today screen
// showed anything on THREE. Nothing on the schedule is the common day, so it
// is the day this screen is designed for.

export type LastJob = {
  workOrderId: string;
  endDate: string;
  crewName: string | null;
  address: string;
  lastCheckIn: string | null;
};

export function EmptyDay({ orgId, lastJob }: { orgId: string; lastJob: LastJob | null }) {
  return (
        <div className="flex flex-col gap-3">
          {/* WHAT fetch_field_jobs CAN BACK, and no more. It is a definer
              function over this org's live trade jobs with a schedule row
              ending today or later, and the route guard has already made the
              caller a member — so an empty answer here IS "nothing on the
              schedule", not "nothing you can see". The sentence claims exactly
              that scope: today or later. It does not claim there is no work.

              U-W1.25 — the second line used to read "Jobs appear here once
              coordination schedules a crew." `coordination` is a module name
              standing in for a person. */}
          <div className="flex flex-col gap-1 rounded-2xl border border-border p-4 group-data-[outdoor=true]/field:border-white/40">
            <p className="text-base font-semibold text-text group-data-[outdoor=true]/field:text-white">
              Nothing on the schedule for today or later
            </p>
            <p className="text-sm text-muted group-data-[outdoor=true]/field:text-white/80">
              When a job is put on the schedule, it shows up here with its dates.
            </p>
          </div>

          {lastJob && (
            <Link
              href={`/w/${orgId}/field/${lastJob.workOrderId}?tab=check-in`}
              className="flex flex-col gap-3 rounded-2xl border-[1.5px] border-border p-4 group-data-[outdoor=true]/field:border-white/40"
            >
              <div>
                <p className="text-sm font-semibold uppercase tracking-wide text-muted group-data-[outdoor=true]/field:text-white/80">
                  Your last job
                </p>
                <p className="text-base font-semibold text-text group-data-[outdoor=true]/field:text-white">
                  {lastJob.address || "Job with no address recorded"}
                </p>
                <p className="font-mono text-sm text-muted group-data-[outdoor=true]/field:text-white/80">
                  Finished {formatDateOnly(lastJob.endDate)}
                  {lastJob.crewName ? ` · ${lastJob.crewName}` : ""}
                </p>
                {/* A POSITIVE claim only. When no check-in is visible nothing
                    is said, because an RLS read that returns none cannot
                    distinguish "none recorded" from "none visible to you". */}
                {lastJob.lastCheckIn && (
                  <p className="text-sm text-muted group-data-[outdoor=true]/field:text-white/80">
                    Last check-in {formatDateOnly(lastJob.lastCheckIn)}
                  </p>
                )}
                <p className="mt-1 text-sm text-text group-data-[outdoor=true]/field:text-white">
                  You can still add a check-in, hours or photos to it.
                </p>
              </div>
              <span className="flex min-h-14 items-center justify-center rounded-lg border border-border text-base font-semibold text-text group-data-[outdoor=true]/field:border-white group-data-[outdoor=true]/field:text-white">
                Open last job
              </span>
            </Link>
          )}
        </div>
  );
}
