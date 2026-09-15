import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";

export default async function Home({
  searchParams,
}: {
  searchParams: { code?: string };
}) {
  // X-W1.14. If a reset link's redirect URL is not on Supabase's Redirect URLs
  // allow-list, GoTrue does not refuse — it silently falls back to the Site URL,
  // i.e. here, with ?code=. Redirecting to /login would drop the code and leave the
  // user at a sign-in page with no explanation. Hand it to the link handler, which
  // owns every named state for it. This app has no other ?code= flow.
  if (searchParams.code) {
    redirect(`/auth/confirm?code=${encodeURIComponent(searchParams.code)}`);
  }

  const supabase = createClient();
  const {
    data: { session },
  } = await supabase.auth.getSession();

  redirect(session ? "/select-workspace" : "/login");
}
