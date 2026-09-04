import type { Database } from "@/lib/supabase/database.types";

/**
 * G3 — the capability model, as it exists in the LIVE schema on 2026-09-04.
 *
 * ============================================================================
 * WHY THIS FILE CONTAINS MIRRORED CONSTANTS AND NOT LIVE READS
 * ============================================================================
 * Three of the four things this grid needs cannot be read by the application
 * at runtime, and each for a different, deliberate reason. This is stated here
 * rather than discovered later, because a mirror nobody knows is a mirror is
 * how a grid starts lying.
 *
 *  1. THE ROLE VOCABULARY lives in a CHECK constraint on `org_members.role`.
 *     PostgREST exposes `public` only; `pg_constraint` is not reachable.
 *  2. THE ROLE DEFAULTS live in `default_permissions_for_role(text)`, and
 *     A2.1c step 1a (migration 20260826133457) REVOKED EXECUTE ON IT FROM
 *     `authenticated` on purpose — it is called only from inside the database.
 *     Measured, not assumed:
 *         has_function_privilege('authenticated', oid, 'EXECUTE') -> FALSE
 *     So the app cannot ask what a role's defaults are. It can only observe
 *     what real member rows actually carry.
 *  3. THE ENFORCEMENT MAP is spread across function bodies and RLS policy
 *     expressions in `pg_proc` / `pg_policies`. Same reachability problem as 1.
 *
 * What IS live: `org_members` (SELECT policy "member read own members", scoped
 * to my_org_ids()) and `has_capability()` (EXECUTE granted to authenticated).
 * The grid derives everything it can from those two and mirrors only what it
 * must — each mirror labelled, dated, and shipped with the query that produced
 * it so the next person re-derives instead of trusting this comment.
 *
 * IF TRACK S ADDS A CAPABILITY OR A ROLE, THIS FILE GOES STALE SILENTLY.
 * That is the cost of the revoke in (2) and it is a real cost. The fix is a
 * definer RPC returning the role x capability matrix — reported, not built.
 */

export type OrgMemberRow = Database["public"]["Tables"]["org_members"]["Row"];

// ---------------------------------------------------------------------------
// MIRROR 1 — the role vocabulary.
// Derived 2026-09-04 from constraint `org_members_role_check`:
//   select pg_get_constraintdef(oid) from pg_constraint
//    where conrelid = 'public.org_members'::regclass and contype = 'c';
// -> CHECK (role = ANY (ARRAY['owner','admin','office','field',
//                             'client_portal_viewer','agency_admin','member']))
// Order below is presentation order (manager tier first), not constraint order.
// ---------------------------------------------------------------------------
export const ORG_ROLES = [
  "owner",
  "admin",
  "agency_admin",
  "office",
  "member",
  "field",
  "client_portal_viewer",
] as const;

export type OrgRole = (typeof ORG_ROLES)[number];

// ---------------------------------------------------------------------------
// MIRROR 2 — the manager short-circuit, from the live body of is_org_manager():
//   select exists (select 1 from public.org_members
//                   where user_id = auth.uid() and org_id = p_org_id
//                     and role in ('owner','admin','agency_admin'));
//
// This is THE most consequential fact on the whole page. has_capability() reads
//   case when is_org_manager(p_org_id) then true else <stored key> end
// so for these three roles the stored `permissions` row IS NOT CONSULTED. A
// manager's grid cell is true because of their role, and setting the stored key
// to false would change nothing. A grid that showed the stored value for these
// roles would be showing a number that does not decide anything.
// ---------------------------------------------------------------------------
export const MANAGER_ROLES: readonly OrgRole[] = ["owner", "admin", "agency_admin"];

export function isManagerRole(role: string): boolean {
  return (MANAGER_ROLES as readonly string[]).includes(role);
}

// ---------------------------------------------------------------------------
// MIRROR 3 — the capability set and where each one is actually ENFORCED.
//
// The KEYS are the nine emitted by default_permissions_for_role(), confirmed
// against the live function body AND against every key stored on a real member
// row (jsonb_each over org_members.permissions) — the two agree, 9 = 9.
//
// The SITES were counted 2026-09-04 by this query, which folds in the two thin
// wrappers because view_financials and view_master_work_order are enforced
// through can_view_financials()/can_view_master_work_order(), never by a direct
// has_capability() literal:
//
//   with fn as (select 'function' kind, proname site, prosrc body
//                 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
//                where n.nspname='public'
//                  and proname not in ('has_capability','can_view_financials',
//                                      'can_view_master_work_order')),
//        pol as (select case when permissive='RESTRICTIVE'
//                            then 'restrictive policy' else 'policy' end,
//                       tablename||'.'||policyname,
//                       coalesce(qual,'')||' '||coalesce(with_check,'')
//                  from pg_policies where schemaname='public'),
//        s as (select * from fn union all select * from pol)
//   select (regexp_matches(body,'has_capability\s*\([^,]+,\s*''([a-z_]+)''','g'))[1], ...
//   -- plus: select ... from s where body ~ 'can_view_financials'
//   -- plus: select ... from s where body ~ 'can_view_master_work_order'
//
// TWO OF THE NINE CAME BACK WITH ZERO SITES. `schedule` and `view_field` are
// derived by the deriver, stored on every seeded member row, and consulted by
// NOTHING — no function body, no policy, no RESTRICTIVE policy, and nothing in
// src/. They are names. The grid says so on their own row rather than drawing a
// tick that implies a control, because a tick beside an unenforced key is the
// same defect as a label standing in for a check.
// ---------------------------------------------------------------------------
export type Enforcement = {
  /** Distinct DB objects that consult this capability. 0 means it is inert. */
  sites: number;
  /** Human sentence for the grid. */
  summary: string;
  /** The objects themselves, so a reader can go and look. */
  where: string[];
  /**
   * Set when denying this capability is a stated product constraint rather
   * than an accident — SCOPE constraint 7, "no dollars in the field".
   */
  constraint?: string;
};

export const CAPABILITIES = [
  "view_financials",
  "view_estimates",
  "view_master_work_order",
  "manage_catalog",
  "edit_leads",
  "create_estimates",
  "add_notes",
  "schedule",
  "view_field",
] as const;

export type Capability = (typeof CAPABILITIES)[number];

export const ENFORCEMENT: Record<Capability, Enforcement> = {
  view_financials: {
    sites: 12,
    summary:
      "8 RPCs + 4 RESTRICTIVE policies, all through can_view_financials(). A RESTRICTIVE policy ANDs with every other policy, so this key is what actually keeps money off a crew screen.",
    where: [
      "restrictive policy: deals · estimates · estimate_line_items · products",
      "rpc: fetch_deal, fetch_estimate, fetch_product, list_products",
      "rpc: create_product, update_product, generate_take_off, update_deal_fields",
    ],
    constraint: "SCOPE constraint 7 — no dollars in the field.",
  },
  view_estimates: {
    sites: 10,
    summary:
      "9 policies across estimates, estimate_line_items and signatures, plus generate_take_off(). Also gates whether the Estimating module appears in the sidebar at all.",
    where: [
      "policy: estimates (read/insert/update)",
      "policy: estimate_line_items (read/insert/update/delete)",
      "policy: signatures (read/insert)",
      "rpc: generate_take_off",
      "app: getWorkspaceContext() hides the module when false",
    ],
    constraint: "SCOPE constraint 7 — no dollars in the field.",
  },
  view_master_work_order: {
    sites: 5,
    summary:
      "3 RESTRICTIVE policies + 2 RPCs, through can_view_master_work_order(). work_orders is partially exempt: a row with kind='trade' is readable regardless.",
    where: [
      "restrictive policy: work_orders, work_order_activity, work_order_agreements",
      "rpc: fetch_work_order, fetch_work_order_tree",
    ],
    constraint: "SCOPE constraint 7 — a crew sees its trade, not the master.",
  },
  manage_catalog: {
    sites: 6,
    summary:
      "3 RPCs + 3 policies on products. Both layers moved off manager-tier onto this key in A2.1c so an office hire can maintain the item list.",
    where: [
      "rpc: create_product, update_product, delete_product",
      "policy: products (insert/update/delete)",
    ],
  },
  edit_leads: {
    sites: 6,
    summary: "5 RPCs + 1 policy on deals.",
    where: [
      "rpc: update_deal_fields, update_deal_stage, update_intake_checklist_field",
      "rpc: archive_deal, restore_deal",
      "policy: deals (update)",
    ],
  },
  create_estimates: {
    sites: 1,
    summary: "One RPC: create_estimate_from_deal().",
    where: ["rpc: create_estimate_from_deal"],
  },
  add_notes: {
    sites: 1,
    summary: "One RPC: add_deal_note().",
    where: ["rpc: add_deal_note"],
  },
  schedule: {
    sites: 0,
    summary:
      "NOTHING READS THIS KEY. No RPC, no policy, nothing in the app. It is derived onto every member row and then never consulted — granting or revoking it changes nothing anyone can observe.",
    where: [],
  },
  view_field: {
    sites: 0,
    summary:
      "NOTHING READS THIS KEY. Field access is decided by modulesVisibleForRole(role) in the app and by org-scoped RLS, neither of which looks at this permission.",
    where: [],
  },
};

export function isCapability(k: string): k is Capability {
  return (CAPABILITIES as readonly string[]).includes(k);
}

// ---------------------------------------------------------------------------
// THE DERIVATION — this part is live, not mirrored.
// ---------------------------------------------------------------------------

/** What the grid can honestly say about one (capability, role) cell. */
export type CellState =
  | {
      kind: "manager";
      /** Always true, and not from the stored row. */
      value: true;
    }
  | {
      kind: "observed";
      value: boolean;
      /** How many members of this role carry that value. */
      members: number;
      /** True when members of the same role disagree — a drift alarm. */
      split: boolean;
    }
  | {
      kind: "unset";
      /** Members of this role exist but carry no key at all -> closed default. */
      members: number;
    }
  | { kind: "no-member" };

export type Cell = CellState & { capability: Capability; role: OrgRole };

/**
 * Build the grid from the org's real member rows.
 *
 * Deliberately does NOT fall back to a role default when no member holds a
 * role: the app cannot execute default_permissions_for_role(), so any default
 * shown here would be this file guessing. "No member holds this role" is a
 * smaller claim and a true one.
 */
export function buildGrid(members: Pick<OrgMemberRow, "role" | "permissions">[]) {
  const byRole = new Map<string, typeof members>();
  for (const m of members) {
    if (!m.role) continue;
    const list = byRole.get(m.role) ?? [];
    list.push(m);
    byRole.set(m.role, list);
  }

  const cells: Cell[] = [];
  for (const capability of CAPABILITIES) {
    for (const role of ORG_ROLES) {
      cells.push({ capability, role, ...cellFor(capability, role, byRole.get(role) ?? []) });
    }
  }
  return { cells, byRole };
}

function cellFor(
  capability: Capability,
  role: OrgRole,
  rolesMembers: Pick<OrgMemberRow, "role" | "permissions">[]
): CellState {
  // The short-circuit wins before anything is read, so it is tested first —
  // in the same order has_capability() tests it.
  if (isManagerRole(role)) return { kind: "manager", value: true };
  if (rolesMembers.length === 0) return { kind: "no-member" };

  let trues = 0;
  let falses = 0;
  let missing = 0;
  for (const m of rolesMembers) {
    const perms = (m.permissions ?? {}) as Record<string, unknown>;
    if (!(capability in perms)) missing++;
    else if (perms[capability] === true) trues++;
    else falses++;
  }

  // Absence is not false — it is a DIFFERENT state, and conflating them is the
  // exact bug A2.0 closed at the database layer. Under the closed default the
  // effective answer is the same (denied), but the reason is not: a false was
  // decided, a missing key was never written. The office hire in production
  // right now is the missing-key case, and calling it "false" would hide that.
  if (missing > 0 && trues === 0 && falses === 0) {
    return { kind: "unset", members: missing };
  }
  const value = trues > 0 && falses === 0 && missing === 0;
  const split = (trues > 0 && falses + missing > 0) || (falses > 0 && missing > 0);
  return { kind: "observed", value, members: rolesMembers.length, split };
}

/**
 * Why a cell cannot be changed from this screen. Returned for EVERY cell,
 * because right now the answer is the same for every cell and saying it once
 * per page would let a reader assume the exceptions are the editable ones.
 */
export const NO_WRITE_PATH_REASON =
  "No RPC writes org_members.permissions. The only two functions that write org_members at all are add_org_member() (platform-admin only, writes the role default) and accept_invite() (the invitee's own path). Changing one capability for one member has no server action to call.";
