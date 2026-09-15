import Link from "next/link";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { authGaveUp } from "@/lib/supabase/bounded-fetch";
import { updatePassword } from "@/lib/auth/password-reset";
import { isResetState, TERMINAL_STATES, weakReasons } from "@/lib/auth/reset-states";
import { ResetStateBanner } from "@/components/auth/ResetStateBanner";

export const dynamic = "force-dynamic";

export default async function ResetPasswordPage({
  searchParams,
}: {
  searchParams: { state?: string; reasons?: string };
}) {
  const state = isResetState(searchParams.state) ? searchParams.state : null;

  // States that end or pause the flow render without a session: after a successful
  // reset every session has been signed out, and "the service did not answer" must
  // not be turned into "your link expired" by the absence of one.
  if (state && TERMINAL_STATES.includes(state)) {
    return (
      <Shell>
        <ResetStateBanner state={state} />
        <p className="mt-6 text-sm">
          <Link href="/login" className="text-accent-strong underline">
            Go to sign in
          </Link>
        </p>
      </Shell>
    );
  }

  const supabase = createClient();
  const {
    data: { session },
  } = await supabase.auth.getSession();
  if (!session) {
    if (authGaveUp(supabase)) redirect("/reset-password?state=auth_unreachable");
    redirect("/forgot-password?state=link_expired");
  }

  return (
    <Shell>
      <p className="mt-1 text-sm text-muted">Choose a new password for {session.user.email}.</p>
      {state ? <ResetStateBanner state={state} reasons={weakReasons(searchParams.reasons)} /> : null}
      <form action={updatePassword} className="mt-6 flex flex-col gap-4">
        <div className="flex flex-col gap-1">
          <label htmlFor="password" className="text-sm text-muted">
            New password
          </label>
          <input
            id="password"
            name="password"
            type="password"
            required
            autoComplete="new-password"
            className="min-h-11 rounded-md border border-border bg-bg px-3 py-2 text-sm text-text outline-none focus:border-accent"
          />
        </div>
        <div className="flex flex-col gap-1">
          <label htmlFor="confirm" className="text-sm text-muted">
            New password again
          </label>
          <input
            id="confirm"
            name="confirm"
            type="password"
            required
            autoComplete="new-password"
            className="min-h-11 rounded-md border border-border bg-bg px-3 py-2 text-sm text-text outline-none focus:border-accent"
          />
        </div>
        <button
          type="submit"
          className="mt-2 min-h-11 rounded-md bg-accent-strong px-3 py-2 text-sm font-medium text-white"
        >
          Change password
        </button>
      </form>
    </Shell>
  );
}

function Shell({ children }: { children: React.ReactNode }) {
  return (
    <main className="flex min-h-screen items-center justify-center bg-bg px-6">
      <div className="w-full max-w-sm rounded-lg border border-border bg-surface p-8">
        <h1 className="text-xl font-semibold text-text">Choose a new password</h1>
        {children}
      </div>
    </main>
  );
}
