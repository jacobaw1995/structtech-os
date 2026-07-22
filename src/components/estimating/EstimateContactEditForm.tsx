import { updateEstimateDocumentContact } from "@/lib/estimating/actions";

// Task A (7/24 walkthrough) — the customer block holds ESTABLISHED reference
// data (copied from the lead at estimate creation), not fields being
// gathered — a stray thumb tap-to-editing this on a phone at the job site
// must not silently overwrite a saved phone number (SCOPE §2.8
// clarification). Same <details>-disclosure + explicit-Save pattern as
// EditLeadDetailsForm (Lead Control Center): collapsed by default, one
// deliberate tap to open, one deliberate tap to save — never auto-submit-
// on-blur like EditableField. Job-site measurements (site_address/squares/
// pitch) stay tap-to-edit deliberately — those are being gathered on-site
// during the estimate build, not established records.
export function EstimateContactEditForm({
  orgId,
  estimateId,
  company,
  contactName,
  phone,
  email,
}: {
  orgId: string;
  estimateId: string;
  company: string;
  contactName: string;
  phone: string;
  email: string;
}) {
  return (
    <details className="mt-1 rounded-md border border-border text-xs">
      <summary className="cursor-pointer select-none px-2 py-1.5 font-medium text-accent-strong">
        Edit customer →
      </summary>
      <form action={updateEstimateDocumentContact} className="flex flex-col gap-2 border-t border-border p-2">
        <input type="hidden" name="orgId" value={orgId} />
        <input type="hidden" name="estimateId" value={estimateId} />

        <Field label="Company" name="company" defaultValue={company} />
        <Field label="Contact name" name="contact_name" defaultValue={contactName} />
        <Field label="Phone" name="phone" type="tel" defaultValue={phone} />
        <Field label="Email" name="email" type="email" defaultValue={email} />

        <button type="submit" className="mt-1 self-end rounded-md bg-accent-strong px-3 py-1.5 text-xs font-medium text-white">
          Save
        </button>
      </form>
    </details>
  );
}

function Field({
  label,
  name,
  defaultValue,
  type = "text",
}: {
  label: string;
  name: string;
  defaultValue: string;
  type?: string;
}) {
  return (
    <label className="flex flex-col gap-1">
      <span className="text-muted">{label}</span>
      <input
        name={name}
        type={type}
        defaultValue={defaultValue}
        className="rounded-md border border-border bg-bg px-2 py-1.5 text-sm text-text outline-none focus:border-accent"
      />
    </label>
  );
}
