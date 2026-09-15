import Link from "next/link";
import { requestPasswordReset } from "@/lib/auth/password-reset";
import { authEmailEnabled, isResetState } from "@/lib/auth/reset-states";
import { ResetStateBanner } from "@/components/auth/ResetStateBanner";

export const dynamic = "force-dynamic";

export default function ForgotPasswordPage({
  searchParams,
}: {
  searchParams: { state?: string };
}) {
  // "off" is decided here from configuration, not only after a submit, so nobody
  // types their address into a form that cannot send anything.
  const enabled = authEmailEnabled();
  const state = !enabled ? "off" : isResetState(searchParams.state) ? searchParams.state : null;

  return (
    <main className="flex min-h-screen items-center justify-center bg-bg px-6">
      <div className="w-full max-w-sm rounded-lg border border-border bg-surface p-8">
        <h1 className="text-xl font-semibold text-text">Reset your password</h1>
        <p className="mt-1 text-sm text-muted">
          We&apos;ll email you a link to choose a new one.
        </p>

        {state ? <ResetStateBanner state={state} /> : null}

        {enabled ? (
          <form action={requestPasswordReset} className="mt-6 flex flex-col gap-4">
            <div className="flex flex-col gap-1">
              <label htmlFor="email" className="text-sm text-muted">
                Email
              </label>
              <input
                id="email"
                name="email"
                type="email"
                required
                autoComplete="email"
                className="min-h-11 rounded-md border border-border bg-bg px-3 py-2 text-sm text-text outline-none focus:border-accent"
              />
            </div>
            <button
              type="submit"
              className="mt-2 min-h-11 rounded-md bg-accent-strong px-3 py-2 text-sm font-medium text-white"
            >
              Email me a reset link
            </button>
          </form>
        ) : null}

        <p className="mt-6 text-sm">
          <Link href="/login" className="text-accent-strong underline">
            Back to sign in
          </Link>
        </p>
      </div>
    </main>
  );
}
