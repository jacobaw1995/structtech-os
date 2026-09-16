"use client";

import { useRef, useState } from "react";
import { useFormStatus } from "react-dom";
import { signByLink } from "@/lib/signing/link-actions";
import { SignaturePad, type SignaturePadHandle } from "@/components/estimating/SignaturePad";

// The customer's signature form. Phone first: one column, 56dp targets, the
// drawing box full width. The drawing is read into a hidden field at submit.
// Every refusal the database can give still comes back as a code the page looks
// up — these client checks only save a round trip, they decide nothing.
export function LinkSignForm({ token, documentVersion, total }: { token: string; documentVersion: string; total: string | null }) {
  const padRef = useRef<SignaturePadHandle>(null);
  const dataRef = useRef<HTMLInputElement>(null);
  const [problem, setProblem] = useState<string | null>(null);

  return (
    <form
      action={signByLink}
      onSubmit={(e) => {
        const form = e.currentTarget;
        const name = (form.elements.namedItem("signer_name") as HTMLInputElement).value.trim();
        const drawing = padRef.current?.toDataUrl() ?? null;
        if (!name) {
          e.preventDefault();
          setProblem("Enter your name before signing.");
          return;
        }
        if (!drawing) {
          e.preventDefault();
          setProblem("Draw your signature in the box before signing.");
          return;
        }
        setProblem(null);
        if (dataRef.current) dataRef.current.value = drawing;
      }}
      className="flex flex-col gap-4"
    >
      <input type="hidden" name="token" value={token} />
      <input type="hidden" name="document_version" value={documentVersion} />
      <input ref={dataRef} type="hidden" name="signature_data" value="" />

      <label className="flex flex-col gap-1">
        <span className="text-sm font-medium text-text">Your full name</span>
        <input
          name="signer_name"
          autoComplete="name"
          required
          className="min-h-14 rounded-lg border border-border bg-surface px-3 text-base text-text outline-none focus:border-accent"
        />
      </label>

      <label className="flex flex-col gap-1">
        <span className="text-sm font-medium text-text">You are signing as</span>
        <select
          name="signer_role"
          defaultValue="Homeowner"
          className="min-h-14 rounded-lg border border-border bg-surface px-3 text-base text-text outline-none focus:border-accent"
        >
          <option>Homeowner</option>
          <option>Property manager</option>
          <option>Other</option>
        </select>
      </label>

      <div className="flex flex-col gap-2">
        <span className="text-sm font-medium text-text">Draw your signature</span>
        <SignaturePad ref={padRef} onDirtyChange={() => setProblem(null)} />
        <button
          type="button"
          onClick={() => padRef.current?.clear()}
          className="flex min-h-14 items-center justify-center self-start rounded-lg border border-border px-4 text-base text-text"
        >
          Clear signature
        </button>
      </div>

      {problem && (
        <p role="alert" className="rounded-lg border border-warn bg-warn-soft px-3 py-2 text-sm text-text">
          {problem}
        </p>
      )}

      <SubmitButton total={total} />
      <p className="text-sm leading-relaxed text-muted">
        Signing accepts this estimate as shown above. Your signature is saved as soon as you sign.
      </p>
    </form>
  );
}

function SubmitButton({ total }: { total: string | null }) {
  const { pending } = useFormStatus();
  return (
    <button
      type="submit"
      disabled={pending}
      className="flex min-h-14 items-center justify-center rounded-lg bg-accent-strong px-4 text-base font-semibold text-white disabled:opacity-70"
    >
      {pending ? "Signing…" : total ? `Sign and accept · ${total}` : "Sign and accept"}
    </button>
  );
}
