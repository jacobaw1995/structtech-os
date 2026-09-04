import { createBrowserClient } from "@supabase/ssr";
import type { Database } from "@/lib/supabase/database.types";
import { clientInfoHeaders } from "@/lib/supabase/client-info";

/** Browser-side Supabase client. Use only in Client Components. */
export function createClient() {
  return createBrowserClient<Database>(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    // See client-info.ts: the shared project's edge log has no tenant column.
    { global: clientInfoHeaders("browser") }
  );
}
