import { cookies } from "next/headers";
import { createServerClient } from "@supabase/ssr";
import type { Database } from "@/lib/supabase/database.types";
import { clientInfoHeaders } from "@/lib/supabase/client-info";
import { createBoundedFetch } from "@/lib/supabase/bounded-fetch";

/**
 * Server-side Supabase client. Use in Server Components, Server Actions, and
 * Route Handlers only. Always call `supabase.auth.getSession()` before any
 * DB call — `getUser()` alone does not load the session into the client, so
 * PostgREST sends no auth header and `auth.uid()` is null (see CLAUDE.md).
 */
export function createClient() {
  const cookieStore = cookies();
  const bounded = createBoundedFetch();

  return createServerClient<Database>(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      // Tags every request so our rows are separable from the other tenant's
      // in the shared project's edge log — see client-info.ts. The bounded
      // fetch is here rather than at the 18 getSession() call sites: a silent
      // auth service otherwise hangs every page indefinitely (bounded-fetch.ts).
      global: { ...clientInfoHeaders("server"), fetch: bounded.fetch },
      cookies: {
        getAll() {
          return cookieStore.getAll();
        },
        setAll(cookiesToSet) {
          // A refresh we abandoned on time must not LOG THE USER OUT. The
          // synthetic 400 makes supabase-js clear the session, and writing that
          // through would destroy a session that may still be perfectly valid —
          // turning a slow auth service into a forced re-login. Skipping the
          // write degrades this one request and leaves the cookie for the next.
          if (bounded.timedOut()) return;
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
}
