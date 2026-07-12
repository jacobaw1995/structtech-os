import { createDeal } from "@/lib/crm/actions";

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
          <span className="text-muted">Company</span>
          <input
            name="company"
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
