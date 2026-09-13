import Link from "next/link";
import { getWorkspaceContext } from "@/lib/workspace/context";
import { CapabilityGrid, GridLegend } from "@/components/permissions/CapabilityGrid";
import { RoleReference } from "@/components/permissions/RoleReference";
import { MirrorRegistryPanel } from "@/components/permissions/MirrorRegistry";
import { MemberCapabilityEditor } from "@/components/permissions/MemberCapabilityEditor";
import {
  buildGrid,
  isManagerRole,
  CAPABILITIES,
  ENFORCEMENT,
  driftFromRoleDefault,
  grantedCountForRole,
  fetchRoleMatrix,
  capabilityDrift,
  type OrgMemberRow,
} from "@/lib/permissions/model";

// G3 · Capability admin surface — EDITABLE from 2026-09-12.
//
// It was read-only for eight days, and that was a finding rather than a
// shortcut: no function wrote org_members.permissions. Migration
// 20260911233218 added set_member_capability() and role_capability_matrix(),
// so the write now exists and this page offers it — per member, never on a
// manager-tier row, and with the role-change warning at the controls.
//
// NOT under requireModuleAccess(): permissions are not a module, they are org
// administration, and gating them on `estimating` or `crm` entitlement would be
// wrong in both directions. getWorkspaceContext() still runs — the org guard,
// the session and the redirect to /select-workspace all come from it.

export default async function PermissionsPage({
  params,
  searchParams,
}: {
  params: { orgId: string };
  searchParams: { edit?: string; error?: string };
}) {
  const ctx = await getWorkspaceContext(params.orgId);

  // Visibility gate, mirroring is_org_manager()'s role list. It is NOT the
  // security boundary: set_member_capability() itself refuses a non-manager
  // caller ("only an owner or admin can change what a member can do in this
  // workspace"), and RLS scopes every row this page reads. It is here so a crew member is not shown an
  // administration screen that has nothing to do with their job.
  //
  // SCOPE §2.8 is not engaged: §2.8 forbids blocking an action the user is
  // permitted to take because some OTHER data is incomplete. This hides a
  // screen the user is not permitted to administer, which is the same
  // distinction the catalog page draws for `manage_catalog`.
  const isManager = isManagerRole(ctx.active.role);

  // Direct list query, deliberately, and NOT list_org_members(). That RPC
  // exists but returns TABLE(user_id uuid, full_name text) — no role, no
  // permissions — so it cannot drive this grid. CLAUDE.md pattern 5 permits a
  // list query after getSession(); org_members carries the SELECT policy
  // "member read own members" scoped to my_org_ids(), so this is org-scoped by
  // RLS and not by the .eq() below alone.
  const { data: memberRows, error } = await ctx.supabase
    .from("org_members")
    .select("user_id, full_name, role, permissions, created_at")
    .eq("org_id", params.orgId)
    .order("role");

  const members = (memberRows ?? []) as Pick<
    OrgMemberRow,
    "user_id" | "full_name" | "role" | "permissions" | "created_at"
  >[];

  // ONE read of the matrix per request, passed to every component, so the grid,
  // the reference and the editors cannot answer from two different reads.
  const { matrix, error: matrixError } = await fetchRoleMatrix(ctx.supabase);

  // Members whose stored row is missing capabilities their role grants. Under
  // A2.0's closed default an absent key grants NOTHING, and A2.0b deliberately
  // left the hole open: "The residual case — a direct INSERT with permissions
  // '{}' — is left failing CLOSED". That case is live in production and it is
  // the first thing this page should tell you.
  //
  // 2026-09-08 — WIDENED, because a correct backfill by someone else silently
  // switched this alarm off.
  //
  // It used to key on `Object.keys(permissions).length === 0`. The
  // manage_purchasing backfill then wrote that one key into the very row this
  // alarm exists to report, taking it from zero keys to one — so the row was
  // still missing NINE capabilities, still denied almost everything, and no
  // longer matched the test. A monitor whose subject can be moved out of scope
  // by an unrelated migration is not a monitor.
  //
  // It now keys on MISSING KEYS, which is the thing that actually matters:
  // under A2.0's closed default an absent key grants nothing, so a row missing
  // any of them is under-provisioned whether it holds zero keys or nine.
  const underProvisioned = matrix
    ? members
        .map((m) => ({ m, drift: driftFromRoleDefault(matrix, m.role, m.permissions) }))
        .filter(({ m, drift }) => !isManagerRole(m.role) && drift.missing.length > 0)
    : [];

  const inert = CAPABILITIES.filter((c) => ENFORCEMENT[c].sites === 0);
  const capDrift = matrix ? capabilityDrift(matrix) : null;

  return (
    <div className="mx-auto flex w-full max-w-6xl flex-col gap-4">
      <Link
        href={`/w/${params.orgId}`}
        className="inline-flex min-h-11 items-center self-start text-sm text-muted hover:text-accent-strong sm:min-h-0"
      >
        ← {ctx.active.org_name}
      </Link>

      <div>
        <h1 className="text-2xl font-semibold text-text">Roles &amp; permissions</h1>
        <p className="text-sm text-muted">
          {ctx.active.org_name} · what each role can do, and what actually enforces it
        </p>
      </div>

      {!isManager ? (
        <p className="rounded-lg border border-border bg-surface px-4 py-3 text-sm text-muted">
          Roles and permissions are administered by an owner or admin of{" "}
          {ctx.active.org_name}. Ask one of them if something you need is closed to you.
        </p>
      ) : (
        <>
          {searchParams.error && (
            <p className="rounded-lg border border-warn bg-warn-soft px-4 py-3 text-sm text-text">
              {/* Verbatim from set_member_capability — Track S's wording names
                  the role and the reason, and a paraphrase would lose both. */}
              {searchParams.error}
            </p>
          )}

          {matrixError && (
            <p className="rounded-lg border border-warn bg-warn-soft px-4 py-3 text-sm text-text">
              Could not read the role matrix, so nothing below is drawn from a guess:{" "}
              {matrixError}
            </p>
          )}

          {capDrift &&
            (capDrift.inDatabaseNotInCensus.length > 0 ||
              capDrift.inCensusNotInDatabase.length > 0) && (
              <section className="rounded-lg border border-warn bg-warn-soft px-4 py-3">
                <h2 className="text-sm font-semibold text-text">
                  The capability list here has drifted from the database
                </h2>
                <p className="mt-1 text-xs leading-relaxed text-text">
                  {capDrift.inDatabaseNotInCensus.length > 0 && (
                    <>
                      In the database but not in this page&rsquo;s enforcement census:{" "}
                      <code>{capDrift.inDatabaseNotInCensus.join(", ")}</code>.{" "}
                    </>
                  )}
                  {capDrift.inCensusNotInDatabase.length > 0 && (
                    <>
                      In the census but no longer in the database:{" "}
                      <code>{capDrift.inCensusNotInDatabase.join(", ")}</code>.{" "}
                    </>
                  )}
                  Re-derive mirror C before trusting the enforcement counts.
                </p>
              </section>
            )}

          {error && (
            <p className="rounded-lg border border-warn bg-warn-soft px-4 py-3 text-sm text-text">
              Could not read members: {error.message}
            </p>
          )}

          {underProvisioned.length > 0 && (
            <section className="rounded-lg border border-warn bg-warn-soft px-4 py-3">
              <h2 className="text-sm font-semibold text-text">
                {underProvisioned.length} member
                {underProvisioned.length === 1 ? " is" : "s are"} missing capabilities
                their role grants
              </h2>
              <ul className="mt-2 space-y-1 text-sm text-text">
                {underProvisioned.map(({ m, drift }) => (
                  <li key={m.user_id}>
                    <span className="font-medium">{m.full_name ?? "Unnamed member"}</span>{" "}
                    <span className="text-muted">
                      · {m.role} · joined {formatDay(m.created_at)} ·{" "}
                      {drift.missing.length} of {CAPABILITIES.length} keys never written
                    </span>
                  </li>
                ))}
              </ul>
              <p className="mt-2 text-xs leading-relaxed text-muted">
                Their stored row never had these keys written. Since A2.0 the default
                is CLOSED — an absent key grants nothing — so they are denied every
                capability listed above, including ones their role would normally get.
                Nobody chose that: the row was written by a path that does not seed.
                It can be fixed from the member list below — granting or denying each
                key. This is the case A2.0b recorded as
                deliberately left &ldquo;failing closed&rdquo;. Note this is different
                from a key written as <code>false</code>, which is a decision someone
                made — the grid below draws that distinction per cell.
              </p>
            </section>
          )}

          {inert.length > 0 && (
            <section className="rounded-lg border border-border bg-surface px-4 py-3">
              <h2 className="text-sm font-semibold text-text">
                {inert.length} of {CAPABILITIES.length} capabilities are not enforced by anything
              </h2>
              <p className="mt-1 text-sm leading-relaxed text-text">
                {inert.map((c, i) => (
                  <span key={c}>
                    {i > 0 && ", "}
                    <code>{c}</code>
                  </span>
                ))}{" "}
                are derived onto every member row and
                then read by no RPC, no policy and no page. Turning one on or off would change
                nothing anyone can observe. They are shown on the grid so that the list of
                capabilities matches the database rather than a tidier version of it.
              </p>
            </section>
          )}

          {matrix && (
            <>
              <CapabilityGrid cells={buildGrid(matrix, members).cells} roles={matrix.roles} />
              <GridLegend />
              <RoleReference matrix={matrix} />
            </>
          )}
          <MirrorRegistryPanel />

          <section className="rounded-lg border border-border bg-surface">
            <h2 className="border-b border-border px-4 py-2 text-xs uppercase tracking-wide text-muted">
              Members of {ctx.active.org_name} · {members.length}
            </h2>
            <ul>
              {members.length === 0 && (
                <li className="px-4 py-3 text-sm text-muted">
                  No member rows are readable here.
                </li>
              )}
              {members.map((m) => {
                const keys = Object.keys((m.permissions ?? {}) as Record<string, unknown>);
                const manager = isManagerRole(m.role);
                // Does this row match what its own role would grant TODAY? A row
                // written by hand never went through accept_invite() or
                // add_org_member() and so was never seeded — it looks like a
                // normal member row until somebody tries to do their job. This
                // is the one place that difference becomes visible.
                const drift = matrix
                  ? driftFromRoleDefault(matrix, m.role, m.permissions)
                  : null;
                return (
                  <li
                    key={m.user_id}
                    id={`member-${m.user_id}`}
                    className="border-b border-border px-4 py-3 last:border-0"
                  >
                   <div className="flex flex-wrap items-baseline justify-between gap-x-4 gap-y-1">
                    <div className="min-w-0">
                      <span className="font-medium text-text">
                        {m.full_name ?? "Unnamed member"}
                      </span>
                      <span className="ml-2 text-xs text-muted">{m.role}</span>
                    </div>
                    <span className="text-right text-xs">
                      {manager ? (
                        <span className="text-muted">
                          manager tier — capabilities come from the role, not these keys
                        </span>
                      ) : !drift ? (
                        <span className="text-muted">role matrix unavailable</span>
                      ) : drift.kind === "unknown-role" ? (
                        <span className="text-[var(--warn-strong)]">
                          <code>{m.role}</code> is not a role the database lists
                        </span>
                      ) : drift.kind === "no-keys" ? (
                        <span className="font-medium text-[var(--warn-strong)]">
                          no permission keys — denied everything, where{" "}
                          <code>{m.role}</code> would grant{" "}
                          {matrix ? grantedCountForRole(matrix, m.role) ?? "?" : "?"} of {CAPABILITIES.length}
                        </span>
                      ) : drift.kind === "differs" ? (
                        <span className="text-[var(--warn-strong)]">
                          does not match the <code>{m.role}</code> default —{" "}
                          {[
                            drift.missing.length ? `${drift.missing.length} key(s) absent` : null,
                            drift.extraTrue.length ? `${drift.extraTrue.length} granted beyond it` : null,
                            drift.extraFalse.length ? `${drift.extraFalse.length} withheld from it` : null,
                          ]
                            .filter(Boolean)
                            .join(", ")}
                        </span>
                      ) : (
                        <span className="text-muted">
                          {keys.length} key{keys.length === 1 ? "" : "s"} · matches the{" "}
                          <code>{m.role}</code> default
                        </span>
                      )}
                    </span>
                   </div>
                    {matrix && (
                      <MemberCapabilityEditor
                        orgId={params.orgId}
                        member={m}
                        matrix={matrix}
                        open={searchParams.edit === m.user_id}
                      />
                    )}
                  </li>
                );
              })}
            </ul>
          </section>

          <p className="text-xs leading-relaxed text-muted">
            The role list and every role&rsquo;s defaults on this page are read live from{" "}
            <code>role_capability_matrix()</code>. The manager short-circuit and the
            enforcement counts are still copies of the live schema — the matrix does not
            contain either — and the queries that re-derive them are in the registry
            above.
          </p>
        </>
      )}
    </div>
  );
}

function formatDay(iso: string | null) {
  if (!iso) return "an unknown date";
  return new Date(iso).toLocaleDateString("en-US", {
    month: "short",
    day: "numeric",
    year: "numeric",
  });
}
