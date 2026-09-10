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

// ===========================================================================
// THE MIRROR REGISTRY — U-W1.5, 2026-09-06.
//
// Material Matrix's framing, adopted: AN ENUMERATION THAT LIVES IN CODE IS
// NEVER QUESTIONED; ONE THAT LIVES IN A DIRECTIVE IS. Each of the four mirrors
// below already stated what it mirrored, when it was derived, and the query
// that re-derives it. What nobody could do was COUNT them — so "how much of
// this file is a copy of something that can change without us?" had no answer
// short of reading three hundred lines.
//
// It now has one, and the count is rendered on the permissions page rather
// than only living here.
//
// THIS IS NOT A STALENESS DETECTOR AND MUST NOT BE READ AS ONE. Nothing here
// can tell you a mirror has drifted: the application cannot execute
// default_permissions_for_role() (EXECUTE revoked from `authenticated` by
// A2.1c step 1a), and pg_proc / pg_policies / pg_constraint are not reachable
// through PostgREST. What it gives you is the DENOMINATOR and the COMMANDS —
// so re-deriving is a mechanical five-minute job rather than an archaeology
// problem, and so a person can see how old the answers are.
//
// PROVED THE SAME DAY IT WAS WRITTEN, which is the argument for it: mirror C
// shipped on 2026-09-05 saying `schedule` was enforced by NOTHING. Track S
// wired it the next morning — 0 sites to 6. The mirror was false within a day,
// nothing in the running application could have noticed, and re-running the
// census is what caught it.
//
// THE RULE: A NEW MIRROR IN THIS FILE GETS AN ENTRY HERE, OR THE COUNT IS A
// LIE. Nothing enforces that — this comment is the enforcement, which is the
// honest description of what it is.
// ===========================================================================
export type MirrorEntry = {
  /** Stable id, used in the UI. */
  id: "A" | "B" | "C" | "D";
  /** The TypeScript constant that holds the copy. */
  constant: string;
  /** The database object it is a copy of. */
  mirrors: string;
  /** Why the application cannot simply read it at runtime. */
  unreachableBecause: string;
  /** ISO date this value was last derived FROM THE LIVE SCHEMA. */
  derivedOn: string;
  /** Paste into the SQL editor to re-derive. Kept executable, not prose. */
  rederive: string;
};

export const MIRRORS: MirrorEntry[] = [
  {
    id: "A",
    constant: "ORG_ROLES",
    mirrors: "CHECK constraint org_members_role_check",
    unreachableBecause:
      "PostgREST exposes `public` only; pg_constraint is not reachable.",
    derivedOn: "2026-09-10",
    rederive: String.raw`select pg_get_constraintdef(oid) from pg_constraint where conname = 'org_members_role_check';`,
  },
  {
    id: "B",
    constant: "MANAGER_ROLES",
    mirrors: "the role list inside is_org_manager()",
    unreachableBecause:
      "is_org_manager() answers only for auth.uid(); it cannot be asked which roles it would accept.",
    derivedOn: "2026-09-10",
    rederive: String.raw`select prosrc from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = 'is_org_manager';`,
  },
  {
    id: "C",
    constant: "ENFORCEMENT",
    mirrors:
      "every has_capability() literal in pg_proc bodies and pg_policies expressions, plus the two thin wrappers",
    unreachableBecause:
      "pg_proc and pg_policies are not reachable through PostgREST.",
    // 2026-09-07: re-derived after a2_3_purchase_orders landed mid-session.
    // ENFORCEMENT itself did not move; what moved is that a TENTH key now has
    // 13 enforcement sites and is not in the derived set at all — see
    // ENFORCED_BUT_UNDERIVED.
    //
    // 2026-09-10: re-derived at the closing check, NO MOVEMENT — the day's
    // migration (po_org_explicit_and_attach) changed function signatures, not
    // any has_capability() literal, and the census confirms it.
    //
    // 2026-09-09: re-derived at the closing check, NO MOVEMENT — same nine
    // counts plus manage_purchasing=13, which joined the derived set the
    // previous evening. All four mirrors were checked; none moved.
    //
    // 2026-09-08: re-derived again, NO MOVEMENT. view_financials=12,
    // view_estimates=10, edit_leads=6, manage_catalog=6, schedule=6,
    // view_master_work_order=5, add_notes=1, create_estimates=1, and
    // view_field absent from the census entirely, which is the 0 it has always
    // been. `derivedOn` advances on a no-change run too: the field records
    // WHEN SOMEONE LAST LOOKED, not when the answer last changed, and a date
    // that only moves on change cannot distinguish "still true" from
    // "nobody has checked since".
    derivedOn: "2026-09-10",
    rederive: String.raw`with fn as (select 'function' kind, proname site, prosrc body from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and proname not in ('has_capability','can_view_financials','can_view_master_work_order')), pol as (select case when permissive = 'RESTRICTIVE' then 'restrictive policy' else 'policy' end, tablename || '.' || policyname, coalesce(qual,'') || ' ' || coalesce(with_check,'') from pg_policies where schemaname = 'public'), s as (select * from fn union all select * from pol), hits as (select kind, site, (regexp_matches(body, 'has_capability\s*\([^,]+,\s*''([a-z_]+)''', 'g'))[1] cap from s union all select kind, site, 'view_financials' from s where body ~ 'can_view_financials' union all select kind, site, 'view_master_work_order' from s where body ~ 'can_view_master_work_order') select cap, kind, count(distinct site) from hits group by 1, 2 order by 1, 2;`,
  },
  {
    id: "D",
    constant: "ROLE_DEFAULTS",
    mirrors:
      "default_permissions_for_role(text), for every role in the CHECK constraint AND for the else branch an unrecognised role reaches",
    unreachableBecause:
      "EXECUTE revoked from `authenticated` by A2.1c step 1a (migration 20260826133457) — deliberately; it is called only from inside the database.",
    derivedOn: "2026-09-10",
    // The trailing 'some_future_role' is not padding. F5 (2026-09-06) changed
    // ONLY the else branch, so a re-derivation limited to the seven named roles
    // reported "unchanged" and was wrong. The probe for the unlisted case is
    // part of the command now.
    rederive: String.raw`select r.role, public.default_permissions_for_role(r.role) from unnest(array['owner','admin','agency_admin','office','member','field','client_portal_viewer','some_future_role']) as r(role);`,
  },
];

/** The number this registry exists to make answerable. */
export const MIRROR_COUNT = MIRRORS.length;

/** The stalest derivation date across all mirrors. */
export function oldestMirrorDerivation(): string {
  return MIRRORS.map((m) => m.derivedOn).sort()[0];
}

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
// ONE OF THE NINE COMES BACK WITH ZERO SITES. `view_field` is derived by the
// deriver, stored on every seeded member row, and consulted by NOTHING — no
// function body, no policy, no RESTRICTIVE policy, and nothing in src/. It is a
// name. The grid says so on its own row rather than drawing a tick that implies
// a control, because a tick beside an unenforced key is the same defect as a
// label standing in for a check.
//
// It was TWO until 2026-09-06. `schedule` was wired that morning and this line
// is only correct because the census was re-run — the count is derived from
// ENFORCEMENT below, so the UI cannot disagree with the data even when this
// prose goes stale.
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
  "manage_purchasing",
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
  manage_purchasing: {
    // Re-derived 2026-09-08 at the closing check. 13 sites since the PO
    // migration; the key joined the DERIVED set the same evening.
    sites: 13,
    summary:
      "6 RPCs + 7 policies across purchase_orders, purchase_order_lines and purchase_order_line_promises. Gates the WRITE path only — reading a purchase order is org-scoped and needs no capability.",
    where: [
      "rpc: create_purchase_order, update_purchase_order, delete_purchase_order",
      "rpc: add_purchase_order_line, update_purchase_order_line, delete_purchase_order_line",
      "policy: purchase_orders (insert/update/delete)",
      "policy: purchase_order_lines (insert/update/delete)",
      "policy: purchase_order_line_promises (insert)",
    ],
  },
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
    // RE-DERIVED 2026-09-06, and it MOVED: 0 sites -> 6. Track S wired it
    // (migration `wire_schedule_capability`) between yesterday's derivation
    // and today's. This is the exact failure this file's registry exists to
    // make visible: the mirror was shipped on 09-05 saying "nothing reads this
    // key", was false within a day, and nothing in the running application
    // could have noticed. It was caught by re-running the census, not by the
    // code.
    sites: 6,
    summary:
      "3 RPCs + 3 policies on schedule_blocks. Wired 2026-09-06; before that this key was derived onto every member row and read by nothing.",
    where: [
      "rpc: add_schedule_block, update_schedule_block, delete_schedule_block",
      "policy: schedule_blocks (insert/update/delete)",
    ],
  },
  view_field: {
    sites: 0,
    summary:
      "NOTHING READS THIS KEY. Field access is decided by modulesVisibleForRole(role) in the app and by org-scoped RLS, neither of which looks at this permission.",
    where: [],
  },
};

// ---------------------------------------------------------------------------
// MIRROR 4 — WHAT EACH ROLE GRANTS WHEN A HUMAN IS ADDED.
//
// Obtained 2026-09-05 by CALLING the live deriver for every role the CHECK
// constraint allows, not by transcribing its body:
//
//   select r.role, public.default_permissions_for_role(r.role)
//     from unnest(array['owner','admin','agency_admin','office','member',
//                       'field','client_portal_viewer']) as r(role);
//
// WHY THIS MIRROR EXISTS WHEN FRIDAY DELIBERATELY REFUSED TO ADD IT.
// Friday's refusal was narrower than it looked: it refused to fill an
// UNOBSERVED GRID CELL with a default, because a cell that reads as an
// observation must not silently become a guess. That still holds and the grid
// still shows an empty dashed circle there. This is a different claim in a
// different place — a reference table, labelled as the deriver's output, never
// mixed into the observed grid.
//
// The trap it exists to close: `office` and `member` are IDENTICAL on eight of
// the nine keys and differ on exactly `manage_catalog`. Nothing anywhere told
// anyone that. An office hire invited as `member` loses the catalog and keeps
// everything else, which is the least visible way for a permission to be wrong.
//
// STALENESS IS THE COST AND IT IS REAL. The app cannot execute
// default_permissions_for_role() (EXECUTE revoked from `authenticated` by
// A2.1c step 1a), so nothing here re-checks itself at runtime. If Track S adds
// a capability or changes a branch, this table is wrong and silent. The fix is
// a definer RPC returning the matrix — reported, not built.
// ---------------------------------------------------------------------------
export const ROLE_DEFAULTS: Record<OrgRole, Record<Capability, boolean>> = {
  owner: {
    manage_purchasing: true, view_financials: true, view_estimates: true, view_master_work_order: true,
    manage_catalog: true, edit_leads: true, create_estimates: true,
    add_notes: true, schedule: true, view_field: true,
  },
  admin: {
    manage_purchasing: true, view_financials: true, view_estimates: true, view_master_work_order: true,
    manage_catalog: true, edit_leads: true, create_estimates: true,
    add_notes: true, schedule: true, view_field: true,
  },
  agency_admin: {
    manage_purchasing: true, view_financials: true, view_estimates: true, view_master_work_order: true,
    manage_catalog: true, edit_leads: true, create_estimates: true,
    add_notes: true, schedule: true, view_field: true,
  },
  office: {
    manage_purchasing: true, view_financials: true, view_estimates: true, view_master_work_order: true,
    manage_catalog: true, edit_leads: false, create_estimates: false,
    add_notes: true, schedule: true, view_field: true,
  },
  member: {
    manage_purchasing: false, view_financials: true, view_estimates: true, view_master_work_order: true,
    manage_catalog: false, edit_leads: false, create_estimates: false,
    add_notes: true, schedule: true, view_field: true,
  },
  field: {
    manage_purchasing: false, view_financials: false, view_estimates: false, view_master_work_order: false,
    manage_catalog: false, edit_leads: false, create_estimates: false,
    add_notes: true, schedule: true, view_field: true,
  },
  client_portal_viewer: {
    manage_purchasing: false, view_financials: false, view_estimates: false, view_master_work_order: false,
    manage_catalog: false, edit_leads: false, create_estimates: false,
    add_notes: true, schedule: true, view_field: true,
  },
};

/**
 * The deriver's ELSE branch — what a role NOT in the CHECK constraint gets.
 *
 * RE-DERIVED 2026-09-06 after migration `f5_unrecognised_role_gets_nothing`
 * landed mid-session, by calling the function with a role the constraint does
 * not allow:
 *
 *   select public.default_permissions_for_role('some_future_role');
 *
 * Nine explicit falses — everything denied, and denied by a written value
 * rather than by an absent key, which are different things everywhere else on
 * this page. Before F5 this branch returned the member-like set (six grants),
 * so an unrecognised role silently inherited most of a member's access.
 *
 * WHY THIS ENTRY EXISTS AT ALL, given the CHECK constraint makes it
 * unreachable today: mirror D would otherwise have reported "unchanged" after
 * F5, because all seven roles it enumerates hit a NAMED branch and none of them
 * moved. The thing F5 changed is the only thing mirror D did not cover. A
 * re-derivation that only checks the cases you already listed cannot find a
 * change to the case you did not.
 */
export const ROLE_DEFAULTS_UNRECOGNISED: Record<Capability, boolean> = {
  manage_purchasing: false, view_financials: false, view_estimates: false, view_master_work_order: false,
  manage_catalog: false, edit_leads: false, create_estimates: false,
  add_notes: false, schedule: false, view_field: false,
};

/** The nine keys as a stable fingerprint, so identical roles can be grouped. */
function fingerprint(role: OrgRole): string {
  return CAPABILITIES.map((c) => (ROLE_DEFAULTS[role][c] ? "1" : "0")).join("");
}

/**
 * Seven roles, four distinct answers. Grouping them is the single most useful
 * thing this data can be turned into: it makes "these two roles are the same"
 * and "these two differ by one key" readable at a glance instead of requiring
 * someone to diff two rows of ticks by eye.
 */
export type RoleGroup = {
  roles: OrgRole[];
  grants: Capability[];
  denies: Capability[];
  /** What this rung drops relative to the one above it, or null for the widest. */
  dropsFromAbove: { roles: OrgRole[]; lost: Capability[]; gained: Capability[] } | null;
  /** False if this rung grants something the wider rung above it does not. */
  nested: boolean;
};

export function roleGroups(): RoleGroup[] {
  // Array of pairs rather than [...map.values()] — the tsconfig target here
  // predates downlevelIteration, so spreading a Map iterator does not compile.
  const groups: { print: string; roles: OrgRole[] }[] = [];
  for (const r of ORG_ROLES) {
    const print = fingerprint(r);
    const existing = groups.find((g) => g.print === print);
    if (existing) existing.roles.push(r);
    else groups.push({ print, roles: [r] });
  }
  const shaped = groups.map(({ roles }) => {
    const head: OrgRole = roles[0];
    return {
      roles,
      grants: CAPABILITIES.filter((c) => ROLE_DEFAULTS[head][c]),
      denies: CAPABILITIES.filter((c) => !ROLE_DEFAULTS[head][c]),
    };
  });

  // Widest first. The four answers turn out to be STRICTLY NESTED — each one
  // grants a subset of the one above it — so ordering them this way makes the
  // set a ladder and lets each rung state what it drops. `nested` is COMPUTED
  // rather than asserted: if Track S ever adds a role that grants something a
  // wider role lacks, the ladder claim stops being made instead of becoming a
  // quietly false sentence.
  shaped.sort((a, b) => b.grants.length - a.grants.length);
  return shaped.map((g, i) => {
    if (i === 0) return { ...g, dropsFromAbove: null, nested: true };
    const above = shaped[i - 1];
    const lost = above.grants.filter((c) => !g.grants.includes(c));
    const gained = g.grants.filter((c) => !above.grants.includes(c));
    return {
      ...g,
      dropsFromAbove: { roles: above.roles, lost, gained },
      nested: gained.length === 0,
    };
  });
}

/**
 * Capabilities on which two roles' defaults disagree. Used to state the
 * office/member trap as a measured difference rather than as a warning
 * somebody remembered to write.
 */
export function defaultsDiff(a: OrgRole, b: OrgRole): Capability[] {
  return CAPABILITIES.filter((c) => ROLE_DEFAULTS[a][c] !== ROLE_DEFAULTS[b][c]);
}

/**
 * How a member's STORED row compares with what their role would grant today.
 *
 * This is the trap's fingerprint. A row written by hand — a direct INSERT, a
 * dashboard edit — does not go through accept_invite() or add_org_member() and
 * therefore never gets seeded. It then looks like a normal member row until
 * somebody tries to do their job.
 */
export type DriftKind = "matches" | "no-keys" | "differs";
export function driftFromRoleDefault(
  role: string,
  permissions: unknown
): { kind: DriftKind; missing: Capability[]; extraTrue: Capability[]; extraFalse: Capability[] } {
  const perms = (permissions ?? {}) as Record<string, unknown>;
  // An unrecognised role used to fall through to "matches", which said the row
  // agreed with a default this file had no value for. F5 gave that branch a
  // real answer, so it is compared like any other.
  const known: Record<Capability, boolean> = ORG_ROLES.includes(role as OrgRole)
    ? ROLE_DEFAULTS[role as OrgRole]
    : ROLE_DEFAULTS_UNRECOGNISED;
  const missing: Capability[] = [];
  const extraTrue: Capability[] = [];
  const extraFalse: Capability[] = [];

  if (Object.keys(perms).length === 0) return { kind: "no-keys", missing: [...CAPABILITIES], extraTrue, extraFalse };

  for (const c of CAPABILITIES) {
    if (!(c in perms)) missing.push(c);
    else if (perms[c] === true && !known[c]) extraTrue.push(c);
    else if (perms[c] !== true && known[c]) extraFalse.push(c);
  }
  const differs = missing.length + extraTrue.length + extraFalse.length > 0;
  return { kind: differs ? "differs" : "matches", missing, extraTrue, extraFalse };
}

/** How many of the nine a role would grant, if the row were seeded properly. */
export function grantedCountForRole(role: string): number {
  // No longer nullable. Since F5 the deriver has a defined answer for an
  // unrecognised role — zero — so returning null would be this file being
  // vaguer than the database.
  if (!ORG_ROLES.includes(role as OrgRole)) {
    return CAPABILITIES.filter((c) => ROLE_DEFAULTS_UNRECOGNISED[c]).length;
  }
  return CAPABILITIES.filter((c) => ROLE_DEFAULTS[role as OrgRole][c]).length;
}

/**
 * ENFORCED BUT NEVER GRANTED — RESOLVED 2026-09-08, and kept as a record of the
 * gap rather than deleted, because the gap is the useful part.
 *
 * For roughly 26 hours the set of capabilities the database ENFORCED and the
 * set `default_permissions_for_role()` EMITS were different sizes.
 * `a2_3_purchase_orders` (20260907230009) introduced `manage_purchasing` and
 * gated 13 objects on it without extending the deriver, so under
 * has_capability()'s closed default only manager tier passed — and they passed
 * through the is_org_manager() short-circuit rather than through any stored
 * key. An `office` member, the role A2.1c deliberately gave `manage_catalog`
 * because "the person who builds estimates maintains the item list", could not
 * create a purchase order.
 *
 * `manage_purchasing_in_deriver` (20260909003438, applied 2026-09-08 20:34 EDT)
 * closed it. Re-derived at the closing check: all seven roles plus the else
 * branch now carry ten keys, `office` is TRUE, and every stored org_members row
 * was backfilled. The two sets are one set again, so `manage_purchasing` is now
 * an ordinary member of CAPABILITIES / ROLE_DEFAULTS / ENFORCEMENT above —
 * added BY RE-DERIVATION, never by hand.
 *
 * WHAT THIS COST, AND WHY THE EMPTY ARRAY STAYS: the state was findable only
 * because the census is re-run rather than read. A mid-session derivation at
 * ~20:45 still reported the key absent; the CLOSING check, two minutes after
 * the migration landed, reported it present. The same day's earlier answer was
 * true when it was taken and false by the end of the session. That is the whole
 * argument for the closing re-derivation being a step rather than a habit.
 *
 * The type and the array survive so the next occurrence has somewhere to go.
 * A capability that is enforced but underived is a real state, it has happened
 * once, and it will happen again the next time a migration adds a key.
 */
export const ENFORCED_BUT_UNDERIVED: {
  key: string;
  sites: number;
  where: string;
  derivedBy: string;
  consequence: string;
  observedOn: string;
  resolvedOn?: string;
}[] = [];

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
