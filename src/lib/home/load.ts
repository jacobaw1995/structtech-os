import type { WorkspaceContext } from "@/lib/workspace/context";
import type { ModuleKey } from "@/lib/workspace/modules";
import { parseCrmStages } from "@/lib/crm/stages";
import { todayInNewYork, type Caps, type Section } from "@/lib/home/model";
import {
  UNAVAILABLE,
  buildEstimates,
  buildJobs,
  buildMaterials,
  buildPipeline,
  buildSchedule,
  reachableOnly,
} from "@/lib/home/build";

// Server-only: takes the already-authenticated client from getWorkspaceContext
// (its getSession() has run — CLAUDE.md rule 1). Every read below is a LIST
// query (rule 5), pinned to the active org with .eq("org_id"). What each row
// MEANS is decided in ./build.ts, which is pure.
//
// NO MONEY, STRUCTURALLY: no select below names deals.value, estimates.subtotal,
// presented_total or tax_amount. There is nothing on this page to leak.
//
// WHICH GATE, AND WHERE IT WAS READ (live bodies, 2026-09-14):
//   pipeline  — deals carry RESTRICTIVE can_view_financials(org_id), whose body
//               is `select has_capability(p_org_id, 'view_financials')`. The
//               home screen calls the SAME function the policy calls, so the
//               section's visibility and the rows RLS returns cannot disagree.
//   estimates — PERMISSIVE needs has_capability('view_estimates') AND the
//               RESTRICTIVE needs view_financials. Both are read.
//   schedule, materials, jobs — org-scoped for every member. work_orders adds
//               RESTRICTIVE kind='trade' OR can_view_master_work_order, which
//               the jobs section reads and names (build.ts, §7.1).
//   ENTITLEMENT — active.entitled_modules comes from fetch_membership_context(),
//               i.e. tenant_modules. A section for a module the tenant does not
//               have is not rendered: "no estimates entered yet" on a tenant
//               that cannot enter estimates would be a false empty.
//
// "NEEDS YOU" GATES, from the RPC that resolves each item:
//   schedule conflict, unscheduled trade  — add/update_schedule_block: has_capability('schedule')
//   draft purchase order                  — update_purchase_order: has_capability('manage_purchasing')
//   signed estimate with no job           — create_job_from_estimate: membership only
//   material with no ready-by / orphaned  — update_material_item: membership (assert_work_order_level) only
//   unowned open deal                     — assign_deal_owner: a manager assigns, a rep may claim
//   overdue pending follow-up             — no single RPC; edit_leads is used and REPORTED as a choice
// and, on top of every one of them, the caller must be able to OPEN the page
// the item is resolved on (reachableOnly, in build.ts).

// U-W1.24 (2026-09-20) — WHAT WAS WITHHELD IS NOT A THING THE SCREEN SAYS.
//
// `hidden` used to live here: a list of sections the caller's capabilities
// refused, rendered at the foot of the page as "Estimates is not shown — your
// role does not have view_estimates." MEASURED BY A HUMAN on production, as
// the crew member: `view_master_work_order` and `view_estimates` were on a
// roofer's screen, verbatim. Those are our internal identifiers. He cannot act
// on them, and naming what he cannot see tells him the shape of a system he
// has no business seeing.
//
// THE RULE (Jacob, 2026-09-20): a screen says what the person CAN DO, not what
// the system withheld from them. If a section is not for this role, it is
// ABSENT — not present and explained. So the array, its type, the component
// that rendered it and the sentence it built are all gone rather than reworded:
// a politer sentence would still be a sentence about our permission model.
//
// It is worth being clear about what this cost, because it is not nothing. The
// note existed so an absence could not be read as an empty — "no estimates
// yet" on a screen that is not allowed to count estimates is a lie of a
// different kind. That case is still handled, but by NOT BUILDING the section
// at all rather than by explaining its absence, which is the same answer the
// person would get from a screen that simply does not have that job.
export type HomeData = {
  sections: Section[];
  today: string;
};

type Supabase = WorkspaceContext["supabase"];

/**
 * A READ THAT CAME BACK SHORT IS NOT A READ. PostgREST caps a response at the
 * project's max_rows (1000 by default) WITHOUT an error, so 1,200 deals would
 * arrive as 1,000 and every count on this page would be quietly wrong. Every
 * list select asks for the exact count, and a response whose rows do not match
 * it is treated as unreadable rather than as the whole.
 */
function whole<T>(res: { data: T[] | null; error: unknown; count: number | null }): res is {
  data: T[];
  error: null;
  count: number;
} {
  return !res.error && res.data !== null && res.count !== null && res.count === res.data.length;
}

async function cap(supabase: Supabase, orgId: string, key: keyof Caps | "view_master_work_order") {
  const { data, error } = await supabase.rpc("has_capability", {
    p_org_id: orgId,
    p_capability: key,
  });
  // A failed capability read is NO — the database's own closed default. The
  // section it gates is then hidden, never shown as empty.
  return !error && data === true;
}

export async function loadHome(ctx: WorkspaceContext): Promise<HomeData> {
  const { supabase, active, session } = ctx;
  const orgId = active.org_id;
  const today = todayInNewYork();
  const entitled = new Set<string>(active.entitled_modules ?? []);
  // Links follow the route guard (requireModuleAccess), so a link on this page
  // is never one that bounces the caller back here.
  const visible = new Set<ModuleKey>(ctx.visibleModules);
  const href = (module: ModuleKey, path = "") =>
    visible.has(module) ? `/w/${orgId}/${module}${path}` : null;
  const workOrderHref = (id: string) => href("coordination", `/${id}`) ?? href("field", `/${id}`);

  const [view_financials, view_estimates, schedule, manage_purchasing, edit_leads, viewMaster] =
    await Promise.all([
      cap(supabase, orgId, "view_financials"),
      cap(supabase, orgId, "view_estimates"),
      cap(supabase, orgId, "schedule"),
      cap(supabase, orgId, "manage_purchasing"),
      cap(supabase, orgId, "edit_leads"),
      cap(supabase, orgId, "view_master_work_order"),
    ]);
  const caps: Caps = { view_financials, view_estimates, schedule, manage_purchasing, edit_leads };

  const tasks: Promise<Section>[] = [];

  // U-W1.24 (2026-09-20) — GATED ON WHAT THIS PERSON CAN OPEN, NOT ON WHAT THE
  // ORG BOUGHT. This read `entitled.has("coordination") || entitled.has("field")`,
  // and the `|| entitled.has("field")` is the whole of yesterday's crew-screen
  // defect: a field member is entitled to `field`, so the OFFICE's three cards
  // — Schedule, Jobs, "Materials and purchasing" — were built and rendered for
  // a roofer, in the office's words, linking to a module the route guard would
  // bounce them out of. Entitlement is the ORG's; visibility is the PERSON's,
  // and this page is a person's.
  //
  // The field module has its own Today list, which is the crew's schedule in
  // the crew's words. This page does not need to build them a second one.
  if (visible.has("coordination")) {
    tasks.push(
      (async () => {
        const res = await supabase
          .from("schedule_blocks")
          .select("id, work_order_id, crew_name, start_date, end_date, ready_by_conflict, ready_by_conflict_reason", { count: "exact" })
          .eq("org_id", orgId)
          .order("start_date", { ascending: true });
        return whole(res) ? buildSchedule(res.data, today, caps, workOrderHref) : UNAVAILABLE("schedule", "Schedule");
      })(),
      (async () => {
        const [j, w, b] = await Promise.all([
          supabase.from("jobs").select("id", { count: "exact", head: true }).eq("org_id", orgId),
          supabase.from("work_orders").select("id, job_id, kind, voided_at", { count: "exact" }).eq("org_id", orgId),
          supabase.from("schedule_blocks").select("work_order_id", { count: "exact" }).eq("org_id", orgId),
        ]);
        if (j.error || j.count === null || !whole(w) || !whole(b)) return UNAVAILABLE("jobs", "Jobs");
        return buildJobs(j.count, w.data, b.data.map((r) => r.work_order_id), caps, viewMaster, href);
      })(),
      (async () => {
        const [m, p] = await Promise.all([
          supabase.from("material_items").select("id, ready_by, ready_by_source", { count: "exact" }).eq("org_id", orgId),
          supabase.from("purchase_orders").select("id, status, supplier_name", { count: "exact" }).eq("org_id", orgId),
        ]);
        if (!whole(m) || !whole(p)) return UNAVAILABLE("materials", "Materials and purchasing");
        return buildMaterials(m.data, p.data, caps, href);
      })()
    );
  }

  if (visible.has("estimating")) {
    if (view_estimates && view_financials) {
      tasks.push(
        (async () => {
          const [e, j] = await Promise.all([
            supabase.from("estimates").select("id, status, estimate_number, company, contact_name", { count: "exact" }).eq("org_id", orgId),
            supabase.from("jobs").select("estimate_id", { count: "exact" }).eq("org_id", orgId),
          ]);
          if (!whole(e) || !whole(j)) return UNAVAILABLE("estimates", "Estimates");
          return buildEstimates(e.data, j.data.map((r) => r.estimate_id), href);
        })()
      );
    }
    // NOT EXPLAINED WHEN ABSENT — see the note on `hidden` below.
  }

  if (visible.has("crm")) {
    if (view_financials) {
      tasks.push(
        (async () => {
          const [c, d, f] = await Promise.all([
            supabase.from("tenant_modules").select("config", { count: "exact" }).eq("org_id", orgId).eq("module_key", "crm"),
            supabase.from("deals").select("id, stage, owner_id", { count: "exact" }).eq("org_id", orgId).is("archived_at", null),
            supabase.from("follow_ups").select("id, send_at, status", { count: "exact" }).eq("org_id", orgId).eq("status", "pending"),
          ]);
          if (c.error || !whole(d) || !whole(f)) return UNAVAILABLE("pipeline", "Pipeline");
          const stages = parseCrmStages(c.data?.[0]?.config ?? null);
          return buildPipeline(stages, d.data, f.data, session.user.id, Date.now(), caps, href);
        })()
      );
    }
  }

  return { sections: reachableOnly(await Promise.all(tasks)), today };
}
