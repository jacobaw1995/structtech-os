import type { Database } from "@/lib/supabase/database.types";

// Client-safe: no server-only imports. Pure module metadata + role logic,
// shared between server guards (context.ts) and client UI (WorkspaceShell).

// Order also drives sidebar order.
export const MODULE_ORDER = [
  "crm",
  "estimating",
  "coordination",
  "field",
  "delivery",
  "scan",
  "roadmap",
  "tracker",
  "build",
] as const;

export type ModuleKey = (typeof MODULE_ORDER)[number];

export function isModuleKey(value: string): value is ModuleKey {
  return (MODULE_ORDER as readonly string[]).includes(value);
}

const MODULE_LABELS: Record<ModuleKey, string> = {
  crm: "Pipeline",
  estimating: "Estimating",
  coordination: "Coordination",
  field: "Field",
  delivery: "Delivery",
  scan: "Scan",
  roadmap: "Roadmap",
  tracker: "Tracker",
  build: "Build",
};

/**
 * SCOPE.md §3: delivery is StructTech's own admin view internally, but
 * surfaces read-only inside a client tenant as "StructTech Roadmap".
 */
export function moduleLabel(
  moduleKey: ModuleKey,
  tenantType: string | null
): string {
  if (moduleKey === "delivery" && tenantType === "contractor") {
    return "StructTech Roadmap";
  }
  return MODULE_LABELS[moduleKey];
}

/**
 * Second access axis (SCOPE.md §2/§5): tenant entitlements x role. owner /
 * admin / agency_admin see everything the org is entitled to (agency_admin
 * is a StructTech operator who needs to actually run the client's modules,
 * not a spectator). office / field / client_portal_viewer are scoped to
 * their slice. Unrecognized or legacy roles (including 'member') default to
 * the narrowest read — crm only — rather than failing open.
 */
export function modulesVisibleForRole(
  role: string | null,
  entitled: string[]
): ModuleKey[] {
  // fetch_membership_context()'s array_agg has no ORDER BY, so entitled's
  // order isn't guaranteed — re-sort to MODULE_ORDER so the sidebar has a
  // stable, intentional order regardless of what Postgres happens to return.
  const entitledKeys = MODULE_ORDER.filter((m) => entitled.includes(m));

  switch (role) {
    case "owner":
    case "admin":
    case "agency_admin":
      return entitledKeys;
    case "office":
      return entitledKeys.filter(
        (m) => m === "crm" || m === "estimating" || m === "coordination"
      );
    case "field":
      return entitledKeys.filter((m) => m === "field");
    case "client_portal_viewer":
      return entitledKeys.filter((m) => m === "delivery");
    default:
      return entitledKeys.filter((m) => m === "crm");
  }
}

type MembershipRow = Database["public"]["CompositeTypes"]["membership_context"];

export type ActiveMembership = MembershipRow & {
  org_id: string;
  org_name: string;
  tenant_type: string;
  role: string;
};

export function isActiveMembership(m: MembershipRow): m is ActiveMembership {
  return (
    m.org_id != null &&
    m.org_name != null &&
    m.tenant_type != null &&
    m.role != null
  );
}
