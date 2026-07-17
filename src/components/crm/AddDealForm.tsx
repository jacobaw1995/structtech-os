import { createDeal } from "@/lib/crm/actions";
import { LEAD_TYPE_OPTIONS } from "@/lib/crm/command-center";

// The real new-lead form (CRM Depth Stage 1, reworked in the fix pass
// below). Company stays always-visible ("if applicable") rather than
// conditionally shown/hidden by lead type — that's later polish
// (BACKLOG.md), not worth a client component here. billing_address has
// no "same as project" checkbox/JS — left blank, it falls back to the
// structured service address wherever it's displayed later.
//
// Fix pass (7/16): first/last name split (matches the intake checklist's
// first_name/last_name columns — contact_name is now derived server-side
// by create_deal) and a structured service address (street/city/state/
// zip, matching service_address_* — the checklist's canonical address)
// replace the old single "Contact name" + free-text "Project address"
// fields, which never flowed into the checklist or the estimate's
// structured address at all. project_address is retired from this form.
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
          <span className="text-muted">First name</span>
          <input
            name="first_name"
            required
            className="rounded-md border border-border bg-bg px-2 py-1.5 text-text outline-none focus:border-accent"
          />
        </label>
        <label className="flex flex-col gap-1 text-sm">
          <span className="text-muted">Last name</span>
          <input
            name="last_name"
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
            {LEAD_TYPE_OPTIONS.map((o) => (
              <option key={o.value} value={o.value}>
                {o.label}
              </option>
            ))}
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

        <div className="col-span-2 flex flex-col gap-1 text-sm">
          <span className="text-muted">Service address</span>
          <input
            name="service_address_street"
            required
            placeholder="Street"
            className="rounded-md border border-border bg-bg px-2 py-1.5 text-text outline-none focus:border-accent"
          />
          <div className="grid grid-cols-3 gap-2">
            <input
              name="service_address_city"
              placeholder="City"
              className="rounded-md border border-border bg-bg px-2 py-1.5 text-text outline-none focus:border-accent"
            />
            <input
              name="service_address_state"
              placeholder="State"
              className="rounded-md border border-border bg-bg px-2 py-1.5 text-text outline-none focus:border-accent"
            />
            <input
              name="service_address_zip"
              placeholder="ZIP"
              className="rounded-md border border-border bg-bg px-2 py-1.5 text-text outline-none focus:border-accent"
            />
          </div>
        </div>
        <label className="col-span-2 flex flex-col gap-1 text-sm">
          <span className="text-muted">Billing address</span>
          <input
            name="billing_address"
            placeholder="Leave blank if same as service address"
            className="rounded-md border border-border bg-bg px-2 py-1.5 text-text outline-none focus:border-accent"
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
