"use client";

import { useState } from "react";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { signOut } from "@/lib/auth/actions";
import {
  moduleLabel,
  type ActiveMembership,
  type ModuleKey,
} from "@/lib/workspace/modules";

export function WorkspaceShell({
  orgId,
  active,
  orgs,
  visibleModules,
  userEmail,
  children,
}: {
  orgId: string;
  active: ActiveMembership;
  orgs: ActiveMembership[];
  visibleModules: ModuleKey[];
  userEmail: string;
  children: React.ReactNode;
}) {
  const pathname = usePathname();
  const [switcherOpen, setSwitcherOpen] = useState(false);
  const [userMenuOpen, setUserMenuOpen] = useState(false);

  // wireframe 2a: switching into a client tenant tints the top bar and adds
  // the "viewing as: agency admin" affordance + a quick way back.
  const isAgencyOperating =
    active.tenant_type === "contractor" && active.role === "agency_admin";
  const homeOrg = orgs.find((o) => o.tenant_type === "internal");

  return (
    <div className="flex min-h-screen flex-col bg-bg">
      <header
        className={`flex items-center gap-3 border-b border-border px-4 py-2 ${
          isAgencyOperating ? "bg-accent-soft" : "bg-surface"
        }`}
      >
        <Link
          href={`/w/${orgId}`}
          className="flex h-6 w-6 shrink-0 items-center justify-center rounded bg-accent-strong font-mono text-xs font-bold text-white"
        >
          S
        </Link>

        <div className="relative">
          <button
            onClick={() => setSwitcherOpen((v) => !v)}
            className={`flex items-center gap-1.5 rounded-md border px-3 py-1.5 text-sm font-medium ${
              isAgencyOperating
                ? "border-accent text-accent-strong"
                : "border-border text-text"
            }`}
          >
            <span>▾</span>
            <span>{active.org_name}</span>
            {isAgencyOperating && homeOrg && (
              <span className="text-xs font-normal text-muted">
                ↩ back to {homeOrg.org_name}
              </span>
            )}
          </button>

          {switcherOpen && (
            <div className="absolute left-0 top-full z-10 mt-1 w-64 rounded-md border border-border bg-surface py-1 shadow-lg">
              {orgs.map((org) => (
                <Link
                  key={org.org_id}
                  href={`/w/${org.org_id}`}
                  onClick={() => setSwitcherOpen(false)}
                  className={`flex flex-col px-3 py-2 text-sm hover:bg-surface2 ${
                    org.org_id === orgId ? "bg-accent-soft" : ""
                  }`}
                >
                  <span className="font-medium text-text">
                    {org.org_name}
                  </span>
                  <span className="text-xs text-muted">
                    {org.tenant_type} · {org.role}
                  </span>
                </Link>
              ))}
            </div>
          )}
        </div>

        {isAgencyOperating && (
          <span className="rounded-full bg-surface px-2 py-0.5 text-xs text-accent-strong">
            viewing as: agency admin
          </span>
        )}

        <div className="mx-2 hidden max-w-xs flex-1 sm:block">
          <input
            type="search"
            placeholder="Search…"
            disabled
            title="Coming in Week 2+"
            className="w-full rounded-full border border-border bg-bg px-3 py-1.5 text-sm text-muted placeholder:text-muted disabled:opacity-60"
          />
        </div>

        <div className="ml-auto flex items-center gap-3">
          <button
            disabled
            title="Coming in Week 2+"
            className="rounded-md bg-accent-strong px-3 py-1.5 text-sm font-medium text-white disabled:opacity-60"
          >
            + Add
          </button>
          <button
            disabled
            title="Coming in Week 2+"
            aria-label="Notifications"
            className="text-muted disabled:opacity-60"
          >
            🔔
          </button>

          <div className="relative">
            <button
              onClick={() => setUserMenuOpen((v) => !v)}
              aria-label="Account menu"
              className="flex h-7 w-7 items-center justify-center rounded-full bg-surface2 text-xs font-medium text-text"
            >
              {userEmail.slice(0, 1).toUpperCase()}
            </button>
            {userMenuOpen && (
              <div className="absolute right-0 top-full z-10 mt-1 w-56 rounded-md border border-border bg-surface py-1 shadow-lg">
                <div className="border-b border-border px-3 py-2 text-xs text-muted">
                  {userEmail}
                </div>
                <form action={signOut}>
                  <button className="w-full px-3 py-2 text-left text-sm text-text hover:bg-surface2">
                    Sign out
                  </button>
                </form>
              </div>
            )}
          </div>
        </div>
      </header>

      <div className="flex flex-1">
        <nav className="flex w-56 shrink-0 flex-col gap-1 border-r border-border bg-surface p-3">
          {visibleModules.map((moduleKey) => {
            const href = `/w/${orgId}/${moduleKey}`;
            const isActive = pathname === href;
            return (
              <Link
                key={moduleKey}
                href={href}
                className={`rounded-md px-3 py-2 text-sm ${
                  isActive
                    ? "bg-accent-soft font-medium text-accent-strong"
                    : "text-text hover:bg-surface2"
                }`}
              >
                {moduleLabel(moduleKey, active.tenant_type)}
              </Link>
            );
          })}
        </nav>

        {/* min-w-0 is load-bearing: a flex item defaults to min-width:auto,
            which refuses to shrink below its content's intrinsic width. Any
            module page wide enough to need its own horizontal scroll (the
            crm board, first to hit this) would otherwise force this whole
            element past the viewport instead of respecting flex-1. */}
        <main className="min-w-0 flex-1 p-6">{children}</main>
      </div>
    </div>
  );
}
