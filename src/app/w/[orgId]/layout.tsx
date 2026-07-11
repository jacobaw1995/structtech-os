import { getWorkspaceContext } from "@/lib/workspace/context";
import { WorkspaceShell } from "@/components/workspace/WorkspaceShell";

export default async function WorkspaceLayout({
  children,
  params,
}: {
  children: React.ReactNode;
  params: { orgId: string };
}) {
  const ctx = await getWorkspaceContext(params.orgId);

  // Only pass what the shell needs — not the raw session (tokens included).
  const userEmail = ctx.session.user.email ?? ctx.session.user.id;

  return (
    <WorkspaceShell
      orgId={params.orgId}
      active={ctx.active}
      orgs={ctx.orgs}
      visibleModules={ctx.visibleModules}
      userEmail={userEmail}
    >
      {children}
    </WorkspaceShell>
  );
}
