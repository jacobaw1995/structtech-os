import Link from "next/link";
import { getWorkspaceContext } from "@/lib/workspace/context";
import { CapabilityGrid, GridLegend } from "@/components/permissions/CapabilityGrid";
import {
  buildGrid,
  isManagerRole,
  CAPABILITIES,
  ENFORCEMENT,
  NO_WRITE_PATH_REASON,
  type OrgMemberRow,
} from "@/lib/permissions/model";

// G3 · Capability admin surface — READ ONLY, and that is a finding rather than
// a shortcut. See "WHY THIS IS READ ONLY" below.
//
// NOT under requireModuleAccess(): permissions are not a module, they are org
// administration, and gating them on `estimating` or `crm` entitlement would be
// wrong in both directions. getWorkspaceContext() still runs — the org guard,
// the session and the redirect to /select-workspace all come from it.

export default async function PermissionsPage({
  params,
}: {
  params: { orgId: string };
}) {
  const ctx = await getWorkspaceContext(params.orgId);

  // Visibility gate, mirroring is_org_manager()'s role list. This is NOT the
  // security boundary and is not pretending to be one — the boundary is that
  // no write path exists at all (see NO_WRITE_PATH_REASON), plus RLS on every
  // row this page reads. It is here so a crew member is not shown an
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

  const { cells } = buildGrid(members);

  // Members whose permissions object is empty. Under A2.0's closed default this
  // person is denied EVERYTHING, and A2.0b deliberately left this case open:
  // "The residual case — a direct INSERT with permissions '{}' — is left
  // failing CLOSED". This is that case, in production, and it is the first
  // thing this page should tell you.
  const unprovisioned = members.filter(
    (m) => Object.keys((m.permissions ?? {}) as Record<string, unknown>).length === 0
  );

  const inert = CAPABILITIES.filter((c) => ENFORCEMENT[c].sites === 0);

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
          {/* WHY THIS IS READ ONLY — stated first, at full weight, because a
              grid that looks editable and is not is worse than one that says
              so. This is not a decision I made about the UI; it is the state
              of the schema, measured today. */}
          <section className="rounded-lg border border-accent bg-accent-soft/50 px-4 py-3">
            <h2 className="text-sm font-semibold text-text">This grid is read-only, and here is why</h2>
            <p className="mt-1 text-sm leading-relaxed text-text">{NO_WRITE_PATH_REASON}</p>
            <p className="mt-2 text-xs leading-relaxed text-muted">
              Every write on this platform goes through a security-definer RPC. There is no
              RPC for this one, so there is nothing for a button here to call. Building the
              write path is a schema change and belongs to whoever owns migrations — not to
              this screen.
            </p>
          </section>

          {error && (
            <p className="rounded-lg border border-warn bg-warn-soft px-4 py-3 text-sm text-text">
              Could not read members: {error.message}
            </p>
          )}

          {unprovisioned.length > 0 && (
            <section className="rounded-lg border border-warn bg-warn-soft px-4 py-3">
              <h2 className="text-sm font-semibold text-text">
                {unprovisioned.length} member
                {unprovisioned.length === 1 ? " has" : "s have"} no permissions at all
              </h2>
              <ul className="mt-2 space-y-1 text-sm text-text">
                {unprovisioned.map((m) => (
                  <li key={m.user_id}>
                    <span className="font-medium">{m.full_name ?? "Unnamed member"}</span>{" "}
                    <span className="text-muted">
                      · {m.role} · joined {formatDay(m.created_at)}
                    </span>
                  </li>
                ))}
              </ul>
              <p className="mt-2 text-xs leading-relaxed text-muted">
                Their <code>permissions</code> object is empty. Since A2.0 the default is
                CLOSED — an absent key grants nothing — so this person is denied every
                capability on the grid below, including the ones their role would normally
                get. Nobody chose that: the row was written by a path that does not seed,
                and no screen in this app can fix it. This is the case A2.0b recorded as
                deliberately left &ldquo;failing closed&rdquo;.
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

          <CapabilityGrid cells={cells} />
          <GridLegend />

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
                return (
                  <li
                    key={m.user_id}
                    className="flex flex-wrap items-baseline justify-between gap-x-4 gap-y-1 border-b border-border px-4 py-3 last:border-0"
                  >
                    <div className="min-w-0">
                      <span className="font-medium text-text">
                        {m.full_name ?? "Unnamed member"}
                      </span>
                      <span className="ml-2 text-xs text-muted">{m.role}</span>
                    </div>
                    <span className="text-xs text-muted">
                      {manager
                        ? "manager tier — capabilities come from the role, not from these keys"
                        : keys.length === 0
                          ? "no permission keys — denied everything"
                          : `${keys.length} permission key${keys.length === 1 ? "" : "s"} stored`}
                    </span>
                  </li>
                );
              })}
            </ul>
          </section>

          <p className="text-xs leading-relaxed text-muted">
            The role list, the manager short-circuit and the enforcement counts on this page
            are mirrored from the live schema as measured on 2026-09-04; the app is not
            permitted to execute <code>default_permissions_for_role()</code> and so cannot
            re-derive them at runtime. The queries that produced each mirror are recorded in{" "}
            <code>src/lib/permissions/model.ts</code> so they can be re-run rather than
            trusted.
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
