import { cookies } from "next/headers";
import { createServerClient } from "@supabase/ssr";

// TODO(week 1, schema stage): pass the generated `Database` type once the
// foundation migration lands (`supabase gen types typescript`).

/**
 * Server-side Supabase client. Use in Server Components, Server Actions, and
 * Route Handlers only. Always call `supabase.auth.getSession()` before any
 * DB call — `getUser()` alone does not load the session into the client, so
 * PostgREST sends no auth header and `auth.uid()` is null (see CLAUDE.md).
 */
export function createClient() {
  const cookieStore = cookies();

  return createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
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
}
