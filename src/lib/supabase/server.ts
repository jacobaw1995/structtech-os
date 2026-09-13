import { cookies } from "next/headers";
import { createServerClient } from "@supabase/ssr";
import type { Database } from "@/lib/supabase/database.types";
import { clientInfoHeaders } from "@/lib/supabase/client-info";
import { boundGetSession, createBoundedFetch } from "@/lib/supabase/bounded-fetch";

/**
 * Server-side Supabase client. Use in Server Components, Server Actions, and
 * Route Handlers only. Always call `supabase.auth.getSession()` before any
 * DB call — `getUser()` alone does not load the session into the client, so
 * PostgREST sends no auth header and `auth.uid()` is null (see CLAUDE.md).
 */
export function createClient() {
  const cookieStore = cookies();

  const client = createServerClient<Database>(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      // Tags every request so our rows are separable from the other tenant's
      // in the shared project's edge log — see client-info.ts. The bounded
      // fetch is here rather than at the 18 getSession() call sites: a silent
      // auth service otherwise hangs every page indefinitely (bounded-fetch.ts).
      global: { ...clientInfoHeaders("server"), fetch: createBoundedFetch() },
      cookies: {
        getAll() {
          return cookieStore.getAll();
        },
        setAll(cookiesToSet) {
          try {
            cookiesToSet.forEach(({ name, value, options }) =>
              cookieStore.set(name, value, options)
            );
          } catch {
            // setAll called from a Server Component — middleware refreshes
            // the session, so this can be safely ignored.
          }
        },
      },
    }
  );

  // Bound the call, not just the socket: a timeout that stays retryable never
  // clears the session or emits SIGNED_OUT, and this race is what lets the
  // request proceed anyway. See bounded-fetch.ts for why both halves are needed.
  //
  // The cookie-write guard that used to sit in setAll is gone on purpose. It
  // existed because the synthetic-400 version made supabase-js clear a live
  // session; the retryable version never does (measured: 0 cookie removals
  // across a 39 s stall). Keeping a guard whose reason no longer exists is how
  // code starts protecting against things nobody can remember.
  boundGetSession(client);
  return client;
}
