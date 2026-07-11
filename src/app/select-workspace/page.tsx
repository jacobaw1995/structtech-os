import Link from "next/link";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { signOut } from "@/lib/auth/actions";

export default async function SelectWorkspacePage() {
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

  type Membership = NonNullable<typeof memberships>[number];

  const orgs = (memberships ?? []).filter(
    (m): m is Membership & { org_id: string } => m.org_id != null
  );

  // Single workspace: skip the picker entirely.
  if (orgs.length === 1) {
    redirect(`/w/${orgs[0].org_id}`);
  }

  // No membership rows at all: authenticated, but nothing to land in.
  if (orgs.length === 0) {
    return (
      <main className="flex min-h-screen flex-col items-center justify-center gap-4 bg-bg px-6 text-center">
        <h1 className="text-xl font-semibold text-text">
          No workspace access yet
        </h1>
        <p className="max-w-sm text-sm text-muted">
          {session.user.email} isn&apos;t a member of any organization yet.
          Ask a platform admin to add you.
        </p>
        <form action={signOut}>
          <button className="rounded-md border border-border px-3 py-2 text-sm text-text">
            Sign out
          </button>
        </form>
      </main>
    );
  }

  // Multiple workspaces: the picker (wireframe 2h).
  return (
    <main className="flex min-h-screen flex-col items-center justify-center gap-6 bg-bg px-6">
      <div className="flex flex-col items-center gap-1 text-center">
        <h1 className="text-xl font-semibold text-text">
          Choose a workspace
        </h1>
        <p className="text-sm text-muted">{session.user.email}</p>
      </div>

      <div className="flex w-full max-w-sm flex-col gap-3">
        {orgs.map((org) => (
          <Link
            key={org.org_id}
            href={`/w/${org.org_id}`}
            className="flex items-center justify-between rounded-lg border border-border bg-surface px-4 py-3 transition-colors hover:border-accent"
          >
            <div>
              <div className="text-sm font-medium text-text">
                {org.org_name ?? "Unnamed workspace"}
              </div>
              <div className="text-xs text-muted">
                {org.tenant_type ?? "unknown"} · {org.role ?? "unknown role"}
              </div>
            </div>
          </Link>
        ))}
      </div>

      <form action={signOut}>
        <button className="text-sm text-muted underline">Sign out</button>
      </form>
    </main>
  );
}
