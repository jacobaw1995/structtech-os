import { createBrowserClient } from "@supabase/ssr";

// TODO(week 1, schema stage): pass the generated `Database` type once the
// foundation migration lands.

/** Browser-side Supabase client. Use only in Client Components. */
export function createClient() {
  return createBrowserClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!
  );
}
