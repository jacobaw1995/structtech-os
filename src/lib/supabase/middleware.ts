import { createServerClient } from "@supabase/ssr";
import { clientInfoHeaders } from "@/lib/supabase/client-info";
import { createBoundedFetch } from "@/lib/supabase/bounded-fetch";
import { NextResponse, type NextRequest } from "next/server";

/**
 * Refreshes the Supabase session cookie on every request. Called from
 * `middleware.ts`. This does not do route-guarding itself — that lives in
 * per-route/layout checks so entitlement + role logic stays close to the
 * screens it protects.
 */
export async function updateSession(request: NextRequest) {
  let supabaseResponse = NextResponse.next({ request });
  const bounded = createBoundedFetch();

  const supabase = createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      // See client-info.ts: the shared project's edge log has no tenant column.
      // Bounded fetch: see bounded-fetch.ts — without it a silent auth service
      // blocks this middleware, and therefore every matched route, forever.
      global: { ...clientInfoHeaders("middleware"), fetch: bounded.fetch },
      cookies: {
        getAll() {
          return request.cookies.getAll();
        },
        setAll(cookiesToSet) {
          // See server.ts: an abandoned refresh must not clear a live session.
          if (bounded.timedOut()) return;
          cookiesToSet.forEach(({ name, value }) =>
            request.cookies.set(name, value)
          );
          supabaseResponse = NextResponse.next({ request });
          cookiesToSet.forEach(({ name, value, options }) =>
            supabaseResponse.cookies.set(name, value, options)
          );
        },
      },
    }
  );

  // Required: this triggers a token refresh if the session is stale, and
  // must run before any route-guard logic reads the session.
  await supabase.auth.getSession();

  return supabaseResponse;
}
