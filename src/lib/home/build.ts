import type { ModuleKey } from "@/lib/workspace/modules";
import type { CrmStage } from "@/lib/crm/stages";
import {
  plural,
  stateOf,
  todayInNewYork,
  type AttentionItem,
  type Caps,
  type Section,
} from "@/lib/home/model";

// PURE: rows in, a Section out. No client, no session, no imports that reach
// next/headers — so the exact function the page runs can be run by a fixture
// against rows measured under a real member's RLS. The fetches, and the
// columns they select, are in ./load.ts.

export type Href = (module: ModuleKey, path?: string) => string | null;

export const UNAVAILABLE = (id: Section["id"], title: string): Section => ({
  id,
  title,
  state: "unavailable",
  onRecord: null,
  onRecordLabel: "",
  items: [],
  notes: [],
});

/**
 * AN ITEM ONLY "NEEDS YOU" IF YOU CAN ALSO GET TO WHERE IT IS RESOLVED.
 * The backend allowing the write is half of it; the other half is a route
 * guard that lets the caller open the page the write lives on. Telling a crew
 * member something needs them, with no way to reach it, is a task they cannot do.
 */
export function reachableOnly(sections: Section[]): Section[] {
  return sections.map((s) => ({
    ...s,
    items: s.items.map((i) => ({ ...i, needsYou: i.needsYou && i.href !== null })),
  }));
}

const is = (n: number, one: string, many: string) => (n === 1 ? one : many);

// ---------------------------------------------------------------- schedule

export type BlockRow = {
  id: string;
  work_order_id: string;
  crew_name: string | null;
  start_date: string;
  end_date: string;
  ready_by_conflict: boolean;
  ready_by_conflict_reason: string | null;
};

export function buildSchedule(
  blocks: BlockRow[],
  today: string,
  caps: Caps,
  workOrderHref: (id: string) => string | null
): Section {
  const current = blocks.filter((b) => b.end_date >= today);
  const onSiteToday = current.filter((b) => b.start_date <= today);
  const conflicts = current.filter((b) => b.ready_by_conflict);

  const items: AttentionItem[] = [];
  for (const b of conflicts) {
    items.push({
      key: `conflict-${b.id}`,
      // The reason is the database's own sentence, written when the block was
      // saved. Quoted, not paraphrased.
      text: `${b.crew_name || "A crew"} starts ${b.start_date} — ${
        b.ready_by_conflict_reason ?? "before its materials are ready"
      }`,
      href: workOrderHref(b.work_order_id),
      needsYou: caps.schedule,
    });
  }
  for (const b of onSiteToday) {
    items.push({
      key: `today-${b.id}`,
      text: `${b.crew_name || "A crew"} is on site today, through ${b.end_date}`,
      href: workOrderHref(b.work_order_id),
      needsYou: false,
    });
  }

  return {
    id: "schedule",
    title: "Schedule",
    state: stateOf(blocks.length, items.length),
    onRecord: blocks.length,
    onRecordLabel: plural(blocks.length, "schedule block"),
    items,
    notes:
      blocks.length > 0
        ? [
            `${onSiteToday.length} on site today · ${current.length - onSiteToday.length} upcoming · ${
              blocks.length - current.length
            } finished · ${conflicts.length} of ${plural(current.length, "unfinished block")} ${is(
              conflicts.length,
              "starts",
              "start"
            )} before ${is(conflicts.length, "its", "their")} materials are ready`,
          ]
        : [],
  };
}

// -------------------------------------------------------------------- jobs

export type WorkOrderRow = { id: string; job_id: string | null; kind: string; voided_at: string | null };

export function buildJobs(
  jobCount: number,
  workOrders: WorkOrderRow[],
  scheduledWorkOrderIds: string[],
  caps: Caps,
  viewMaster: boolean,
  href: Href
): Section {
  const live = workOrders.filter((w) => w.voided_at === null);
  const inFlight = new Set(live.map((w) => w.job_id).filter(Boolean)).size;
  const scheduled = new Set(scheduledWorkOrderIds);
  const trades = live.filter((w) => w.kind === "trade");
  const unscheduled = trades.filter((w) => !scheduled.has(w.id));

  const items: AttentionItem[] =
    unscheduled.length > 0
      ? [
          {
            key: "unscheduled",
            text: `${plural(unscheduled.length, "trade work order")} of ${trades.length} ${is(
              unscheduled.length,
              "has",
              "have"
            )} no schedule block`,
            href: href("coordination") ?? href("field"),
            needsYou: caps.schedule,
          },
        ]
      : [];

  // §7.1 — NEVER INFER "DOES NOT EXIST" FROM "CANNOT SEE". Without
  // view_master_work_order, RLS returns trades only, so a job whose only live
  // work order is its master would count as "not in flight". The sentence
  // names what was counted rather than passing a smaller number off as the whole.
  const counted = viewMaster ? "work order" : "trade work order";
  // A job count of zero gets no notes: "0 of 0 jobs" is arithmetic, not information.
  const notes = jobCount === 0 ? [] : [
    `${inFlight} of ${plural(jobCount, "job")} ${is(inFlight, "has", "have")} a ${counted} that is not void`,
    viewMaster
      ? `${plural(live.length, "work order")} not void · ${trades.length} trade`
      : `${plural(trades.length, "trade work order")} not void`,
  ];
  if (jobCount > 0 && !viewMaster) {
    notes.push("Master work orders are not counted here — your role does not have view_master_work_order.");
  }

  return {
    id: "jobs",
    title: "Jobs",
    state: stateOf(jobCount, items.length),
    onRecord: jobCount,
    onRecordLabel: plural(jobCount, "job"),
    items,
    notes,
  };
}

// --------------------------------------------------------------- materials

export type MaterialRow = { id: string; ready_by: string | null; ready_by_source: string | null };
export type PurchaseOrderRow = { id: string; status: string; supplier_name: string | null };

export function buildMaterials(
  mats: MaterialRow[],
  pos: PurchaseOrderRow[],
  caps: Caps,
  href: Href
): Section {
  const drafts = pos.filter((p) => p.status === "draft");
  const noDate = mats.filter((m) => m.ready_by === null);
  const orphaned = mats.filter((m) => m.ready_by_source === "orphaned");

  const items: AttentionItem[] = [];
  for (const p of drafts) {
    items.push({
      key: `po-${p.id}`,
      text: `Purchase order to ${p.supplier_name || "an unnamed supplier"} is still a draft — not sent`,
      href: href("coordination", `/po/${p.id}`),
      needsYou: caps.manage_purchasing,
    });
  }
  if (noDate.length > 0) {
    items.push({
      key: "no-ready-by",
      text: `${plural(noDate.length, "material item")} of ${mats.length} ${is(noDate.length, "has", "have")} no ready-by date`,
      href: href("coordination"),
      needsYou: true,
    });
  }
  if (orphaned.length > 0) {
    items.push({
      key: "orphaned",
      text: `${plural(orphaned.length, "material item")} of ${mats.length} lost the purchase order line ${is(
        orphaned.length,
        "its",
        "their"
      )} date came from`,
      href: href("coordination"),
      needsYou: true,
    });
  }

  const total = mats.length + pos.length;
  return {
    id: "materials",
    title: "Materials and purchasing",
    state: stateOf(total, items.length),
    onRecord: total,
    onRecordLabel: `${plural(mats.length, "material item")} · ${plural(pos.length, "purchase order")}`,
    items,
    notes:
      total > 0
        ? [
            `${drafts.length} of ${plural(pos.length, "purchase order")} in draft · ${noDate.length} of ${plural(
              mats.length,
              "material item"
            )} without a ready-by date`,
          ]
        : [],
  };
}

// --------------------------------------------------------------- estimates

export type EstimateRow = {
  id: string;
  status: string;
  estimate_number: string | null;
  company: string | null;
  contact_name: string | null;
};

export function buildEstimates(ests: EstimateRow[], jobEstimateIds: (string | null)[], href: Href): Section {
  const withJob = new Set(jobEstimateIds.filter(Boolean));
  const by = (s: string) => ests.filter((e) => e.status === s);
  const presented = by("presented");
  const drafts = by("draft");
  const signed = by("signed");
  const signedNoJob = signed.filter((e) => !withJob.has(e.id));
  const name = (e: EstimateRow) =>
    e.company || e.contact_name || (e.estimate_number ? `Estimate ${e.estimate_number}` : "An estimate");

  const items: AttentionItem[] = [
    ...presented.map((e) => ({
      key: `presented-${e.id}`,
      text: `${name(e)} — presented, not signed`,
      href: href("estimating", `/${e.id}`),
      needsYou: true,
    })),
    ...signedNoJob.map((e) => ({
      key: `nojob-${e.id}`,
      text: `${name(e)} — signed, no job created from it`,
      href: href("coordination"),
      needsYou: true,
    })),
    ...drafts.map((e) => ({
      key: `draft-${e.id}`,
      text: `${name(e)} — draft, not presented`,
      href: href("estimating", `/${e.id}`),
      needsYou: true,
    })),
  ];

  return {
    id: "estimates",
    title: "Estimates",
    state: stateOf(ests.length, items.length),
    onRecord: ests.length,
    onRecordLabel: plural(ests.length, "estimate"),
    items,
    notes:
      ests.length > 0
        ? [
            `${presented.length} of ${ests.length} awaiting signature · ${signed.length} signed (${signedNoJob.length} without a job) · ${drafts.length} draft · ${by("void").length} void`,
          ]
        : [],
  };
}

// ---------------------------------------------------------------- pipeline

export type DealRow = { id: string; stage: string; owner_id: string | null };
export type FollowUpRow = { id: string; send_at: string; status: string };

export function buildPipeline(
  stages: CrmStage[],
  deals: DealRow[],
  pendingFollowUps: FollowUpRow[],
  userId: string,
  now: number,
  caps: Caps,
  href: Href
): Section {
  const closed = new Set(stages.filter((s) => s.outcome !== null).map((s) => s.key));
  const labels = new Map(stages.map((s) => [s.key, s.label] as const));
  const open = deals.filter((d) => !closed.has(d.stage));
  const mine = open.filter((d) => d.owner_id === userId);
  const unowned = open.filter((d) => d.owner_id === null);
  // Compared as instants, not strings: PostgREST returns "+00:00", toISOString "Z".
  const overdue = pendingFollowUps
    .filter((f) => Date.parse(f.send_at) < now)
    .sort((a, b) => Date.parse(a.send_at) - Date.parse(b.send_at));

  const items: AttentionItem[] = [];
  if (unowned.length > 0) {
    items.push({
      key: "unowned",
      text: `${plural(unowned.length, "open deal")} of ${open.length} ${is(unowned.length, "has", "have")} no owner`,
      href: href("crm"),
      needsYou: true,
    });
  }
  if (overdue.length > 0) {
    items.push({
      key: "overdue-followups",
      // The fact, not a cause. Why they did not send is not knowable from here.
      text: `${plural(overdue.length, "follow-up email")} of ${pendingFollowUps.length} pending ${is(
        overdue.length,
        "was",
        "were"
      )} due to send and ${is(overdue.length, "has", "have")} not — the oldest was due ${todayInNewYork(
        new Date(overdue[0].send_at)
      )}`,
      href: href("crm"),
      needsYou: caps.edit_leads,
    });
  }

  const byStage = new Map<string, number>();
  for (const d of mine) byStage.set(d.stage, (byStage.get(d.stage) ?? 0) + 1);
  const spread = Array.from(byStage.entries())
    .sort((a, b) => b[1] - a[1])
    .map(([k, n]) => `${labels.get(k) ?? k} ${n}`)
    .join(" · ");

  return {
    id: "pipeline",
    title: "Pipeline",
    state: stateOf(deals.length, items.length),
    onRecord: deals.length,
    onRecordLabel: plural(deals.length, "deal"),
    items,
    notes:
      deals.length > 0
        ? [
            `${mine.length} of ${plural(open.length, "open deal")} ${is(mine.length, "is", "are")} yours${
              spread ? ` — ${spread}` : ""
            }`,
            `${plural(deals.length, "deal")} not archived · ${deals.length - open.length} won or lost`,
          ]
        : [],
  };
}
