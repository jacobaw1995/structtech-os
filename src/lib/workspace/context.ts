import { cache } from "react";
import { redirect } from "next/navigation";
import type { Session } from "@supabase/supabase-js";
import { createClient } from "@/lib/supabase/server";
import {
  isModuleKey,
  modulesVisibleForRole,
  isActiveMembership,
  type ModuleKey,
  type ActiveMembership,
} from "@/lib/workspace/modules";

// Server-only (imports next/headers transitively via @/lib/supabase/server)
// — never import this from a Client Component. Client-safe pieces
// (moduleLabel, ModuleKey, ActiveMembership, ...) live in ./modules.

export type WorkspaceContext = {
  session: Session;
  orgs: ActiveMembership[];
  active: ActiveMembership;
  visibleModules: ModuleKey[];
};

/**
 * Server-side guard, not just nav-hiding: every module route calls this (via
 * requireModuleAccess) or its own membership-scoped fetch. Wrapped in
 * React's cache() so the layout and the page it wraps share one
 * fetch_membership_context() round trip per request instead of two.
 */
export const getWorkspaceContext = cache(
  async (orgId: string): Promise<WorkspaceContext> => {
    const supabase = createClient();
    const {
      data: { session },
    } = await supabase.auth.getSession();

    if (!session) {
      redirect("/login");
    }

    const { data: memberships, error } = await supabase.rpc(
      "fetch_membership_context"
    );

    if (error) {
      throw error;
    }

    const orgs = (memberships ?? []).filter(isActiveMembership);
    const active = orgs.find((m) => m.org_id === orgId);

    if (!active) {
      redirect("/select-workspace");
    }

    const visibleModules = modulesVisibleForRole(
      active.role,
      active.entitled_modules ?? []
    );

    return { session, orgs, active, visibleModules };
  }
);

/**
 * Per-module guard: entitlement (is this module even in the org's
 * fetch_membership_context() output) x role (modulesVisibleForRole) both
 * have to pass, enforced here server-side — not by which links happen to be
 * rendered in the sidebar.
 */
export async function requireModuleAccess(
  orgId: string,
  moduleKey: string
): Promise<WorkspaceContext & { moduleKey: ModuleKey }> {
  const ctx = await getWorkspaceContext(orgId);

  if (!isModuleKey(moduleKey) || !ctx.visibleModules.includes(moduleKey)) {
    redirect(`/w/${orgId}`);
  }

  return { ...ctx, moduleKey };
}
