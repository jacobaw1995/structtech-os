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
// THIS IS NOT A STALENESS DETECTOR FOR THE MIRROR THAT REMAINS. B copies
// something still unreachable through PostgREST (pg_proc) and nothing in the
// running app can tell you it has drifted. On 2026-09-12 A and D stopped being
// mirrors at all — they are READ. On 2026-09-14 C was retired by ruling: its
// site counts could not be checked at runtime, so the page stopped showing
// them. What the registry gives you is the DENOMINATOR and the COMMANDS —
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
  id: "B";
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
    id: "B",
    constant: "MANAGER_ROLES",
    mirrors: "the role list inside is_org_manager()",
    unreachableBecause:
      "is_org_manager() answers only for auth.uid(); it cannot be asked which roles it would accept.",
    // KEPT, and why, since the matrix retired its neighbours: the matrix
    // returns what each role is GRANTED, not which roles is_org_manager()
    // short-circuits. A manager's grant and a manager's bypass are different
    // facts — the matrix shows owner=true for every key either way.
    //
    // 2026-09-14: re-derived at the closing check, NO MOVEMENT — the body still
    // reads role in ('owner', 'admin', 'agency_admin').
    derivedOn: "2026-09-14",
    rederive: String.raw`select prosrc from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = 'is_org_manager';`,
  },
];

/** The number this registry exists to make answerable. */
export const MIRROR_COUNT = MIRRORS.length;

/**
 * Mirrors that STOPPED being mirrors, kept so the count's history is legible:
 * "2" means nothing without knowing it was 4.
 */
export const RETIRED_MIRRORS: {
  id: "A" | "C" | "D";
  constant: string;
  retiredOn: string;
  /** What replaced the copy — rendered after "retired <date> ·". */
  resolution: string;
  evidence: string;
}[] = [
  {
    id: "A",
    constant: "ORG_ROLES",
    retiredOn: "2026-09-12",
    resolution: "now read from role_capability_matrix() — its role list",
    evidence:
      "The function body derives roles from pg_get_constraintdef(org_members_role_check), the exact object this mirror copied.",
  },
  {
    id: "D",
    constant: "ROLE_DEFAULTS",
    retiredOn: "2026-09-12",
    resolution: "now read from role_capability_matrix() — its allowed column",
    evidence:
      "The function body reads default_permissions_for_role(role) ->> capability for every pair, and agreed with the deriver on all 70 pairs when checked.",
  },
  {
    id: "C",
    constant: "ENFORCEMENT",
    retiredOn: "2026-09-14",
    resolution: "no longer shown — this page no longer says where, or whether, a capability is checked",
    evidence:
      "It was a hand count of has_capability() references in function bodies and policies, which the application cannot read. A count nothing can check at runtime stopped being rendered as a current fact. The capability key list it was keyed on is still compared with role_capability_matrix() on every render.",
  },
];

/** The stalest derivation date across all mirrors. */
export function oldestMirrorDerivation(): string {
  return MIRRORS.map((m) => m.derivedOn).sort()[0];
}


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
export const MANAGER_ROLES: readonly string[] = ["owner", "admin", "agency_admin"];

export function isManagerRole(role: string): boolean {
  return (MANAGER_ROLES as readonly string[]).includes(role);
}

// ---------------------------------------------------------------------------
// THE CAPABILITY KEYS — and, until 2026-09-14, where each was ENFORCED.
//
// The KEYS below are compared with role_capability_matrix() on every render
// (capabilityDrift), so a key added or removed in the database shows as a
// banner rather than being silently drawn from a stale list.
//
// MIRROR C (`ENFORCEMENT`) IS GONE, BY RULING. It held, per key, a count of the
// function bodies and policies that consult it, a sentence describing them, and
// a "not enforced anywhere" flag for keys that counted zero. Every one of those
// was a copy of pg_proc and pg_policies, which PostgREST does not expose, so the
// page asserted enforcement it could not verify. It was wrong once already
// (`schedule`: shipped 2026-09-05 as read by nothing, wired 2026-09-06) and the
// running application could not have noticed.
//
// Controller ruling, 2026-09-14: THE SURFACE STOPS ASSERTING ENFORCEMENT IT
// CANNOT VERIFY AT RUNTIME. The replacement says what the page cannot see —
// which stays true however the database changes — and nothing about what the
// database does. Incomplete, never wrong. The last census query and its counts
// are in git history before this change; re-run it, do not restore it.
// ---------------------------------------------------------------------------
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

// ---------------------------------------------------------------------------
// RETIRED 2026-09-12 — MIRROR D (`ROLE_DEFAULTS`) AND MIRROR A (`ORG_ROLES`).
//
// Both were copies of things the app could not read. They can be read now:
// `role_capability_matrix()` (migration 20260911233218) is EXECUTE-granted to
// `authenticated` and returns one row per (role, capability, allowed).
//
// It retires TWO, not one, and that was established by reading its body on
// 2026-09-11 rather than by trusting its name: its role list comes from
//   regexp_matches(pg_get_constraintdef(<org_members_role_check>), ...)
// — the CHECK constraint mirror A copied — and its capability list comes from
//   jsonb_object_keys(default_permissions_for_role('owner'))
// — the deriver mirror D copied. It agreed with the deriver on all 70 pairs
// with zero disagreements when checked.
//
// So the role vocabulary and every role's defaults are now READ, per request,
// from the database. What did NOT go away, and why, is in the registry: B (the
// manager short-circuit list) and C (where each capability is enforced) are
// not in the matrix and stay mirrors.
//
// The F5 else branch (`ROLE_DEFAULTS_UNRECOGNISED`) also went. It was a copy
// of the deriver's answer for a role outside the CHECK constraint — a row that
// constraint makes impossible. A role the matrix does not list is now reported
// as UNKNOWN instead of being assumed to get nothing: a sentence this page
// cannot back with a read should not be on it.
// ---------------------------------------------------------------------------

/** A role is whatever the CHECK constraint says it is, read at request time. */
export type OrgRole = string;

export type RoleMatrixRow = { role: string; capability: string; allowed: boolean };

export type RoleMatrix = {
  /** Display order: manager tier first (mirror B), then widest grant first. */
  roles: OrgRole[];
  /** As the deriver emits them. */
  capabilities: string[];
  /** Undefined for a (role, capability) pair the matrix does not contain. */
  allowed: (role: string, capability: string) => boolean | undefined;
  hasRole: (role: string) => boolean;
};

type MatrixClient = {
  rpc: (fn: "role_capability_matrix") => PromiseLike<{
    data: RoleMatrixRow[] | null;
    error: { message: string } | null;
  }>;
};

/**
 * Read the matrix. Called once per request by the page and passed down, so
 * every component on the page answers from the SAME read — two reads could
 * straddle a migration and disagree with each other on one screen.
 */
export async function fetchRoleMatrix(
  supabase: MatrixClient
): Promise<{ matrix: RoleMatrix | null; error: string | null }> {
  const { data, error } = await supabase.rpc("role_capability_matrix");
  if (error) return { matrix: null, error: error.message };
  const rows = (data ?? []) as RoleMatrixRow[];
  if (rows.length === 0) {
    // An empty matrix is not "no roles". It is a read that returned nothing,
    // and building a grid from it would draw a confident empty page.
    return { matrix: null, error: "role_capability_matrix() returned no rows" };
  }
  return { matrix: toMatrix(rows), error: null };
}

export function toMatrix(rows: RoleMatrixRow[]): RoleMatrix {
  // Role and capability names are [a-z_]+ (the CHECK constraint and the
  // deriver's keys), so "|" cannot occur in either and is a safe separator.
  const key = (r: string, c: string) => `${r}|${c}`;
  const table = new Map<string, boolean>();
  const roleSet: string[] = [];
  const capSet: string[] = [];
  for (const row of rows) {
    table.set(key(row.role, row.capability), row.allowed === true);
    if (!roleSet.includes(row.role)) roleSet.push(row.role);
    if (!capSet.includes(row.capability)) capSet.push(row.capability);
  }
  const grants = (r: string) => capSet.filter((c) => table.get(key(r, c)) === true).length;
  const roles = [...roleSet].sort((a, b) => {
    const ma = isManagerRole(a) ? 0 : 1;
    const mb = isManagerRole(b) ? 0 : 1;
    if (ma !== mb) return ma - mb;
    const g = grants(b) - grants(a);
    return g !== 0 ? g : a.localeCompare(b);
  });
  return {
    roles,
    capabilities: capSet,
    allowed: (r, c) => table.get(key(r, c)),
    hasRole: (r) => roleSet.includes(r),
  };
}

/**
 * `CAPABILITIES` IS A HAND-WRITTEN KEY LIST, AND IT IS CHECKED.
 *
 * Before the matrix nothing could notice if a capability was added or removed
 * without this file changing. Now the live list is compared on every render,
 * and a mismatch is shown rather than silently drawn from a stale key set.
 */
export function capabilityDrift(matrix: RoleMatrix): {
  inDatabaseNotInCensus: string[];
  inCensusNotInDatabase: string[];
} {
  return {
    inDatabaseNotInCensus: matrix.capabilities.filter((c) => !isCapability(c)),
    inCensusNotInDatabase: CAPABILITIES.filter((c) => !matrix.capabilities.includes(c)),
  };
}

function fingerprint(matrix: RoleMatrix, role: string): string {
  return CAPABILITIES.map((c) => (matrix.allowed(role, c) ? "1" : "0")).join("");
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

export function roleGroups(matrix: RoleMatrix): RoleGroup[] {
  // Array of pairs rather than [...map.values()] — the tsconfig target here
  // predates downlevelIteration, so spreading a Map iterator does not compile.
  const groups: { print: string; roles: OrgRole[] }[] = [];
  for (const r of matrix.roles) {
    const print = fingerprint(matrix, r);
    const existing = groups.find((g) => g.print === print);
    if (existing) existing.roles.push(r);
    else groups.push({ print, roles: [r] });
  }
  const shaped = groups.map(({ roles }) => {
    const head: OrgRole = roles[0];
    return {
      roles,
      grants: CAPABILITIES.filter((c) => matrix.allowed(head, c) === true),
      denies: CAPABILITIES.filter((c) => matrix.allowed(head, c) !== true),
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
export function defaultsDiff(matrix: RoleMatrix, a: OrgRole, b: OrgRole): Capability[] {
  return CAPABILITIES.filter((c) => matrix.allowed(a, c) !== matrix.allowed(b, c));
}

/**
 * How a member's STORED row compares with what their role would grant today.
 *
 * This is the trap's fingerprint. A row written by hand — a direct INSERT, a
 * dashboard edit — does not go through accept_invite() or add_org_member() and
 * therefore never gets seeded. It then looks like a normal member row until
 * somebody tries to do their job.
 */
export type DriftKind = "matches" | "no-keys" | "differs" | "unknown-role";
export function driftFromRoleDefault(
  matrix: RoleMatrix,
  role: string,
  permissions: unknown
): { kind: DriftKind; missing: Capability[]; extraTrue: Capability[]; extraFalse: Capability[] } {
  const perms = (permissions ?? {}) as Record<string, unknown>;
  // A role the live matrix does not list has no default this page can READ,
  // so it is reported as unknown rather than compared against a guess.
  if (!matrix.hasRole(role)) {
    return { kind: "unknown-role", missing: [], extraTrue: [], extraFalse: [] };
  }
  const missing: Capability[] = [];
  const extraTrue: Capability[] = [];
  const extraFalse: Capability[] = [];

  if (Object.keys(perms).length === 0) return { kind: "no-keys", missing: [...CAPABILITIES], extraTrue, extraFalse };

  for (const c of CAPABILITIES) {
    if (!(c in perms)) missing.push(c);
    else if (perms[c] === true && matrix.allowed(role, c) !== true) extraTrue.push(c);
    else if (perms[c] !== true && matrix.allowed(role, c) === true) extraFalse.push(c);
  }
  const differs = missing.length + extraTrue.length + extraFalse.length > 0;
  return { kind: differs ? "differs" : "matches", missing, extraTrue, extraFalse };
}

/** How many capabilities a role grants, READ from the live matrix. Null if unknown. */
export function grantedCountForRole(matrix: RoleMatrix, role: string): number | null {
  if (!matrix.hasRole(role)) return null;
  return CAPABILITIES.filter((c) => matrix.allowed(role, c) === true).length;
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
 * an ordinary member of CAPABILITIES / ROLE_DEFAULTS / ENFORCEMENT (the last two
 * since retired) —
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
export function buildGrid(
  matrix: RoleMatrix,
  members: Pick<OrgMemberRow, "role" | "permissions">[]
) {
  const byRole = new Map<string, typeof members>();
  for (const m of members) {
    if (!m.role) continue;
    const list = byRole.get(m.role) ?? [];
    list.push(m);
    byRole.set(m.role, list);
  }

  const cells: Cell[] = [];
  for (const capability of CAPABILITIES) {
    for (const role of matrix.roles) {
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

