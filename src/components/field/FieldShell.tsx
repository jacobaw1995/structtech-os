"use client";

import { useEffect, useState } from "react";
import Link from "next/link";

// Generalized version of EstimateFlowShell's pattern (single thumb column,
// capped phone width, group-data-[outdoor=true]/field:* CSS variant driven
// by a data-outdoor attribute) — reused by both the Today page (no tabs)
// and the job-detail page (Check-in/Packet tabs). Outdoor defaults OFF
// (CLAUDE.md, updated 7/13 per Jacob) — normal light theme on load, crew
// toggles it on if they need the high-contrast view.
//
// ===========================================================================
// U-W1.4 (2026-09-05) — SCOPE §2.4 AUDIT. Measured at 375x812 against the real
// component, not read off the source. Four of the seven interactive elements
// on a field screen were under the 56dp floor:
//
//     ← Back link ......... 20px    (a bare text link, no padding at all)
//     Outdoor mode ........ 40px
//     Check-in tab ........ 44px
//     Packet tab .......... 44px
//     job cards ....... 75-160px    pass
//
// The 20px back link is the worst of them: it is the primary way out of a job
// and it was the smallest target on the screen, on the one surface whose spec
// says "one-handed, with gloves, in bright sun".
//
// AND THE DEFECT THAT MATTERS MORE THAN ANY OF THEM, proved by navigating
// rather than by reading useState: OUTDOOR MODE DID NOT SURVIVE A TAP.
// FieldShell is rendered per PAGE, not in a layout, so every navigation
// remounted it and `useState(false)` won. Measured: data-outdoor="true" after
// the toggle, data-outdoor="false" after moving to the next field page. A crew
// member in bright sun turned it on, opened a job, and it was gone — every
// time, for the whole day.
// ===========================================================================

const OUTDOOR_KEY = "stos.field.outdoor";

export function FieldShell({
  backHref,
  backLabel,
  tabs,
  children,
}: {
  backHref?: string;
  backLabel?: string;
  tabs?: { label: string; href: string; active: boolean }[];
  children: React.ReactNode;
}) {
  const [outdoor, setOutdoor] = useState(false);

  // localStorage rather than lifting into a field layout. A layout would keep
  // the state across in-app navigations only; this also survives a reload, a
  // phone lock, and closing the browser — which is the actual shape of a work
  // day on a roof. Per-device by design: whether the sun is on YOUR screen is
  // not a fact about the org.
  //
  // Every access is wrapped: Safari private mode and a browser set to block
  // site data both THROW on read, and a field screen must not white-screen
  // because a preference could not be loaded.
  useEffect(() => {
    try {
      if (window.localStorage.getItem(OUTDOOR_KEY) === "1") setOutdoor(true);
    } catch {
      /* storage unavailable — stay on the documented default (off) */
    }
  }, []);

  // Outdoor mode is a DOCUMENT mode, not a panel mode. FieldShell paints itself
  // black, but WorkspaceShell draws the top bar, the tenant row and a 16px
  // padded <main> around it — measured at 375x812 — so before this the
  // high-contrast panel sat inside a bright white frame, which is the opposite
  // of what the mode is for. The attribute goes on <html> and the three chrome
  // surfaces follow it in globals.css.
  //
  // Cleared on unmount, so it cannot leak onto a non-field screen: a crew
  // member has only `field` in their sidebar, but an owner or agency_admin can
  // open the field module and then navigate away, and the app must not stay
  // black because they once tapped this.
  useEffect(() => {
    document.documentElement.dataset.fieldOutdoor = outdoor ? "true" : "false";
    return () => {
      delete document.documentElement.dataset.fieldOutdoor;
    };
  }, [outdoor]);

  function toggleOutdoor() {
    setOutdoor((v) => {
      const next = !v;
      try {
        window.localStorage.setItem(OUTDOOR_KEY, next ? "1" : "0");
      } catch {
        /* the toggle still works for this page view; it just will not persist */
      }
      return next;
    });
  }

  return (
    <div
      data-outdoor={outdoor ? "true" : "false"}
      className={`group/field min-h-full ${outdoor ? "bg-black" : "bg-bg"}`}
    >
      <div className="mx-auto flex max-w-md flex-col gap-4 py-2">
        <div className="flex items-center justify-between gap-2">
          {backHref ? (
            // 56dp, and the negative left margin keeps the LABEL optically
            // aligned with the content below while the TARGET extends past it.
            // A back control that is only as tall as its own text is the
            // easiest thing on the screen to miss with a gloved thumb.
            <Link
              href={backHref}
              className="-ml-3 inline-flex min-h-14 items-center rounded-lg px-3 text-base font-medium text-text group-data-[outdoor=true]/field:text-white"
            >
              {backLabel ?? "← Back"}
            </Link>
          ) : (
            <span />
          )}
          <div className="flex items-center gap-2">
            <ConnectionDot />
            <button
              type="button"
              onClick={toggleOutdoor}
              aria-pressed={outdoor}
              className="inline-flex min-h-14 items-center rounded-full border border-border px-4 text-sm font-medium text-text group-data-[outdoor=true]/field:border-white group-data-[outdoor=true]/field:text-white"
            >
              {outdoor ? "☀ Outdoor" : "Outdoor"}
            </button>
          </div>
        </div>

        {tabs && (
          <div className="flex gap-2">
            {tabs.map((tab) => (
              <Link
                key={tab.label}
                href={tab.href}
                aria-current={tab.active ? "page" : undefined}
                className={`flex min-h-14 flex-1 items-center justify-center rounded-lg text-base font-semibold ${
                  tab.active
                    ? "bg-accent-strong text-white"
                    : "border border-border text-text group-data-[outdoor=true]/field:border-white/40 group-data-[outdoor=true]/field:text-white"
                }`}
              >
                {tab.label}
              </Link>
            ))}
          </div>
        )}

        {children}
      </div>
    </div>
  );
}

/**
 * CONNECTION, NOT SYNC — and the distinction is the whole reason this is worded
 * the way it is.
 *
 * CLAUDE.md calls for sync status (offline / syncing / synced) as a first-class
 * element on every field screen. There is no sync engine: no queue, no outbox,
 * no PowerSync, nothing that could be "syncing". Rendering a green "Synced"
 * badge over a plain fetch would be a name standing in for a control — the
 * failure this project keeps writing rules about — and it would be at its most
 * convincing exactly when it was most wrong, which is when a crew has no signal
 * and their check-in did not save.
 *
 * So this reports the one thing that is actually measurable today:
 * `navigator.onLine` plus the online/offline events. Offline is stated loudly;
 * online is stated quietly, because "you have a connection" is not news. When a
 * real outbox exists this component is where it attaches.
 */
function ConnectionDot() {
  // Starts null and is resolved in an effect: navigator.onLine does not exist
  // during the server render, and guessing "online" would put a wrong claim on
  // screen for a frame.
  const [online, setOnline] = useState<boolean | null>(null);

  useEffect(() => {
    const set = () => setOnline(navigator.onLine);
    set();
    window.addEventListener("online", set);
    window.addEventListener("offline", set);
    return () => {
      window.removeEventListener("online", set);
      window.removeEventListener("offline", set);
    };
  }, []);

  if (online !== false) {
    // Deliberately renders nothing when online or not yet known. A permanent
    // "online" chip trains people to ignore the spot where "offline" appears.
    return null;
  }

  return (
    <span
      role="status"
      className="inline-flex min-h-14 items-center rounded-full bg-warn px-3 text-sm font-semibold text-white"
    >
      Offline
    </span>
  );
}
