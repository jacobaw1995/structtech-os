import {
  CAPABILITIES,
  ENFORCEMENT,
  ROLE_DEFAULTS,
  ORG_ROLES,
  roleGroups,
  defaultsDiff,
  type OrgRole,
} from "@/lib/permissions/model";

/**
 * WHAT EACH ROLE GRANTS — the reference for the moment a role is CHOSEN.
 *
 * There is no role picker in this application. Nothing in src/ calls
 * add_org_member(), accept_invite(), or writes org_invites; the only mentions
 * of `role` outside this module are read-only displays. So the role is chosen
 * by hand, in SQL or the Supabase dashboard, and the only thing this codebase
 * can do about that is put the consequences somewhere the person about to type
 * it will look. That is this component, and it is a mitigation, not a fix — the
 * fix is a provisioning UI, which needs a write path that does not exist.
 *
 * Grouped, not listed as seven rows of ticks. Seven roles produce only FOUR
 * distinct answers, and the two facts a reader needs — "these are the same"
 * and "these differ by exactly one key" — are invisible in a seven-row matrix
 * and unmissable once grouped.
 */
export function RoleReference() {
  const groups = roleGroups();
  // Measured, not asserted: ask the model which keys actually differ rather
  // than hard-coding "manage_catalog" into a sentence that could go stale
  // independently of the table above it.
  const officeVsMember = defaultsDiff("office", "member");

  return (
    <section className="rounded-lg border border-border bg-surface">
      <div className="border-b border-border px-4 py-3">
        <h2 className="text-sm font-semibold text-text">
          What each role grants when you add someone
        </h2>
        <p className="mt-1 text-xs leading-relaxed text-muted">
          Seven roles, four distinct answers. This is the output of{" "}
          <code>default_permissions_for_role()</code> — what a new member is seeded
          with. It is not what anyone currently has; the grid above is that.
        </p>
      </div>

      {officeVsMember.length > 0 && (
        <div className="border-b border-border bg-warn-soft px-4 py-3">
          <h3 className="text-sm font-semibold text-text">
            <code>office</code> and <code>member</code> differ by{" "}
            {officeVsMember.length === 1 ? "one key" : `${officeVsMember.length} keys`}
          </h3>
          <p className="mt-1 text-sm leading-relaxed text-text">
            They are identical on {CAPABILITIES.length - officeVsMember.length} of{" "}
            {CAPABILITIES.length} capabilities and differ only on{" "}
            {officeVsMember.map((c, i) => (
              <span key={c}>
                {i > 0 && ", "}
                <code className="font-medium">{c}</code>
              </span>
            ))}
            , which <code>office</code> gets and <code>member</code> does not.
          </p>
          <p className="mt-1.5 text-xs leading-relaxed text-muted">
            An office hire added as <code>member</code> keeps everything else and
            silently loses{" "}
            {officeVsMember.map((c) => ENFORCEMENT[c].sites).reduce((a, b) => a + b, 0)}{" "}
            enforcement sites&rsquo; worth of access — the product catalog. Nothing
            in the application asks for a role, so this is decided wherever the row
            is written by hand.
          </p>
        </div>
      )}

      <ul>
        {groups.map((g) => (
          <li key={g.roles.join("+")} className="border-b border-border px-4 py-3 last:border-0">
            <div className="flex flex-wrap items-center gap-1.5">
              {g.roles.map((r) => (
                <span
                  key={r}
                  className="inline-flex items-center rounded-full border border-border bg-surface2 px-2 py-0.5 text-xs font-medium text-text"
                >
                  {r}
                </span>
              ))}
              {g.roles.length > 1 && (
                <span className="text-xs text-muted">
                  — identical, all {g.roles.length} of them
                </span>
              )}
            </div>

            {/* THE RUNG. Grouping alone still made a reader diff two lists of
                ticks by eye to find the one key separating office from member —
                which is the exact work this section exists to remove. Each rung
                now states its own difference from the one above. */}
            {g.dropsFromAbove && (
              <p className="mt-1.5 text-xs leading-relaxed text-[var(--warn-strong)]">
                Same as {g.dropsFromAbove.roles.join(" / ")}, minus{" "}
                {g.dropsFromAbove.lost.map((c, i) => (
                  <span key={c}>
                    {i > 0 && ", "}
                    <code className="font-medium">{c}</code>
                  </span>
                ))}
                {!g.nested && (
                  <>
                    {" "}
                    — and it also gains{" "}
                    {g.dropsFromAbove.gained.map((c, i) => (
                      <span key={c}>
                        {i > 0 && ", "}
                        <code className="font-medium">{c}</code>
                      </span>
                    ))}
                    , so these roles are not a simple ladder.
                  </>
                )}
              </p>
            )}
            <div className="mt-2 grid gap-x-6 gap-y-1 sm:grid-cols-2">
              <CapList label="Grants" caps={g.grants} tone="grant" />
              <CapList label="Denies" caps={g.denies} tone="deny" />
            </div>
          </li>
        ))}
      </ul>

      <p className="border-t border-border px-4 py-3 text-xs leading-relaxed text-muted">
        Manager tier — <code>owner</code>, <code>admin</code>,{" "}
        <code>agency_admin</code> — never actually consults these values:{" "}
        <code>is_org_manager()</code> short-circuits <code>has_capability()</code>{" "}
        first. Their row is seeded all-true anyway so that access survives a future
        change to that bypass, which is why they appear here at all.
      </p>
    </section>
  );
}

function CapList({
  label,
  caps,
  tone,
}: {
  label: string;
  caps: readonly string[];
  tone: "grant" | "deny";
}) {
  return (
    <div>
      <div className="text-[11px] font-semibold uppercase tracking-wide text-muted">
        {label} · {caps.length}
      </div>
      {caps.length === 0 ? (
        <p className="text-xs text-muted">nothing</p>
      ) : (
        <ul className="mt-0.5 space-y-0.5">
          {caps.map((c) => {
            const inert = ENFORCEMENT[c as keyof typeof ENFORCEMENT].sites === 0;
            return (
              <li key={c} className="flex items-baseline gap-1.5 text-xs">
                <span
                  aria-hidden="true"
                  className={tone === "grant" ? "text-accent-strong" : "text-muted"}
                >
                  {tone === "grant" ? "✓" : "–"}
                </span>
                <span className={tone === "grant" ? "text-text" : "text-muted"}>{c}</span>
                {/* A capability nothing reads is worth marking HERE too. A
                    reader choosing a role should not weigh a key that decides
                    nothing against one that gates twelve enforcement sites. */}
                {inert && (
                  <span className="text-[10px] uppercase tracking-wide text-muted">
                    inert
                  </span>
                )}
              </li>
            );
          })}
        </ul>
      )}
    </div>
  );
}

/** Sanity: every role in the vocabulary has a defaults entry. */
export const ROLE_DEFAULTS_COVER_ALL_ROLES: boolean = ORG_ROLES.every(
  (r: OrgRole) => ROLE_DEFAULTS[r] !== undefined
);
