import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { signOut } from "@/lib/auth/actions";

// Stub landing page only — the entitlement-driven shell (top bar, tenant
// switcher, sidebar) is Stage 4. This just proves the auth + workspace-select
// flow lands somewhere real, scoped by fetch_organization()'s own
// authorization check (is_platform_admin() or org_id in my_org_ids()).
export default async function WorkspacePage({
  params,
}: {
  params: { orgId: string };
}) {
  const supabase = createClient();
  const {
    data: { session },
  } = await supabase.auth.getSession();

  if (!session) {
    redirect("/login");
  }

  const { data: orgs, error } = await supabase.rpc("fetch_organization", {
    p_org_id: params.orgId,
  });

  if (error) {
    throw error;
  }

  const org = orgs?.[0];

  if (!org) {
    redirect("/select-workspace");
  }

  return (
    <main className="flex min-h-screen flex-col items-center justify-center gap-4 bg-bg px-6 text-center">
      <span className="rounded-full bg-accent-soft px-3 py-1 font-mono text-xs uppercase tracking-wide text-accent-strong">
        Stage 4 builds the real shell here
      </span>
      <h1 className="text-2xl font-semibold text-text">{org.name}</h1>
      <p className="text-sm text-muted">
        {org.tenant_type} workspace · signed in as {session.user.email}
      </p>
      <form action={signOut}>
        <button className="mt-2 rounded-md border border-border px-3 py-2 text-sm text-text">
          Sign out
        </button>
      </form>
    </main>
  );
}
