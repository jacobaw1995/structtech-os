import { resendSignedCopy } from "@/lib/estimating/actions";
import { RETRYABLE_COPY_STATES, type SignedCopyState } from "@/lib/estimating/signed-copy";

// What happened to the emailed copy after a signature landed. X-W1.14.
// Every state but `sent` opens with "The signature is saved" — the one thing a
// customer and a rep both need to know first, and the thing a failed send must
// never put in doubt. `data-signed-copy` is the contract a check reads.
// The address shown is the estimate's own, passed from the page — never a URL
// value, so a crafted link cannot make this line name someone else.
const COPY: Record<SignedCopyState, (email: string | null) => string> = {
  sent: (email) => `A signed copy has been emailed to ${email ?? "the customer"}.`,
  no_email: () =>
    "The signature is saved. No email address is on this estimate, so no copy was sent — download the PDF and share it.",
  not_configured: () =>
    "The signature is saved. Email isn't set up for this workspace yet, so no copy was sent — download the PDF and share it.",
  rejected: () =>
    "The signature is saved. The email service refused the signed copy, so it was not sent. Check the customer's address, or download the PDF and share it.",
  unavailable: () =>
    "The signature is saved. We couldn't confirm the signed copy was sent — the email service didn't answer. It may still arrive. Sending again within 24 hours won't send a second copy.",
  render_failed: () =>
    "The signature is saved. The signed copy couldn't be prepared, so no email was sent.",
};

export function SignedCopyStatus({
  state,
  email,
  orgId,
  estimateId,
}: {
  state: SignedCopyState;
  email: string | null;
  orgId: string;
  estimateId: string;
}) {
  return (
    <div
      role={state === "sent" ? "status" : "alert"}
      data-signed-copy={state}
      className={`mx-auto mb-4 flex max-w-3xl flex-wrap items-center gap-3 rounded-md px-3 py-2 text-sm text-text ${state === "sent" ? "bg-accent-soft" : "bg-warn-soft"}`}
    >
      <p className="flex-1">{COPY[state](email)}</p>
      {RETRYABLE_COPY_STATES.includes(state) ? (
        <form action={resendSignedCopy}>
          <input type="hidden" name="orgId" value={orgId} />
          <input type="hidden" name="estimateId" value={estimateId} />
          <button
            type="submit"
            className="min-h-11 rounded-md bg-accent-strong px-3 py-2 text-sm font-medium text-white"
          >
            Send again
          </button>
        </form>
      ) : null}
    </div>
  );
}
