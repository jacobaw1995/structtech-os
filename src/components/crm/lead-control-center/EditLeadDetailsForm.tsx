import { updateDealDetails, archiveDeal, restoreDeal } from "@/lib/crm/actions";
import { LEAD_TYPE_OPTIONS, REMODEL_OPTIONS, type DealRow } from "@/lib/crm/command-center";

// The full edit form ("Edit lead details ->" in the spec) — every field the
// Lead Control Center can show, in one place, not just the subset covered
// by a command-stage checklist. Relocated + extended from the old
// DealPanel's "Edit details" block (Stage 1/2 fields) with the rest of the
// Stage 2 lead-data-model columns that had no editor at all until now.
export function EditLeadDetailsForm({ orgId, deal }: { orgId: string; deal: DealRow }) {
  return (
    <details className="rounded-md border border-border text-sm">
      <summary className="cursor-pointer select-none px-3 py-2 font-medium text-accent-strong">Edit lead details →</summary>
      <form action={updateDealDetails} className="flex flex-col gap-2 border-t border-border p-3">
        <input type="hidden" name="orgId" value={orgId} />
        <input type="hidden" name="dealId" value={deal.id} />

        <div className="grid grid-cols-2 gap-2">
          <Field label="First name" name="first_name" defaultValue={deal.first_name ?? ""} />
          <Field label="Last name" name="last_name" defaultValue={deal.last_name ?? ""} />
        </div>
        <Field label="Contact name (override)" name="contact_name" defaultValue={deal.contact_name} />
        <Field label="Company" name="company" defaultValue={deal.company ?? ""} />
        <div className="grid grid-cols-2 gap-2">
          <Field label="Email" name="email" defaultValue={deal.email ?? ""} />
          <Field label="Cell phone" name="phone" defaultValue={deal.phone ?? ""} />
        </div>
        <Field label="Secondary phone" name="secondary_phone" defaultValue={deal.secondary_phone ?? ""} />

        <label className="flex flex-col gap-1 text-xs">
          <span className="text-muted">Lead type</span>
          <select
            name="lead_type"
            defaultValue={deal.lead_type ?? ""}
            className="rounded-md border border-border bg-bg px-2 py-1.5 text-sm text-text outline-none focus:border-accent"
          >
            <option value="">—</option>
            {LEAD_TYPE_OPTIONS.map((o) => (
              <option key={o.value} value={o.value}>
                {o.label}
              </option>
            ))}
          </select>
        </label>

        <label className="flex flex-col gap-1 text-xs">
          <span className="text-muted">Remodel or new construction</span>
          <select
            name="remodel_or_new_construction"
            defaultValue={deal.remodel_or_new_construction ?? ""}
            className="rounded-md border border-border bg-bg px-2 py-1.5 text-sm text-text outline-none focus:border-accent"
          >
            <option value="">—</option>
            {REMODEL_OPTIONS.map((o) => (
              <option key={o.value} value={o.value}>
                {o.label}
              </option>
            ))}
          </select>
        </label>

        <Field label="Existing roof type(s)" name="existing_roof_type" defaultValue={(deal.existing_roof_type ?? []).join(", ")} placeholder="Comma-separated" />
        <Field label="Requested roof type(s)" name="roof_type_requested" defaultValue={(deal.roof_type_requested ?? []).join(", ")} placeholder="Comma-separated" />

        <Field label="Project address" name="project_address" defaultValue={deal.project_address ?? ""} />
        <Field label="Billing address" name="billing_address" defaultValue={deal.billing_address ?? ""} placeholder="Same as project address if blank" />

        <div className="grid grid-cols-4 gap-2">
          <Field label="Service street" name="service_address_street" defaultValue={deal.service_address_street ?? ""} />
          <Field label="City" name="service_address_city" defaultValue={deal.service_address_city ?? ""} />
          <Field label="State" name="service_address_state" defaultValue={deal.service_address_state ?? ""} />
          <Field label="ZIP" name="service_address_zip" defaultValue={deal.service_address_zip ?? ""} />
        </div>

        <Field label="Referral name" name="referral_name" defaultValue={deal.referral_name ?? ""} />

        <div className="grid grid-cols-3 gap-2">
          <Field label="Value" name="value" type="number" defaultValue={deal.value ?? ""} />
          <Field label="Trade" name="trade" defaultValue={deal.trade ?? ""} />
          <Field label="Crew size" name="crew_size" type="number" defaultValue={deal.crew_size ?? ""} />
        </div>

        <button type="submit" className="mt-1 self-end rounded-md bg-accent-strong px-3 py-1.5 text-xs font-medium text-white">
          Save details
        </button>
      </form>

      {!deal.archived_at ? (
        <form action={archiveDeal} className="border-t border-border p-3">
          <input type="hidden" name="orgId" value={orgId} />
          <input type="hidden" name="dealId" value={deal.id} />
          <button type="submit" className="w-full rounded-md border border-warn px-3 py-1.5 text-xs font-medium text-warn">
            Archive deal
          </button>
        </form>
      ) : (
        <form action={restoreDeal} className="border-t border-border p-3">
          <input type="hidden" name="orgId" value={orgId} />
          <input type="hidden" name="dealId" value={deal.id} />
          <button type="submit" className="w-full rounded-md border border-accent-strong px-3 py-1.5 text-xs font-medium text-accent-strong">
            Restore deal
          </button>
        </form>
      )}
    </details>
  );
}

function Field({
  label,
  name,
  defaultValue,
  type = "text",
  placeholder,
}: {
  label: string;
  name: string;
  defaultValue: string | number;
  type?: string;
  placeholder?: string;
}) {
  return (
    <label className="flex flex-col gap-1 text-xs">
      <span className="text-muted">{label}</span>
      <input
        name={name}
        type={type}
        step={type === "number" ? "any" : undefined}
        defaultValue={defaultValue}
        placeholder={placeholder}
        className="rounded-md border border-border bg-bg px-2 py-1.5 text-sm text-text outline-none focus:border-accent"
      />
    </label>
  );
}
