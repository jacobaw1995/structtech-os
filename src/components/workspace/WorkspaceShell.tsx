"use client";

import { useEffect, useState } from "react";
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
  // Below the sm breakpoint (640px) the sidebar becomes a slide-out drawer
  // instead of a static flex column — this is its open/closed state.
  // WorkspaceShell lives in the [orgId] layout, so it stays mounted across
  // in-workspace navigations (App Router layout persistence) rather than
  // remounting per page; both the pathname effect and each Link's onClick
  // close the drawer, since a layout that persists needs an explicit close
  // on navigate instead of getting one for free from a remount.
  const [drawerOpen, setDrawerOpen] = useState(false);

  useEffect(() => {
    setDrawerOpen(false);
  }, [pathname]);

  useEffect(() => {
    document.body.style.overflow = drawerOpen ? "hidden" : "";
    return () => {
      document.body.style.overflow = "";
    };
  }, [drawerOpen]);

  // wireframe 2a: switching into a client tenant tints the top bar and adds
  // the "viewing as: agency admin" affordance + a quick way back.
  const isAgencyOperating =
    active.tenant_type === "contractor" && active.role === "agency_admin";
  const homeOrg = orgs.find((o) => o.tenant_type === "internal");

  // Present Mode (Chunk 5) is genuinely full-screen, customer-facing — no
  // sidebar, no topbar, no "viewing as" chrome, nothing that identifies
  // this as an internal tool while a homeowner is looking at it on the
  // tablet. WorkspaceShell lives in the [orgId] layout (wraps EVERY route
  // under /w/[orgId]/*), so this is the one place that can opt a route out
  // of the shell entirely — App Router layouts always wrap their children,
  // there's no per-page "skip my parent's layout" mechanism otherwise.
  if (pathname?.endsWith("/present")) {
    return <>{children}</>;
  }

  return (
    // h-dvh (dynamic viewport height), not h-screen — 100vh doesn't account
    // for mobile browser chrome (iOS Safari's address bar most notably), so
    // h-screen + overflow-hidden here would clip content behind it. dvh
    // tracks the actual visible viewport. overflow-hidden turns this from
    // the previous min-h-screen page-scroll design (every page's whole body
    // grew and scrolled, header included) into a bounded app shell — <main>
    // below is now the one scrollable region, header/sidebar stay in view.
    <div className="flex h-dvh flex-col overflow-hidden bg-bg">
      <header
        className={`flex min-h-14 items-center gap-2 border-b border-border px-3 py-2 sm:min-h-0 sm:gap-3 sm:px-4 ${
          isAgencyOperating ? "bg-accent-soft" : "bg-surface"
        }`}
      >
        {/* Hamburger — mobile only, opens the drawer below the sm
            breakpoint. The sidebar <nav> itself carries the matching
            sm:hidden/sm:static split, so this is the only extra control
            desktop never sees. h-14/w-14 (56dp) makes it the one control
            in this bar sized to the letter of that spec — bell/avatar
            stay their normal small chrome size, matching how even
            Material's own 56dp app bar keeps secondary icons smaller than
            its own height. */}
        <button
          type="button"
          onClick={() => setDrawerOpen(true)}
          aria-label="Open menu"
          className="flex h-14 w-14 shrink-0 items-center justify-center rounded-md text-text sm:hidden"
        >
          <svg viewBox="0 0 20 20" fill="none" className="h-5 w-5">
            <path
              d="M3 5h14M3 10h14M3 15h14"
              stroke="currentColor"
              strokeWidth="1.6"
              strokeLinecap="round"
            />
          </svg>
        </button>

        <Link
          href={`/w/${orgId}`}
          className="flex h-6 w-6 shrink-0 items-center justify-center rounded bg-accent-strong font-mono text-xs font-bold text-white"
        >
          S
        </Link>

        {/* DESKTOP ONLY from 2026-09-03. Below sm the switcher moved out of
            this bar entirely and onto its own full-width row underneath —
            see the <div className="sm:hidden"> immediately after </header>.
            Controller decision 1.2: the tenant you are operating INSIDE is
            the most safety-critical label on this bar, and at 375px in
            agency-admin mode it was truncating to "Broth…". A floor plus
            `truncate` still elides; a row of its own cannot. */}
        <div className="relative hidden sm:block sm:min-w-0">
          <button
            onClick={() => setSwitcherOpen((v) => !v)}
            className={`flex w-auto items-center gap-1.5 rounded-md border px-3 py-1.5 text-sm font-medium ${
              isAgencyOperating
                ? "border-accent text-accent-strong"
                : "border-border text-text"
            }`}
          >
            <span className="shrink-0">▾</span>
            <span className="min-w-0 truncate">{active.org_name}</span>
            {/* "↩ back to X" is a convenience shortcut, not the only way
                home — StructTech is always listed in the dropdown below. */}
            {isAgencyOperating && homeOrg && (
              <span className="shrink-0 whitespace-nowrap text-xs font-normal text-muted">
                ↩ back to {homeOrg.org_name}
              </span>
            )}
          </button>

          {switcherOpen && <SwitcherMenu orgs={orgs} orgId={orgId} onPick={() => setSwitcherOpen(false)} />}
        </div>

        {isAgencyOperating && (
          <span className="shrink-0 whitespace-nowrap rounded-full bg-surface px-1.5 py-0.5 text-[11px] text-accent-strong sm:px-2 sm:text-xs">
            <span className="sm:hidden">agency admin</span>
            <span className="hidden sm:inline">viewing as: agency admin</span>
          </span>
        )}

        <div className="mx-2 hidden max-w-xs flex-1 sm:block">
          <input
            type="search"
            placeholder="Search…"
            disabled
            title="Not built yet"
            className="w-full rounded-full border border-border bg-bg px-3 py-1.5 text-sm text-muted placeholder:text-muted disabled:opacity-60"
          />
        </div>

        {/* The two placeholders below are not built yet and do nothing when
            tapped. Below sm they are dropped entirely rather than shrunk:
            at 320px they were consuming the ~60px that pushed the account
            button — the only route to Sign out — off the right edge of the
            header, so a non-functional control was displacing the one
            control a user cannot do without. They stay on desktop, where
            there is room and they mark where the feature will land. */}
        <div className="ml-auto flex shrink-0 items-center gap-1 sm:gap-3">
          <button
            disabled
            title="Not built yet"
            className="hidden rounded-md bg-accent-strong px-2 py-1.5 text-sm font-medium text-white disabled:opacity-60 sm:inline-block sm:px-3"
          >
            + Add
          </button>
          <button
            disabled
            title="Not built yet"
            aria-label="Notifications"
            className="hidden text-muted disabled:opacity-60 sm:inline-block"
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
              <div className="absolute right-0 top-full z-20 mt-1 w-56 max-w-[85vw] rounded-md border border-border bg-surface py-1 shadow-lg">
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

      {/* MOBILE TENANT ROW — controller decision 1.2 (2026-09-03).
          Full width, its own row, no `truncate` anywhere on the path to the
          name: it wraps to a second line before it elides. `text-left` and
          `break-words` matter — a long tenant name must be readable, not
          tidy. min-h-14 keeps it a 56dp target (§2.4) since it is also the
          switcher. Carries the agency tint so it reads as part of the bar
          above rather than as page content. */}
      <div
        className={`relative border-b border-border px-3 pb-2 sm:hidden ${
          isAgencyOperating ? "bg-accent-soft" : "bg-surface"
        }`}
      >
        <button
          onClick={() => setSwitcherOpen((v) => !v)}
          className={`flex min-h-14 w-full items-center gap-2 rounded-md border px-3 py-2 text-left text-sm font-medium ${
            isAgencyOperating
              ? "border-accent text-accent-strong"
              : "border-border text-text"
          }`}
        >
          <span className="shrink-0">▾</span>
          <span className="min-w-0 break-words">{active.org_name}</span>
        </button>
        {isAgencyOperating && homeOrg && (
          <Link
            href={`/w/${homeOrg.org_id}`}
            className="mt-1 inline-flex min-h-11 items-center text-xs text-muted"
          >
            ↩ back to {homeOrg.org_name}
          </Link>
        )}
        {switcherOpen && <SwitcherMenu orgs={orgs} orgId={orgId} onPick={() => setSwitcherOpen(false)} />}
      </div>

      <div className="flex flex-1 min-h-0">
        {/* Backdrop — mobile only, dismisses the drawer on tap. Doesn't
            exist in the tree at all when closed rather than being
            hidden-but-present, so it can't eat clicks on desktop. */}
        {drawerOpen && (
          <div
            onClick={() => setDrawerOpen(false)}
            aria-hidden="true"
            className="fixed inset-0 z-30 bg-black/40 sm:hidden"
          />
        )}

        {/* Below sm: fixed slide-out drawer, translated off-screen when
            closed. At sm and up: back to the static in-flow sidebar this
            always was — sm:static/sm:translate-x-0/sm:transition-none
            undo every mobile-only rule so the desktop layout is byte-for-
            byte the same as before this change. */}
        <nav
          className={`fixed inset-y-0 left-0 z-40 flex w-72 max-w-[80vw] shrink-0 flex-col gap-1 border-r border-border bg-surface p-3 transition-transform duration-200 ease-out sm:static sm:z-auto sm:w-56 sm:max-w-none sm:translate-x-0 sm:flex-col sm:gap-1 sm:p-3 sm:transition-none ${
            drawerOpen ? "translate-x-0" : "-translate-x-full"
          }`}
        >
          <div className="flex items-center justify-between px-1 pb-2 sm:hidden">
            <span className="text-xs font-semibold uppercase tracking-wide text-muted">
              Menu
            </span>
            <button
              type="button"
              onClick={() => setDrawerOpen(false)}
              aria-label="Close menu"
              className="flex h-14 w-14 items-center justify-center text-muted"
            >
              ✕
            </button>
          </div>

          {visibleModules.map((moduleKey) => {
            const href = `/w/${orgId}/${moduleKey}`;
            const isActive = pathname === href;
            return (
              <Link
                key={moduleKey}
                href={href}
                onClick={() => setDrawerOpen(false)}
                className={`flex min-h-14 items-center rounded-md px-3 text-sm sm:min-h-0 sm:py-2 ${
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
            element past the viewport instead of respecting flex-1. On
            mobile the sidebar is `fixed` (out of flow), so this is already
            full-width there with no extra rule needed. */}
        <main className="min-w-0 flex-1 overflow-y-auto p-4 sm:p-6">{children}</main>
      </div>
    </div>
  );
}

// One menu, two anchors. The switcher renders twice — once in the top bar for
// sm and up, once on the mobile tenant row — and both read the same
// `switcherOpen` state. Only one of the two is ever visible (the other is
// display:none), so factoring the list out is what keeps the two from drifting
// apart the way the "↩ back to X" affordance already had.
function SwitcherMenu({
  orgs,
  orgId,
  onPick,
}: {
  orgs: ActiveMembership[];
  orgId: string;
  onPick: () => void;
}) {
  return (
    <div className="absolute left-3 right-3 top-full z-20 mt-1 rounded-md border border-border bg-surface py-1 shadow-lg sm:left-0 sm:right-auto sm:w-64 sm:max-w-[85vw]">
      {orgs.map((org) => (
        <Link
          key={org.org_id}
          href={`/w/${org.org_id}`}
          onClick={onPick}
          className={`flex min-h-14 flex-col justify-center px-3 py-2 text-sm hover:bg-surface2 sm:min-h-0 ${
            org.org_id === orgId ? "bg-accent-soft" : ""
          }`}
        >
          <span className="font-medium text-text">{org.org_name}</span>
          <span className="text-xs text-muted">
            {org.tenant_type} · {org.role}
          </span>
        </Link>
      ))}
    </div>
  );
}
