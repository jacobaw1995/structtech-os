import { failureText, joinNames, type EmailSetup, type SigningState } from "@/lib/signing/remote";

// Office side of remote signing: where the estimate stands, and whether email
// can be sent at all. Every sentence is chosen by a state in lib/signing/remote.ts;
// nothing here decides a state.
//
// NO SEND BUTTON — STOPPED, and why. A send needs two things this branch does not
// have: the signing link (Track S's token model, not landed on 2026-09-14) and
// X's sendEmail() (on track-x, not on main). A button now would offer a write
// nothing can honour (U-W1.6).

export function SignatureStatusPanel({
  state,
  email,
  customerEmail,
}: {
  state: SigningState;
  email: EmailSetup;
  customerEmail: string | null;
}) {
  const closed = state.kind === "signed" || state.kind === "void";

  return (
    <section
      data-signing-state={state.kind}
      data-email-setup={email.configured ? "configured" : "not_configured"}
      className="rounded-lg border border-border bg-surface px-4 py-3"
    >
      <h2 className="text-sm font-semibold text-text">Signature</h2>
      <StateLine state={state} />

      {!closed && (
        <div className="mt-3 flex flex-col gap-1 border-t border-border pt-3 text-xs leading-relaxed">
          {/* SETUP, stated as setup. A different sentence from any failed send. */}
          {email.configured ? (
            <p className="text-muted">The email settings this workspace needs are present.</p>
          ) : (
            <p className="text-[var(--warn-strong)]">
              <span className="font-semibold">Email is not set up yet.</span> Sending for signature needs{" "}
              {joinNames(email.missing)}. That is setup still to be done, not a failed send.
            </p>
          )}
          <p className="text-muted">
            {customerEmail ? (
              <>
                Customer email on this estimate: <span className="text-text">{customerEmail}</span>
              </>
            ) : (
              "This estimate has no customer email."
            )}
          </p>
          <p className="text-muted">
            Sending this estimate for signature is not available yet: the signing link it would email does
            not exist.
          </p>
        </div>
      )}
    </section>
  );
}

function StateLine({ state }: { state: SigningState }) {
  switch (state.kind) {
    case "signed":
      return (
        <p className="mt-1 text-sm text-text">
          Signed{state.signerName ? ` by ${state.signerName}` : ""} on <Day iso={state.signedAt} />.
        </p>
      );
    case "void":
      return <p className="mt-1 text-sm text-muted">This estimate is void.</p>;
    case "no_send_record_source":
      return (
        <p className="mt-1 text-sm text-text">
          Not signed. Whether it has been sent for signature cannot be shown — this system does not keep a
          record of sends yet.
        </p>
      );
    case "not_sent":
      return <p className="mt-1 text-sm text-text">Not signed, and not sent for signature.</p>;
    case "send_failed": {
      const t = failureText(state.failure);
      return (
        <div className="mt-1">
          <p className="text-sm font-semibold text-[var(--warn-strong)]">{t.headline}</p>
          <p className="text-xs leading-relaxed text-text">{t.detail}</p>
          <p className="text-xs text-muted">
            Tried <Day iso={state.attempt.attemptedAt} /> to {state.attempt.to}.
          </p>
        </div>
      );
    }
    case "awaiting":
      return (
        <div className="mt-1">
          <p className="text-sm text-text">
            Sent to {state.attempt.to} on <Day iso={state.attempt.attemptedAt} />, awaiting signature.
          </p>
          {/* Opens are said only when they are tracked. */}
          {state.opened === "opened" && state.attempt.openedAt && (
            <p className="text-xs text-muted">
              The link was opened on <Day iso={state.attempt.openedAt} />.
            </p>
          )}
          {state.opened === "not_opened" && <p className="text-xs text-muted">The link has not been opened.</p>}
          <p className="text-xs text-muted">
            {state.attempt.expiresAt ? (
              <>
                The link expires on <Day iso={state.attempt.expiresAt} />.
              </>
            ) : (
              "The link does not expire."
            )}
          </p>
        </div>
      );
    case "link_expired":
      return (
        <p className="mt-1 text-sm text-[var(--warn-strong)]">
          Sent to {state.attempt.to} on <Day iso={state.attempt.attemptedAt} />. The link expired on{" "}
          <Day iso={state.attempt.expiresAt as string} /> without being signed.
        </p>
      );
  }
}

function Day({ iso }: { iso: string }) {
  return (
    <span className="whitespace-nowrap font-mono tabular-nums">
      {new Date(iso).toLocaleDateString("en-CA", { timeZone: "America/New_York" })}
    </span>
  );
}
