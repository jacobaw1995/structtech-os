import Link from "next/link";
import { requireModuleAccess } from "@/lib/workspace/context";
import { parseCrmStages } from "@/lib/crm/stages";
import { DealCard } from "@/components/crm/DealCard";
import { DealPanel } from "@/components/crm/DealPanel";
import { AddDealForm } from "@/components/crm/AddDealForm";
import type { Database } from "@/lib/supabase/database.types";

// More specific than the [moduleKey] placeholder route one level up — Next
// resolves this static segment first, per that route's own comment.

type Deal = Database["public"]["Tables"]["deals"]["Row"];
type DealNote = Database["public"]["Tables"]["deal_notes"]["Row"];
type DealActivity = Database["public"]["Tables"]["deal_activity"]["Row"];
type FollowUp = Database["public"]["Tables"]["follow_ups"]["Row"];

export default async function CrmPage({
  params,
  searchParams,
}: {
  params: { orgId: string };
  searchParams: { deal?: string; new?: string; error?: string };
}) {
  const ctx = await requireModuleAccess(params.orgId, "crm");
  // Reuse the client requireModuleAccess already authenticated (its
  // getSession() already ran) — a fresh createClient() here has no session
  // loaded until getSession()/getUser() is called on THAT instance
  // (CLAUDE.md rule 1). That gap was the deal-panel bug: the deals LIST
  // query still returned rows for a staff caller via the is_staff()
  // bypass policy, masking that this second client had no session; fetch_deal
  // has no is_staff() path (my_org_ids() only), so it silently returned
  // nothing and the panel never rendered.
  const supabase = ctx.supabase;

  // List queries — fine direct per CLAUDE.md rule 5, RLS already scopes by
  // org, the explicit .eq(org_id) additionally pins this to the ACTIVE org
  // (a caller can belong to more than one org; RLS alone would return every
  // org's rows they're a member of, not just this workspace's).
  const [{ data: moduleRow }, { data: deals }] = await Promise.all([
    supabase
      .from("tenant_modules")
      .select("config")
      .eq("org_id", params.orgId)
      .eq("module_key", "crm"),
    supabase
      .from("deals")
      .select("*")
      .eq("org_id", params.orgId)
      .order("created_at", { ascending: true }),
  ]);

  const stages = parseCrmStages(moduleRow?.[0]?.config ?? null);
  const dealList = (deals ?? []) as Deal[];

  const byStage = new Map<string, Deal[]>();
  for (const stage of stages) byStage.set(stage.key, []);
  const unrecognized: Deal[] = [];
  for (const deal of dealList) {
    const bucket = byStage.get(deal.stage);
    if (bucket) {
      bucket.push(deal);
    } else {
      unrecognized.push(deal);
    }
  }

  let selectedDeal: Deal | null = null;
  let notes: DealNote[] = [];
  let activity: DealActivity[] = [];
  let nextFollowUp: FollowUp | null = null;

  if (searchParams.deal) {
    // Single-record fetch RPC (rule 4), not a direct .select().single().
    const { data: fetched } = await supabase.rpc("fetch_deal", {
      p_deal_id: searchParams.deal,
    });
    const candidate = fetched?.[0] as Deal | undefined;

    // fetch_deal only guarantees the caller is a member of the deal's org —
    // not that it's THIS org. Guard against viewing a foreign-org deal id
    // while the URL says we're in this workspace (possible if the caller
    // belongs to more than one org, e.g. the agency_admin case).
    if (candidate && candidate.org_id === params.orgId) {
      selectedDeal = candidate;

      const [{ data: notesData }, { data: activityData }, { data: followUpData }] =
        await Promise.all([
          supabase
            .from("deal_notes")
            .select("*")
            .eq("deal_id", candidate.id)
            .order("created_at", { ascending: false }),
          supabase
            .from("deal_activity")
            .select("*")
            .eq("deal_id", candidate.id)
            .order("created_at", { ascending: false }),
          supabase
            .from("follow_ups")
            .select("*")
            .eq("deal_id", candidate.id)
            .eq("status", "pending")
            .order("send_at", { ascending: true })
            .limit(1),
        ]);

      notes = (notesData ?? []) as DealNote[];
      activity = (activityData ?? []) as DealActivity[];
      nextFollowUp = (followUpData?.[0] ?? null) as FollowUp | null;
    }
  }

  const boardHref = `/w/${params.orgId}/crm`;
  const isAdding = searchParams.new === "1";

  return (
    <div className="flex h-full flex-col gap-4">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-semibold text-text">Pipeline</h1>
          <p className="text-sm text-muted">{ctx.active.org_name}</p>
        </div>
        <Link
          href={isAdding ? boardHref : `${boardHref}?new=1`}
          className="rounded-md bg-accent-strong px-3 py-1.5 text-sm font-medium text-white"
        >
          {isAdding ? "Cancel" : "+ Add deal"}
        </Link>
      </div>

      {isAdding && (
        <AddDealForm
          orgId={params.orgId}
          errorMessage={!selectedDeal ? searchParams.error : undefined}
        />
      )}

      {stages.length === 0 ? (
        <p className="text-sm text-muted">
          {ctx.active.org_name} has no CRM stage configuration yet — nothing to
          show.
        </p>
      ) : (
        <>
          {dealList.length === 0 && (
            <p className="text-sm text-muted">
              No deals yet — add the first one to start{" "}
              {ctx.active.org_name}&apos;s pipeline.
            </p>
          )}

          <div className="flex flex-1 gap-4 overflow-hidden">
            {/* min-w-0 is load-bearing: a flex child defaults to
                min-width:auto, which refuses to shrink below its content's
                intrinsic width — with 8 columns that pushed the panel
                sibling off-screen instead of letting this div scroll
                internally. This was the second bug: fetch_deal/org-guard
                were fine, the panel just rendered clipped past the
                viewport edge with no way to scroll to it. */}
            <div className="flex flex-1 min-w-0 gap-4 overflow-x-auto pb-2">
              {stages.map((stage) => {
                const stageDeals = byStage.get(stage.key) ?? [];
                return (
                  <div key={stage.key} className="flex w-64 shrink-0 flex-col gap-2">
                    <div className="flex items-center justify-between px-1">
                      <h2 className="text-sm font-semibold text-text">
                        {stage.label}
                      </h2>
                      <span className="font-mono text-xs text-muted">
                        {stageDeals.length}
                      </span>
                    </div>
                    <div className="flex flex-col gap-2">
                      {stageDeals.map((deal) => (
                        <DealCard
                          key={deal.id}
                          deal={deal}
                          href={`${boardHref}?deal=${deal.id}`}
                          selected={selectedDeal?.id === deal.id}
                          nextAction={stage.next_action}
                        />
                      ))}
                      {stageDeals.length === 0 && (
                        <div className="rounded-md border border-dashed border-border px-3 py-4 text-center text-xs text-muted">
                          Empty
                        </div>
                      )}
                    </div>
                  </div>
                );
              })}

              {unrecognized.length > 0 && (
                <div className="flex w-64 shrink-0 flex-col gap-2">
                  <h2 className="text-sm font-semibold text-warn">
                    Unrecognized stage
                  </h2>
                  <div className="flex flex-col gap-2">
                    {unrecognized.map((deal) => (
                      <DealCard
                        key={deal.id}
                        deal={deal}
                        href={`${boardHref}?deal=${deal.id}`}
                        selected={selectedDeal?.id === deal.id}
                        nextAction={null}
                      />
                    ))}
                  </div>
                </div>
              )}
            </div>

            {selectedDeal && (
              <DealPanel
                orgId={params.orgId}
                deal={selectedDeal}
                stages={stages}
                notes={notes}
                activity={activity}
                nextFollowUp={nextFollowUp}
                closeHref={boardHref}
                errorMessage={searchParams.error}
              />
            )}
          </div>
        </>
      )}
    </div>
  );
}
