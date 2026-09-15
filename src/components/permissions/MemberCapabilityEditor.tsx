import {
  CAPABILITIES,
  isManagerRole,
  driftFromRoleDefault,
  type RoleMatrix,
  type OrgMemberRow,
} from "@/lib/permissions/model";
import { setMemberCapability } from "@/lib/permissions/actions";

type Member = Pick<OrgMemberRow, "user_id" | "full_name" | "role" | "permissions">;

/**
 * G3 — what one member can do, and the controls to change it.
 *
 * PER MEMBER, NOT PER GRID CELL. The write is set_member_capability(org, user,
 * capability, value): it has no "every member of this role" form. The grid
 * above aggregates members by role, so an editable grid cell would have to
 * fan one click out into N writes the user never saw. The editor lives where
 * the write actually lands — on one person.
 */
export function MemberCapabilityEditor({
  orgId,
  member,
  matrix,
  open,
}: {
  orgId: string;
  member: Member;
  matrix: RoleMatrix;
  open: boolean;
}) {
  const name = member.full_name?.trim() || "This member";
  const perms = (member.permissions ?? {}) as Record<string, unknown>;

  // MANAGER TIER: NO CONTROLS, AND THE RPC'S OWN REASON.
  // set_member_capability refuses a manager-tier target, and has_capability()
  // never reads the stored row for one anyway — is_org_manager() short-circuits
  // first. Offering a toggle here would be offering a write the database
  // refuses, U-W1.6's defect. The sentence below is Track S's refusal, quoted,
  // not a paraphrase of it.
  if (isManagerRole(member.role)) {
    return (
      <p className="text-xs leading-relaxed text-muted">
        {name} is an <code>{member.role}</code> and already passes every capability
        check — setting a capability here would change the stored row and nothing
        else. Change their role instead.
      </p>
    );
  }

  if (!matrix.hasRole(member.role)) {
    return (
      <p className="text-xs leading-relaxed text-[var(--warn-strong)]">
        <code>{member.role}</code> is not a role the database lists, so there is no
        default to compare against and no safe way to edit this row from here.
      </p>
    );
  }

  const drift = driftFromRoleDefault(matrix, member.role, member.permissions);
  const overrides = drift.extraTrue.length + drift.extraFalse.length;
  const neverWritten = drift.missing.length;

  return (
    <details open={open} className="group mt-2">
      <summary className="flex min-h-14 cursor-pointer list-none items-center gap-2 rounded-md border border-border px-3 text-sm font-medium text-text sm:h-10 sm:min-h-0 sm:w-fit [&::-webkit-details-marker]:hidden">
        <span aria-hidden="true" className="text-muted transition-transform group-open:rotate-90">
          ›
        </span>
        Change what {name} can do
      </summary>

      <div className="mt-2 flex flex-col gap-3 rounded-md border border-border p-3">
        {/* ============================================================
            THE ROLE-CHANGE WARNING — at the decision, not in a help page.

            A per-member setting DOES NOT SURVIVE A ROLE CHANGE. The live
            trigger org_members_rederive_permissions fires BEFORE UPDATE
            WHEN old.role IS DISTINCT FROM new.role, and its body is
              new.permissions := default_permissions_for_role(new.role);
            — a REPLACE, not a merge. Track S measured it on 2026-09-11 with
            create_estimates true -> role change -> false. (Its first attempt
            used view_financials, false for both roles, so a wipe and a
            coincidence looked identical; that one was discarded.)

            It is stated here, above the controls, every time they are shown,
            because the person clicking Grant is exactly the person who will
            not be in the room when someone else changes the role later.
            ============================================================ */}
        <div className="rounded-md border border-warn bg-warn-soft px-3 py-2">
          <p className="text-sm font-semibold text-text">
            These settings are erased if {name}&rsquo;s role changes
          </p>
          <p className="mt-1 text-xs leading-relaxed text-text">
            Changing a role replaces everything below with that role&rsquo;s
            defaults — including anything you grant or deny here. Nobody is told
            when it happens.
            {overrides > 0 && (
              <>
                {" "}
                <strong>
                  {overrides} setting{overrides === 1 ? "" : "s"} currently differ
                  {overrides === 1 ? "s" : ""} from what {article(member.role)}{" "}
                  <code>{member.role}</code> gets
                </strong>{" "}
                and would be lost.
              </>
            )}
            {neverWritten > 0 && (
              <>
                {" "}
                {neverWritten} undecided capabilit{neverWritten === 1 ? "y" : "ies"} would
                also stop being undecided — a role change writes all of them.
              </>
            )}
          </p>
        </div>

        {/* 2026-09-14 — one row used to say "not enforced — changing it has no
            effect", from a hand count of database checks (retired mirror C).
            The page cannot see those checks, so it no longer predicts the
            effect of a change. It says what a click DOES, which it can see: the
            stored value is written, and the chip shows the result. */}
        <p className="text-xs leading-relaxed text-muted">
          Grant and Deny change the value stored on {name}&rsquo;s row, and the label
          beside each capability shows what is stored. This page cannot see what in the
          product reads that value.
        </p>

        <ul className="flex flex-col">
          {CAPABILITIES.map((cap) => {
            const stored: "granted" | "denied" | "never" = !(cap in perms)
              ? "never"
              : perms[cap] === true
                ? "granted"
                : "denied";
            const roleGets = matrix.allowed(member.role, cap) === true;

            return (
              <li
                key={cap}
                className="flex flex-col gap-2 border-b border-border py-2 last:border-0 sm:flex-row sm:items-center sm:justify-between"
              >
                <div className="min-w-0">
                  <div className="flex flex-wrap items-center gap-2">
                    <code className="text-sm font-medium text-text">{cap}</code>
                    <StateChip state={stored} />
                  </div>
                  <p className="mt-0.5 text-xs text-muted">
                    {capitalise(article(member.role))} <code>{member.role}</code> gets
                    this by default:{" "}
                    {roleGets ? "yes" : "no"}
                    {stored === "never" &&
                      " · undecided, so the closed default denies it today"}
                  </p>
                </div>

                <div className="flex shrink-0 flex-wrap gap-2">
                  {/* Only the moves that CHANGE something. Granting a granted
                      key is not a control, it is a button that does nothing. */}
                  {stored !== "granted" && (
                    <CapForm orgId={orgId} userId={member.user_id} cap={cap} value="true" label="Grant" />
                  )}
                  {stored !== "denied" && (
                    <CapForm orgId={orgId} userId={member.user_id} cap={cap} value="false" label="Deny" />
                  )}
                </div>
              </li>
            );
          })}
        </ul>

        {/* THERE IS NO WAY BACK TO UNDECIDED. set_member_capability refuses a
            null value ("a capability is granted or denied, never null"), so
            the first write onto a never-written key is a DECISION, not a
            toggle: its value can be flipped later, its undecidedness cannot be
            restored. That is also why "Deny" on an undecided key is offered
            separately from "leave it": they are different facts, and after the
            write the chip says Denied, not Never written. */}
        <p className="text-xs leading-relaxed text-muted">
          An <strong className="text-text">undecided</strong> capability is not a
          default. Granting or denying one records a decision, and it cannot be put
          back to undecided afterwards — only switched between granted and denied.
        </p>
      </div>
    </details>
  );
}

/** Three states, three renders. Never collapsed into two. */
function StateChip({ state }: { state: "granted" | "denied" | "never" }) {
  if (state === "granted") {
    return (
      <span className="rounded bg-accent-soft px-1.5 py-0.5 text-[11px] font-medium text-accent-strong">
        Granted
      </span>
    );
  }
  if (state === "denied") {
    return (
      <span className="rounded bg-surface2 px-1.5 py-0.5 text-[11px] font-medium text-text">
        Denied — decided
      </span>
    );
  }
  return (
    <span className="rounded border border-dashed border-warn px-1.5 py-0.5 text-[11px] font-medium text-[var(--warn-strong)]">
      Never written — undecided
    </span>
  );
}

function CapForm({
  orgId,
  userId,
  cap,
  value,
  label,
}: {
  orgId: string;
  userId: string;
  cap: string;
  value: "true" | "false";
  label: string;
}) {
  return (
    <form action={setMemberCapability}>
      <input type="hidden" name="orgId" value={orgId} />
      <input type="hidden" name="userId" value={userId} />
      <input type="hidden" name="capability" value={cap} />
      <input type="hidden" name="value" value={value} />
      <button
        type="submit"
        className={`min-h-14 rounded-md px-4 text-sm font-medium sm:h-9 sm:min-h-0 ${
          value === "true"
            ? "border border-accent text-accent-strong"
            : "border border-border text-text"
        }`}
      >
        {label}
      </button>
    </form>
  );
}

// "an office", "a member". Found by READING THE RENDERED TEXT against the live
// matrix: the first draft printed "what a office gets". Roles now arrive from
// the database, so the article is computed rather than written for one role.
function article(word: string): "a" | "an" {
  return /^[aeiou]/i.test(word) ? "an" : "a";
}
function capitalise(w: string): string {
  return w.charAt(0).toUpperCase() + w.slice(1);
}
