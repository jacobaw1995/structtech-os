import { createDeal } from "@/lib/crm/actions";

// The real new-lead form (CRM Depth Stage 1) — replaces the old 4-field
// version that had no contact info at all. Company stays always-visible
// ("if applicable") rather than conditionally shown/hidden by lead type —
// that's later polish (BACKLOG.md), not worth a client component here.
// billing_address has no "same as project" checkbox/JS — left blank, it
// falls back to project_address wherever it's displayed later.
export function AddDealForm({
  orgId,
  errorMessage,
}: {
  orgId: string;
  errorMessage?: string;
}) {
  return (
    <form
      action={createDeal}
      className="flex flex-col gap-3 rounded-lg border border-border bg-surface p-4"
    >
      <input type="hidden" name="orgId" value={orgId} />

      {errorMessage && (
        <p className="rounded-md bg-warn-soft px-3 py-2 text-xs text-text">
          {errorMessage}
        </p>
      )}

      <div className="grid grid-cols-2 gap-3">
        <label className="flex flex-col gap-1 text-sm">
          <span className="text-muted">Contact name</span>
          <input
            name="contact_name"
            required
            className="rounded-md border border-border bg-bg px-2 py-1.5 text-text outline-none focus:border-accent"
          />
        </label>
        <label className="flex flex-col gap-1 text-sm">
          <span className="text-muted">Cell phone</span>
          <input
            name="phone"
            type="tel"
            className="rounded-md border border-border bg-bg px-2 py-1.5 text-text outline-none focus:border-accent"
          />
        </label>
        <label className="flex flex-col gap-1 text-sm">
          <span className="text-muted">Email</span>
          <input
            name="email"
            type="email"
            className="rounded-md border border-border bg-bg px-2 py-1.5 text-text outline-none focus:border-accent"
          />
        </label>
        <label className="flex flex-col gap-1 text-sm">
          <span className="text-muted">Lead type</span>
          <select
            name="lead_type"
            defaultValue=""
            className="rounded-md border border-border bg-bg px-2 py-1.5 text-text outline-none focus:border-accent"
          >
            <option value="">— Select —</option>
            <option value="homeowner">Homeowner</option>
            <option value="company">Company</option>
          </select>
        </label>
        <label className="flex flex-col gap-1 text-sm">
          <span className="text-muted">Company (if applicable)</span>
          <input
            name="company"
            className="rounded-md border border-border bg-bg px-2 py-1.5 text-text outline-none focus:border-accent"
          />
        </label>
        <label className="flex flex-col gap-1 text-sm">
          <span className="text-muted">Source</span>
          <select
            name="source"
            defaultValue="manual"
            className="rounded-md border border-border bg-bg px-2 py-1.5 text-text outline-none focus:border-accent"
          >
            <option value="referral">Referral</option>
            <option value="website">Website</option>
            <option value="cold_call">Cold call</option>
            <option value="walk_in">Walk-in</option>
            <option value="manual">Other</option>
          </select>
        </label>
        <label className="col-span-2 flex flex-col gap-1 text-sm">
          <span className="text-muted">Project address</span>
          <input
            name="project_address"
            required
            placeholder="Job site / service address"
            className="rounded-md border border-border bg-bg px-2 py-1.5 text-text outline-none focus:border-accent"
          />
        </label>
        <label className="col-span-2 flex flex-col gap-1 text-sm">
          <span className="text-muted">Billing address</span>
          <input
            name="billing_address"
            placeholder="Leave blank if same as project address"
            className="rounded-md border border-border bg-bg px-2 py-1.5 text-text outline-none focus:border-accent"
          />
        </label>
        <label className="flex flex-col gap-1 text-sm">
          <span className="text-muted">Value</span>
          <input
            name="value"
            type="number"
            min="0"
            step="1"
            className="rounded-md border border-border bg-bg px-2 py-1.5 font-mono text-text outline-none focus:border-accent"
          />
        </label>
      </div>

      <button
        type="submit"
        className="self-start rounded-md bg-accent-strong px-3 py-1.5 text-sm font-medium text-white"
      >
        Add deal
      </button>
    </form>
  );
}
