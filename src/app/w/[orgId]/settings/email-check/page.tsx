import { getWorkspaceContext } from "@/lib/workspace/context";
import { emailSetup } from "@/lib/email/send";
import { sendEmailCheck } from "@/lib/email/email-check";

export const dynamic = "force-dynamic";

// X-W1.17 — see src/lib/email/email-check.ts. `?result=` is a code looked up
// below; an unknown code renders nothing.
const RESULT: Record<string, { tone: "info" | "warn"; text: string }> = {
  sent: {
    tone: "info",
    text: "Sent. Email accepted it — check your inbox (and spam). Accepted is not delivered: it only counts once it arrives.",
  },
  not_configured: { tone: "warn", text: "Email isn't set up on this deployment, so nothing was sent." },
  rejected: { tone: "warn", text: "The email service refused the message. Nothing was sent." },
  unavailable: {
    tone: "warn",
    text: "The email service didn't answer in time, so we can't confirm it was sent. It may still arrive.",
  },
  not_allowed: { tone: "warn", text: "Only a workspace owner or admin can run the email check." },
  no_address: { tone: "warn", text: "Your account has no email address to send the check to." },
};

export default async function EmailCheckPage({
  params,
  searchParams,
}: {
  params: { orgId: string };
  searchParams: { result?: string };
}) {
  const ctx = await getWorkspaceContext(params.orgId);
  const setup = emailSetup();
  const result = searchParams.result && Object.prototype.hasOwnProperty.call(RESULT, searchParams.result)
    ? RESULT[searchParams.result]
    : null;

  return (
    <div className="mx-auto flex max-w-xl flex-col gap-4 px-4 py-6">
      <h1 className="text-xl font-semibold text-text">Email check</h1>
      <p className="text-sm text-muted">
        Sends one message to your own address ({ctx.session.user.email ? "the address you sign in with" : "no address on file"}),
        using the same path as the signed copy of an estimate. Repeated checks within the same hour send one message.
      </p>
      <p className="text-sm text-text" data-email-setup={setup.configured ? "configured" : "missing"}>
        {setup.configured
          ? "Email is set up on this deployment."
          : `Email isn't set up on this deployment: ${setup.missing.join(" and ")} missing.`}
      </p>
      {result ? (
        <p
          role={result.tone === "warn" ? "alert" : "status"}
          data-email-check={searchParams.result}
          className={`rounded-md px-3 py-2 text-sm text-text ${result.tone === "warn" ? "bg-warn-soft" : "bg-accent-soft"}`}
        >
          {result.text}
        </p>
      ) : null}
      <form action={sendEmailCheck}>
        <input type="hidden" name="orgId" value={params.orgId} />
        <button type="submit" className="min-h-11 rounded-md bg-accent-strong px-4 py-2 text-sm font-medium text-white">
          Send me a test email
        </button>
      </form>
    </div>
  );
}
