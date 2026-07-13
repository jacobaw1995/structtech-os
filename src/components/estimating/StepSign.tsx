"use client";

import { useRef, useState, useTransition } from "react";
import { signEstimate } from "@/lib/estimating/actions";
import { formatMoney } from "@/lib/crm/stages";
import { SignaturePad, type SignaturePadHandle } from "@/components/estimating/SignaturePad";
import type { Database } from "@/lib/supabase/database.types";

type Estimate = Database["public"]["Tables"]["estimates"]["Row"];
type Signature = Database["public"]["Tables"]["signatures"]["Row"];

// Same-session, authenticated-caller-only signing (CLAUDE.md: no anon/token
// path this phase) — the rep hands their own device to the customer, so
// there's no separate signer auth step, just a name + role captured
// alongside the ink.
export function StepSign({
  orgId,
  estimate,
  signature,
  errorMessage,
}: {
  orgId: string;
  estimate: Estimate;
  signature: Signature | null;
  errorMessage?: string;
}) {
  const padRef = useRef<SignaturePadHandle>(null);
  const [hasInk, setHasInk] = useState(false);
  const [signerName, setSignerName] = useState("");
  const [signerRole, setSignerRole] = useState("Homeowner");
  const [isPending, startTransition] = useTransition();
  const [clientError, setClientError] = useState<string | null>(null);

  const total = estimate.presented_total ?? estimate.subtotal;
  const alreadySigned = estimate.status === "signed";
  const pdfHref = `/w/${orgId}/estimating/${estimate.id}/pdf`;

  function handleSign() {
    if (!signerName.trim()) {
      setClientError("Enter the signer's name.");
      return;
    }
    const dataUrl = padRef.current?.toDataUrl();
    if (!dataUrl) {
      setClientError("Sign in the box above before confirming.");
      return;
    }
    setClientError(null);

    const formData = new FormData();
    formData.set("orgId", orgId);
    formData.set("estimateId", estimate.id);
    formData.set("signer_name", signerName.trim());
    formData.set("signer_role", signerRole);
    formData.set("signature_data", dataUrl);

    startTransition(() => {
      signEstimate(formData);
    });
  }

  if (alreadySigned) {
    return (
      <div className="flex flex-col gap-4 rounded-2xl border-2 border-border bg-surface p-4 group-data-[outdoor=true]/flow:border-white group-data-[outdoor=true]/flow:bg-black">
        <p className="text-xs uppercase tracking-wide text-muted group-data-[outdoor=true]/flow:text-white/60">
          Signed
        </p>
        <p className="text-3xl font-bold text-text group-data-[outdoor=true]/flow:text-white">
          {formatMoney(total)}
        </p>
        {signature && (
          <p className="text-sm text-muted group-data-[outdoor=true]/flow:text-white/70">
            {signature.signer_name} ({signature.signer_role})
          </p>
        )}
        <a
          href={pdfHref}
          target="_blank"
          rel="noreferrer"
          className="flex min-h-14 items-center justify-center rounded-lg bg-accent-strong text-base font-medium text-white"
        >
          Confirm & view copy
        </a>
        <a
          href={`${pdfHref}?download=1`}
          className="text-center text-sm text-muted underline group-data-[outdoor=true]/flow:text-white/70"
        >
          Download PDF
        </a>
      </div>
    );
  }

  return (
    <div className="flex flex-col gap-4 rounded-2xl border-2 border-border bg-surface p-4 group-data-[outdoor=true]/flow:border-white group-data-[outdoor=true]/flow:bg-black">
      <p className="text-sm font-semibold text-text group-data-[outdoor=true]/flow:text-white">
        Sign to accept — {formatMoney(total)}
      </p>

      {(errorMessage || clientError) && (
        <p className="rounded-md bg-warn-soft px-3 py-2 text-xs text-text">
          {clientError ?? errorMessage}
        </p>
      )}

      <SignaturePad ref={padRef} onDirtyChange={setHasInk} />
      <div className="flex items-center justify-between">
        <p className="text-xs text-muted group-data-[outdoor=true]/flow:text-white/60">
          Customer signs here
        </p>
        <button
          type="button"
          onClick={() => padRef.current?.clear()}
          className="text-xs text-muted underline group-data-[outdoor=true]/flow:text-white/70"
        >
          Clear
        </button>
      </div>

      <div className="grid grid-cols-2 gap-3">
        <label className="flex flex-col gap-1 text-sm">
          <span className="text-muted group-data-[outdoor=true]/flow:text-white/70">
            Signer name
          </span>
          <input
            value={signerName}
            onChange={(e) => setSignerName(e.target.value)}
            className="rounded-md border border-border bg-bg px-2 py-2 text-text outline-none focus:border-accent group-data-[outdoor=true]/flow:border-white/40 group-data-[outdoor=true]/flow:bg-black group-data-[outdoor=true]/flow:text-white"
          />
        </label>
        <label className="flex flex-col gap-1 text-sm">
          <span className="text-muted group-data-[outdoor=true]/flow:text-white/70">
            Role
          </span>
          <select
            value={signerRole}
            onChange={(e) => setSignerRole(e.target.value)}
            className="rounded-md border border-border bg-bg px-2 py-2 text-text outline-none focus:border-accent group-data-[outdoor=true]/flow:border-white/40 group-data-[outdoor=true]/flow:bg-black group-data-[outdoor=true]/flow:text-white"
          >
            <option>Homeowner</option>
            <option>Property manager</option>
            <option>Other</option>
          </select>
        </label>
      </div>

      <button
        type="button"
        disabled={isPending}
        onClick={handleSign}
        className="flex min-h-14 items-center justify-center rounded-lg bg-accent-strong text-base font-medium text-white disabled:opacity-60"
      >
        {isPending ? "Signing…" : `Sign to accept — ${formatMoney(total)}`}
      </button>

      {!hasInk && (
        <p className="text-center text-xs text-muted group-data-[outdoor=true]/flow:text-white/60">
          Draw a signature above to enable signing.
        </p>
      )}
    </div>
  );
}
