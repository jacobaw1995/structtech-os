import { createBrowserClient } from "@supabase/ssr";
import type { Database } from "@/lib/supabase/database.types";
import { clientInfoHeaders } from "@/lib/supabase/client-info";
import { boundGetSessionPerCall, createBrowserBoundedFetch } from "@/lib/supabase/bounded-fetch";

/**
 * Browser-side Supabase client. Use only in Client Components.
 *
 * BOUNDED since 2026-09-22 (bounded-fetch.ts, BROWSER_AUTH_BOUND_MS). Until then
 * this client's auth calls had no limit at all: a person carrying a stale session
 * on a bad connection — a crew member on a roof — would have waited on a refresh
 * that never answered, with nothing to stop it. The server client and the
 * middleware were bounded on 2026-09-11 and 2026-09-12; this one was not, and the
 * record said so plainly.
 *
 * NOTHING IMPORTS THIS FILE TODAY (checked 2026-09-22: zero importers in src/,
 * and scripts/monitor/browser-auth-tripwire.mjs reports 0 browser-capable client
 * paths across 175 files). The bound is therefore protection for the FIRST import,
 * not a fix for a hang anyone is living with — and the tripwire is what will say
 * when that import happens.
 */
export function createClient() {
  const client = createBrowserClient<Database>(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    // See client-info.ts: the shared project's edge log has no tenant column.
    { global: { ...clientInfoHeaders("browser"), fetch: createBrowserBoundedFetch() } }
  );
  boundGetSessionPerCall(client);
  return client;
}
