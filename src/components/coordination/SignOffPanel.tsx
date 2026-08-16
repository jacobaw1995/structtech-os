"use client";

import { useRef, useState, useTransition } from "react";
import { signWorkOrderAgreement } from "@/lib/coordination/actions";
import { formatDate } from "@/lib/crm/stages";
import { formatWorkOrderActivityLine } from "@/lib/coordination/stage";
import { SignaturePad, type SignaturePadHandle } from "@/components/estimating/SignaturePad";
import type { Database } from "@/lib/supabase/database.types";

type Agreement = Database["public"]["Tables"]["work_order_agreements"]["Row"];
type WorkOrderActivity = Database["public"]["Tables"]["work_order_activity"]["Row"];

type ColorsFinishes = {
  description?: string;
  shingle_color?: string;
  trim_color?: string;
  gutter_color?: string;
};

// Phase A Week 2 chunk 2: replaces the old notes-only stub
// (record_work_order_sign_off) entirely. Real homeowner signature, anchored
// to a hard colors & finishes confirmation — the rest of the work order
// (materials, schedule) is shown elsewhere on this page for visibility,
// not re-shown or re-signed here (COORDINATION_MODULE_SCOPE.md §7).
//
// Once signed, the agreement is immutable — no more post-signoff editing
// of colors/finishes here (that was the old stub's whole design; a real
// signature can't be silently rewritten). A change after signing needs a
// change order (void + replace, later chunk), not an in-place edit.
export function SignOffPanel({
  orgId,
  workOrderId,
  agreement,
  activity,
  authorName,
}: {
  orgId: string;
  workOrderId: string;
  agreement: Agreement | null;
  activity: WorkOrderActivity[];
  authorName: (userId: string | null) => string;
}) {
  const padRef = useRef<SignaturePadHandle>(null);
  const [signerName, setSignerName] = useState("");
  const [signerRole, setSignerRole] = useState("Homeowner");
  const [description, setDescription] = useState("");
  const [shingleColor, setShingleColor] = useState("");
  const [trimColor, setTrimColor] = useState("");
  const [gutterColor, setGutterColor] = useState("");
  const [isPending, startTransition] = useTransition();
  const [clientError, setClientError] = useState<string | null>(null);

  if (agreement?.status === "signed") {
    const cf = (agreement.colors_finishes ?? {}) as ColorsFinishes;
    return (
      <div className="rounded-lg border border-border bg-surface p-3">
        <p className="text-sm font-medium text-text">
          Homeowner sign-off complete — {agreement.signed_at ? formatDate(agreement.signed_at) : "—"}
          {activity.length > 0 && " — changed after sign-off"}
        </p>
        {cf.description && <p className="mt-1 text-sm text-text">{cf.description}</p>}
        {(cf.shingle_color || cf.trim_color || cf.gutter_color) && (
          <div className="mt-1 flex flex-wrap gap-3 text-xs text-muted">
            {cf.shingle_color && <span>Shingle: {cf.shingle_color}</span>}
            {cf.trim_color && <span>Trim: {cf.trim_color}</span>}
            {cf.gutter_color && <span>Gutter: {cf.gutter_color}</span>}
          </div>
        )}
        {agreement.signature_data && (
          // eslint-disable-next-line @next/next/no-img-element -- data URL, not a static asset
          <img
            src={agreement.signature_data}
            alt="Signature"
            className="mt-2 h-16 w-fit max-w-full rounded-md border border-border bg-bg object-contain"
          />
        )}
        <p className="mt-1 text-xs text-muted">
          {agreement.signer_name} — {agreement.signer_role}
        </p>
        {activity.length > 0 && (
          <div className="mt-2 flex flex-col gap-1 border-t border-border pt-2">
            {activity.map((entry) => (
              <p key={entry.id} className="text-xs text-text">
                {formatWorkOrderActivityLine(
                  { action: entry.action, from_value: entry.from_value, to_value: entry.to_value },
                  entry.actor_id ? authorName(entry.actor_id) : null
                )}
                <span className="text-muted"> · {formatDate(entry.created_at)}</span>
              </p>
            ))}
          </div>
        )}
      </div>
    );
  }

  function handleSign() {
    if (!description.trim()) {
      setClientError("Confirm colors & finishes before signing.");
      return;
    }
    if (!signerName.trim()) {
      setClientError("Enter the signer's name.");
      return;
    }
    const dataUrl = padRef.current?.toDataUrl();
    if (!dataUrl) {
      setClientError("Sign in the box above before confirming.");
      return;
    }
    if (!agreement) {
      setClientError("Sign-off isn't ready yet — reload and try again.");
      return;
    }
    setClientError(null);

    const colorsFinishes: ColorsFinishes = {
      description: description.trim(),
      shingle_color: shingleColor.trim() || undefined,
      trim_color: trimColor.trim() || undefined,
      gutter_color: gutterColor.trim() || undefined,
    };

    const formData = new FormData();
    formData.set("orgId", orgId);
    formData.set("workOrderId", workOrderId);
    formData.set("agreementId", agreement.id);
    formData.set("signer_name", signerName.trim());
    formData.set("signer_role", signerRole);
    formData.set("signature_data", dataUrl);
    formData.set("colors_finishes", JSON.stringify(colorsFinishes));

    startTransition(() => {
      signWorkOrderAgreement(formData);
    });
  }

  return (
    <div className="flex flex-col gap-3 rounded-lg border border-border bg-surface p-3">
      <p className="text-sm font-medium text-text">Homeowner sign-off — colors &amp; finishes</p>
      {clientError && (
        <p className="rounded-md bg-warn-soft px-3 py-2 text-xs text-text">{clientError}</p>
      )}
      <label className="flex flex-col gap-1 text-sm">
        <span className="text-muted">Colors &amp; finishes confirmed (required)</span>
        <textarea
          value={description}
          onChange={(e) => setDescription(e.target.value)}
          rows={2}
          placeholder="e.g. Charcoal architectural shingles, white trim, matching gutters — homeowner confirmed on-site."
          className="rounded-md border border-border bg-bg px-2 py-2 text-sm text-text outline-none focus:border-accent"
        />
      </label>
      <div className="grid grid-cols-3 gap-2">
        <ColorField label="Shingle color" value={shingleColor} onChange={setShingleColor} />
        <ColorField label="Trim color" value={trimColor} onChange={setTrimColor} />
        <ColorField label="Gutter color" value={gutterColor} onChange={setGutterColor} />
      </div>

      <SignaturePad ref={padRef} />
      <p className="text-xs text-muted">Homeowner signs here</p>

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
        className="flex min-h-11 items-center justify-center rounded-lg bg-accent-strong text-sm font-medium text-white disabled:opacity-60"
      >
        {isPending ? "Signing…" : "Sign to confirm colors & finishes"}
      </button>
    </div>
  );
}

function ColorField({
  label,
  value,
  onChange,
}: {
  label: string;
  value: string;
  onChange: (value: string) => void;
}) {
  return (
    <label className="flex flex-col gap-1 text-xs">
      <span className="text-muted">{label}</span>
      <input
        value={value}
        onChange={(e) => onChange(e.target.value)}
        className="rounded-md border border-border bg-bg px-2 py-1.5 text-sm text-text outline-none focus:border-accent"
      />
    </label>
  );
}
