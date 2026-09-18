import { sendForSignature } from "@/lib/signing/send-actions";
import {
  LINK_VALID_DAYS,
  SEND_RESULT_COPY,
  type SendResult,
  type SigningState,
} from "@/lib/signing/remote";

// Office side of remote signing (U-W1.15, button U-W1.19): where the estimate
// stands, the one-time result of the last send, and the send control. Every
// sentence is chosen by a state or a code in lib/signing/remote.ts.
//
// NO PRE-SEND EMAIL CLAIM. The hand-copied environment check that used to say
// "email is not set up" before anything was sent is gone. Track X's send.ts
// exports no setup check, and a second copy of its rule could disagree with it.
// "Email is not set up" is now said when a real send returns not_configured —
// from X's own function — and never otherwise.

export function SignatureStatusPanel({
  orgId,
  estimateId,
  state,
  result,
  customerEmail,
  canSend,
}: {
  orgId: string;
  estimateId: string;
  state: SigningState;
  /** From `?send=` — already checked against the code map by the page. */
  result: SendResult | null;
  customerEmail: string | null;
  /** has_capability(create_estimates) AND can_view_financials — what the link function requires. */
  canSend: boolean;
}) {
  const sendable = state.kind === "not_sent" || state.kind === "awaiting" || state.kind === "link_expired" || state.kind === "link_cancelled";
  const flash = result ? SEND_RESULT_COPY[result] : null;

  return (
    <section
      id="signature"
      data-signing-state={state.kind}
      data-send-result={result ?? ""}
      className="scroll-mt-4 rounded-lg border border-border bg-surface px-4 py-3"
    >
      <h2 className="text-sm font-semibold text-text">Signature</h2>

      {flash && (
        <div
          role="status"
          className={`mt-2 rounded-md px-3 py-2 ${flash.tone === "ok" ? "bg-accent-soft" : "border border-warn bg-warn-soft"}`}
        >
          <p className="text-sm font-semibold text-text">{flash.headline}</p>
          <p className="text-xs leading-relaxed text-text">{flash.detail}</p>
        </div>
      )}

      <StateLine state={state} unconfirmed={result === "cancel_failed"} />

      {sendable &&
        (!canSend ? (
          <p className="mt-2 text-xs text-muted">Your role cannot send estimates for signature in this workspace.</p>
        ) : !customerEmail ? (
          <p className="mt-2 text-xs text-[var(--warn-strong)]">
            This estimate has no customer email address, so it cannot be sent for signature. Add one to the estimate.
          </p>
        ) : (
          <form action={sendForSignature} className="mt-3 flex flex-col gap-1 sm:flex-row sm:items-center sm:gap-3">
            <input type="hidden" name="orgId" value={orgId} />
            <input type="hidden" name="estimateId" value={estimateId} />
            <button
              type="submit"
              className="flex min-h-14 items-center justify-center rounded-md bg-accent-strong px-4 text-sm font-semibold text-white sm:min-h-10"
            >
              {state.kind === "not_sent" ? "Send for signature" : "Send a new signing link"}
            </button>
            <p className="text-xs text-muted">
              To <span className="text-text">{customerEmail}</span> · the link works for {LINK_VALID_DAYS} days
              {state.kind === "awaiting" ? " · the link already sent stops working" : ""}.
            </p>
          </form>
        ))}
    </section>
  );
}

function StateLine({ state, unconfirmed }: { state: SigningState; unconfirmed: boolean }) {
  switch (state.kind) {
    case "signed":
      return (
        <p className="mt-1 text-sm text-text">
          Signed{state.signerName ? ` by ${state.signerName}` : ""} on <Day iso={state.signedAt} />
          {state.viaLink ? ", through the emailed link." : "."}
        </p>
      );
    case "void":
      return <p className="mt-1 text-sm text-muted">This estimate is void.</p>;
    case "not_presented":
      return (
        <p className="mt-1 text-sm text-muted">
          Not signed. An estimate can be sent for signature once it is presented.
        </p>
      );
    case "unreadable":
      return (
        <p className="mt-1 text-sm text-[var(--warn-strong)]">
          Not signed. Whether a signing link was sent could not be read just now — reload before sending again.
        </p>
      );
    case "not_sent":
      return <p className="mt-1 text-sm text-text">Not signed, and not sent for signature.</p>;
    case "awaiting":
      // Right after a failed send whose link could not be cancelled, the live link
      // is NOT a sent one — the one case "live means sent" does not hold.
      if (unconfirmed) {
        return (
          <p className="mt-1 text-sm text-[var(--warn-strong)]">
            Not signed. A signing link created <Day iso={state.link.created_at} /> is live but was not confirmed sent.
          </p>
        );
      }
      return (
        <p className="mt-1 text-sm text-text">
          Sent for signature on <Day iso={state.link.created_at} />, not signed yet. The link works until{" "}
          <Day iso={state.link.expires_at} />.
        </p>
      );
    case "link_expired":
      return (
        <p className="mt-1 text-sm text-[var(--warn-strong)]">
          Sent on <Day iso={state.link.created_at} />. The link expired on <Day iso={state.link.expires_at} /> without
          being signed.
        </p>
      );
    case "link_cancelled":
      return (
        <p className="mt-1 text-sm text-text">
          Not signed. The last signing link, created <Day iso={state.link.created_at} />, was cancelled
          {state.link.revoked_at ? (
            <>
              {" "}
              on <Day iso={state.link.revoked_at} />
            </>
          ) : null}
          . It cannot be signed.
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
