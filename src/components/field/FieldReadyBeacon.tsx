"use client";

import { useEffect } from "react";

// Tells the server the job page became usable on this phone, and how long it took.
// X-W1.19. A page the server rendered (work_order_opened) with no matching page_ready
// is a load that failed or was abandoned — the one failure that otherwise leaves no
// trace once the one-hour runtime log rolls over.
//
// Offline on a roof: the beacon cannot leave, so it is queued in localStorage (at
// most 20, dropped after 2 days) and sent with the next page that loads online,
// marked as sent late. Everything here is wrapped: telemetry never breaks the page.
const KEY = "structtech.field-events.queue";
type Item = { url: string; body: string; at: number };

function send(url: string, body: string): boolean {
  try {
    if (typeof navigator !== "undefined" && navigator.onLine === false) return false;
    return navigator.sendBeacon(url, new Blob([body], { type: "application/json" }));
  } catch {
    return false;
  }
}

function readQueue(): Item[] {
  try {
    const raw = JSON.parse(localStorage.getItem(KEY) ?? "[]");
    return Array.isArray(raw) ? raw.filter((i) => Date.now() - i.at < 2 * 86_400_000).slice(-20) : [];
  } catch {
    return [];
  }
}
function writeQueue(items: Item[]) {
  try {
    localStorage.setItem(KEY, JSON.stringify(items.slice(-20)));
  } catch {
    /* storage blocked: the event is lost, the page is not */
  }
}

export function FieldReadyBeacon({ orgId, workOrderId }: { orgId: string; workOrderId: string }) {
  useEffect(() => {
    const url = `/w/${orgId}/field/${workOrderId}/events`;
    const body = JSON.stringify({
      event: "page_ready",
      durationMs: Math.round(performance.now()),
      clientSentAt: new Date().toISOString(),
    });
    const pending = readQueue();
    const stillPending = pending.filter(
      (i) => !send(i.url, JSON.stringify({ ...JSON.parse(i.body), queued: true }))
    );
    if (!send(url, body)) stillPending.push({ url, body, at: Date.now() });
    writeQueue(stillPending);
  }, [orgId, workOrderId]);
  return null;
}
