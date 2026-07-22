"use client";

import { useRef, useState, useTransition } from "react";
import { signEstimate } from "@/lib/estimating/actions";
import { createWorkOrderFromEstimate } from "@/lib/coordination/actions";
import { formatMoney } from "@/lib/crm/stages";
import { SignaturePad, type SignaturePadHandle } from "@/components/estimating/SignaturePad";

// Chunk 5 relocation: StepSign.tsx (deleted) owned SignaturePad + sign
// capture + the post-sign PDF/create-work-order links. This is their new
// home, adapted for the unified document (no step navigation — every
// action redirects back to the same canonical estimate page, or into
// Present Mode).
//
// The one interactive element Present Mode keeps (Jacob, Chunk 5
// correction): a customer signs IN Present Mode, at the kitchen table, on
// the tablet — that's the close. So the "presented, unsigned" branch below
// renders identically whether presentationMode is true or false; only the
// POST-sign operator links (PDF/create-work-order) are hidden in
// presentationMode — those are for Isaac, not the homeowner looking at
// their own signed copy.
export function EstimateSignatureBlock({
  orgId,
  estimateId,
  status,
  signed,
  imageDataUrl,
  signerLine,
  dateLine,
  liveTotal,
  presentationMode,
}: {
  orgId: string;
  estimateId: string;
  status: string;
  signed: boolean;
  imageDataUrl?: string;
  signerLine?: string;
  dateLine?: string;
  liveTotal: number;
  presentationMode: boolean;
}) {
  const padRef = useRef<SignaturePadHandle>(null);
  const [hasInk, setHasInk] = useState(false);
  const [signerName, setSignerName] = useState("");
  const [signerRole, setSignerRole] = useState("Homeowner");
  const [isPending, startTransition] = useTransition();
  const [clientError, setClientError] = useState<string | null>(null);

  const pdfHref = `/w/${orgId}/estimating/${estimateId}/pdf`;

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
    formData.set("estimateId", estimateId);
    formData.set("signer_name", signerName.trim());
    formData.set("signer_role", signerRole);
    formData.set("signature_data", dataUrl);

    startTransition(() => {
      signEstimate(formData);
    });
  }

  function handleCreateWorkOrder() {
    const formData = new FormData();
    formData.set("orgId", orgId);
    formData.set("estimateId", estimateId);
    startTransition(() => {
      createWorkOrderFromEstimate(formData);
    });
  }

  if (signed) {
    return (
      <div className="flex flex-col gap-2">
        {/* eslint-disable-next-line @next/next/no-img-element -- data URL, not a static asset */}
        <img
          src={imageDataUrl}
          alt="Signature"
          className="h-20 w-fit max-w-full rounded-md border border-border bg-bg object-contain"
        />
        <p className="text-sm text-text">{signerLine}</p>
        <p className="text-xs text-muted">{dateLine}</p>
        {!presentationMode && (
          <div className="flex flex-wrap items-center gap-4 pt-1 text-sm">
            <a href={pdfHref} target="_blank" rel="noreferrer" className="text-accent-strong underline">
              View PDF
            </a>
            <a href={`${pdfHref}?download=1`} className="text-accent-strong underline">
              Download PDF
            </a>
            <button
              type="button"
              disabled={isPending}
              onClick={handleCreateWorkOrder}
              className="font-medium text-accent-strong underline disabled:opacity-60"
            >
              {isPending ? "Creating…" : "Create work order →"}
            </button>
          </div>
        )}
      </div>
    );
  }

  if (status === "presented") {
    return (
      <div className="flex flex-col gap-3">
        {clientError && (
          <p className="rounded-md bg-warn-soft px-3 py-2 text-xs text-text">{clientError}</p>
        )}
        <SignaturePad ref={padRef} onDirtyChange={setHasInk} />
        <div className="flex items-center justify-between">
          <p className="text-xs text-muted">Customer signs here</p>
          <button
            type="button"
            onClick={() => padRef.current?.clear()}
            className="text-xs text-muted underline"
          >
            Clear
          </button>
        </div>
        <div className="grid grid-cols-2 gap-3">
          <label className="flex flex-col gap-1 text-sm">
            <span className="text-muted">Signer name</span>
            <input
              value={signerName}
              onChange={(e) => setSignerName(e.target.value)}
              className="rounded-md border border-border bg-bg px-2 py-2 text-text outline-none focus:border-accent"
            />
          </label>
          <label className="flex flex-col gap-1 text-sm">
            <span className="text-muted">Role</span>
            <select
              value={signerRole}
              onChange={(e) => setSignerRole(e.target.value)}
              className="rounded-md border border-border bg-bg px-2 py-2 text-text outline-none focus:border-accent"
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
          {isPending ? "Signing…" : `Sign to accept — ${formatMoney(liveTotal)}`}
        </button>
        {!hasInk && (
          <p className="text-center text-xs text-muted">Draw a signature above to enable signing.</p>
        )}
      </div>
    );
  }

  // Draft, not yet presented — blank signature/date lines (Chunk 3 polish
  // #3). Present Mode never actually reaches this branch in practice
  // ("Present to client" sets status='presented' before navigating there),
  // but it degrades harmlessly if it ever does.
  return (
    <div className="flex flex-wrap items-end gap-8 pt-2">
      <div className="flex min-w-[12rem] flex-1 flex-col gap-1">
        <div className="h-10 border-b border-text/30" />
        <span className="text-[10px] uppercase tracking-wide text-muted">Signature</span>
      </div>
      <div className="flex w-32 flex-col gap-1">
        <div className="h-10 border-b border-text/30" />
        <span className="text-[10px] uppercase tracking-wide text-muted">Date</span>
      </div>
    </div>
  );
}
