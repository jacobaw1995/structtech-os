import {
  CAPABILITIES,
  ENFORCEMENT,
  isManagerRole,
  type Cell,
} from "@/lib/permissions/model";

// Roles are abbreviated in the column heads because `client_portal_viewer` is
// 20 characters and there are seven of them. The full name is on the <abbr>
// title and spelled out in the legend under the grid — an abbreviation a reader
// cannot expand is worse than a scrollbar.
// Presentation only. Roles now arrive from the database, so a role this map has
// never heard of renders under its FULL name rather than being dropped or
// crashing the grid — a new role added to the CHECK constraint appears here the
// next time the page loads, before anyone edits this file.
const ROLE_SHORT: Record<string, string> = {
  owner: "owner",
  admin: "admin",
  agency_admin: "agency",
  office: "office",
  member: "member",
  field: "field",
  client_portal_viewer: "portal",
};


export function CapabilityGrid({ cells, roles }: { cells: Cell[]; roles: string[] }) {
  const shortName = (r: string) => ROLE_SHORT[r] ?? r;
  // Column count follows the live role list instead of a hard-coded 7.
  const cols = { gridTemplateColumns: `minmax(0,1fr) repeat(${roles.length}, 3.75rem)` };
  const at = (c: string, r: string) =>
    cells.find((x) => x.capability === c && x.role === r)!;

  return (
    <div className="rounded-lg border border-border bg-surface">
      {/* DESKTOP — a real grid. Below lg it is replaced by the stacked cards
          further down rather than being scrolled sideways: this page is read
          on a phone by an owner deciding whether to hire, and a matrix that
          only works at 1200px is a matrix nobody checks. */}
      <div className="hidden lg:block">
        <div
          style={cols}
          className="grid gap-x-2 border-b border-border px-4 py-2 text-xs uppercase tracking-wide text-muted"
        >
          <span>Capability</span>
          {roles.map((r) => (
            <abbr
              key={r}
              title={r}
              className={`text-center no-underline ${
                isManagerRole(r) ? "text-accent-strong" : ""
              }`}
            >
              {shortName(r)}
            </abbr>
          ))}
        </div>

        <ul>
          {CAPABILITIES.map((cap) => {
            const e = ENFORCEMENT[cap];
            const inert = e.sites === 0;
            return (
              <li
                key={cap}
                style={cols}
                className={`grid items-center gap-x-2 border-b border-border px-4 py-3 last:border-0 ${
                  inert ? "bg-warn-soft/40" : ""
                }`}
              >
                <div className="min-w-0 pr-4">
                  <div className="flex flex-wrap items-baseline gap-x-2">
                    <span className="font-medium text-text">{cap}</span>
                    {inert ? (
                      <span className="rounded bg-warn-soft px-1.5 py-0.5 text-[11px] font-medium text-[var(--warn-strong)]">
                        not enforced anywhere
                      </span>
                    ) : (
                      <span className="text-[11px] text-muted">
                        {e.sites} enforcement {e.sites === 1 ? "site" : "sites"}
                      </span>
                    )}
                  </div>
                  <p className="mt-0.5 text-xs leading-relaxed text-muted">{e.summary}</p>
                  {e.constraint && (
                    <p className="mt-1 text-[11px] text-[var(--warn-strong)]">{e.constraint}</p>
                  )}
                </div>
                {roles.map((r) => (
                  <div key={r} className="flex justify-center">
                    <Mark cell={at(cap, r)} />
                  </div>
                ))}
              </li>
            );
          })}
        </ul>
      </div>

      {/* MOBILE / TABLET — one card per capability. Same data, same states,
          no sideways scroll. */}
      <ul className="lg:hidden">
        {CAPABILITIES.map((cap) => {
          const e = ENFORCEMENT[cap];
          const inert = e.sites === 0;
          return (
            <li
              key={cap}
              className={`border-b border-border px-4 py-3 last:border-0 ${
                inert ? "bg-warn-soft/40" : ""
              }`}
            >
              <div className="flex flex-wrap items-baseline gap-x-2">
                <span className="font-medium text-text">{cap}</span>
                {inert ? (
                  <span className="rounded bg-warn-soft px-1.5 py-0.5 text-[11px] font-medium text-[var(--warn-strong)]">
                    not enforced anywhere
                  </span>
                ) : (
                  <span className="text-[11px] text-muted">
                    {e.sites} enforcement {e.sites === 1 ? "site" : "sites"}
                  </span>
                )}
              </div>
              <p className="mt-0.5 text-xs leading-relaxed text-muted">{e.summary}</p>
              {e.constraint && (
                <p className="mt-1 text-[11px] text-[var(--warn-strong)]">{e.constraint}</p>
              )}
              <div className="mt-2 flex flex-wrap gap-1.5">
                {roles.map((r) => {
                  const cell = at(cap, r);
                  return (
                    <span
                      key={r}
                      className="inline-flex items-center gap-1.5 rounded-full border border-border px-2 py-1 text-xs"
                    >
                      <span className="text-muted">{r}</span>
                      <Mark cell={cell} />
                    </span>
                  );
                })}
              </div>
            </li>
          );
        })}
      </ul>
    </div>
  );
}

/**
 * FIVE states, not two, and the distinction between three of them is the whole
 * point of the page:
 *
 *   BY ROLE   — is_org_manager() short-circuits has_capability() before the
 *               stored row is read. True because of the role. Cannot be revoked
 *               by editing permissions, because permissions is not consulted.
 *   GRANTED   — a real member row carries the key set true.
 *   DENIED    — a real member row carries the key set FALSE. Somebody decided.
 *   NEVER SET — a real member row has no such key. Under A2.0's closed default
 *               the effective answer is also "denied" — but nobody decided it,
 *               and that is a different fact with a different fix.
 *   NO MEMBER — nobody in this tenant holds that role, so this grid has not
 *               observed anything. Not a guess, not a blank.
 */
function Mark({ cell }: { cell: Cell }) {
  if (cell.kind === "manager") {
    return (
      /* Quiet on purpose. Looked at on screen, a solid accent circle in three
         columns of every row drew the eye to the cells that never vary and
         away from ! and ≠, which are the two a reader must act on. */
      <Dot title="Always true by role — is_org_manager() short-circuits has_capability() before the stored permissions row is read."
           className="border border-accent-soft bg-accent-soft/60 text-accent-strong">
        R
      </Dot>
    );
  }
  if (cell.kind === "no-member") {
    return (
      /* EMPTY, and dashed. A denial is a filled circle because somebody made
         a decision; this is the absence of any observation and must not be
         mistaken for one. */
      <Dot title="No member of this tenant holds this role, so nothing has been observed. This grid shows what members HAVE; what a role would get is in the reference below, read live."
           className="border border-dashed border-border">
        {""}
      </Dot>
    );
  }
  if (cell.kind === "unset") {
    return (
      <Dot title={`${cell.members} member(s) of this role carry NO key for this capability. Under the closed default that denies it — but it was never decided, it was never written.`}
           className="bg-warn text-white">
        !
      </Dot>
    );
  }
  if (cell.split) {
    return (
      <Dot title={`Members of this role DISAGREE across ${cell.members} rows. The stored data has drifted from a single answer.`}
           className="bg-warn text-white">
        ≠
      </Dot>
    );
  }
  return cell.value ? (
    <Dot title={`Granted on ${cell.members} member row(s).`} className="bg-accent-soft text-accent-strong">
      ✓
    </Dot>
  ) : (
    <Dot title={`Explicitly set false on ${cell.members} member row(s).`} className="bg-surface2 text-muted">
      –
    </Dot>
  );
}

function Dot({
  children,
  title,
  className,
}: {
  children: React.ReactNode;
  title: string;
  className: string;
}) {
  return (
    <span
      title={title}
      className={`inline-flex h-6 w-6 shrink-0 items-center justify-center rounded-full text-xs font-semibold ${className}`}
    >
      {children}
    </span>
  );
}

export function GridLegend() {
  return (
    <div className="rounded-lg border border-border bg-surface p-4 text-xs leading-relaxed text-muted">
      <p className="mb-2 font-medium text-text">How to read a cell</p>
      <ul className="space-y-1.5">
        <li className="flex gap-2">
          <Dot title="" className="border border-accent-soft bg-accent-soft/60 text-accent-strong">R</Dot>
          <span>
            <strong className="text-text">True by role.</strong> owner, admin and agency_admin
            short-circuit <code>has_capability()</code> before the stored row is read. Editing
            their permissions would change nothing.
          </span>
        </li>
        <li className="flex gap-2">
          <Dot title="" className="bg-accent-soft text-accent-strong">✓</Dot>
          <span><strong className="text-text">Granted</strong> on a real member row.</span>
        </li>
        <li className="flex gap-2">
          <Dot title="" className="bg-surface2 text-muted">–</Dot>
          <span><strong className="text-text">Denied</strong> — a filled mark, because the key is present and set false. Somebody decided this.</span>
        </li>
        <li className="flex gap-2">
          <Dot title="" className="bg-warn text-white">!</Dot>
          <span>
            <strong className="text-text">Never set.</strong> The key is absent. The closed default
            denies it, but nobody decided that — it was never written. Different fact, different fix.
          </span>
        </li>
        <li className="flex gap-2">
          <Dot title="" className="bg-warn text-white">≠</Dot>
          <span><strong className="text-text">Split.</strong> Members of one role disagree. Stored data has drifted.</span>
        </li>
        <li className="flex gap-2">
          <Dot title="" className="border border-dashed border-border">{""}</Dot>
          <span>
            <strong className="text-text">No member.</strong> Empty and dashed. Nobody here holds that role, so nothing
            was observed. This grid shows what members have, not what a role would
            get — that is the reference below, read live from{" "}
            <code>role_capability_matrix()</code>.
          </span>
        </li>
      </ul>
      <p className="mt-3">
        Roles, left to right: owner · admin · agency (agency_admin) · office · member · field ·
        portal (client_portal_viewer). The first three are manager tier.
      </p>
    </div>
  );
}
