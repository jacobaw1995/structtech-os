import { createTradeWorkOrder } from "@/lib/coordination/actions";
import type { Database } from "@/lib/supabase/database.types";

type WorkOrder = Database["public"]["Tables"]["work_orders"]["Row"];

// Rendered only on a master (see the work order page) — trades do not nest, so
// a trade page never gets this form.
export function AddTradeWorkOrderForm({
  orgId,
  masterWorkOrderId,
  siblingTrades,
  tradeSuggestions,
}: {
  orgId: string;
  masterWorkOrderId: string;
  siblingTrades: WorkOrder[];
  tradeSuggestions: string[];
}) {
  const datalistId = `trade-suggestions-${masterWorkOrderId}`;

  return (
    // Same mobile stacking as AddScheduleBlockForm: full-width fields on a
    // phone, one line at sm and up.
    <form
      action={createTradeWorkOrder}
      className="flex flex-col gap-2 border-t border-border pt-2 sm:flex-row sm:flex-wrap sm:items-center"
    >
      <input type="hidden" name="orgId" value={orgId} />
      <input type="hidden" name="masterWorkOrderId" value={masterWorkOrderId} />

      {/* FREE TEXT, NOT A SELECT — deliberate, see §5.1 A1.3a and §10. The
          engine is config-driven and tenants do not share a trade list, so a
          closed list here would undo that decision in the UI layer. The
          datalist is a suggestion affordance only: it is built from the trades
          this org has already used, so it stays empty for a tenant on its first
          job and never constrains what can be typed. */}
      <input
        name="trade"
        list={datalistId}
        required
        placeholder="Trade…"
        className="min-h-14 w-full rounded-md border border-border bg-bg px-2 text-base text-text outline-none focus:border-accent sm:min-h-0 sm:w-36 sm:py-2 sm:text-sm"
      />
      <datalist id={datalistId}>
        {tradeSuggestions.map((t) => (
          <option key={t} value={t} />
        ))}
      </datalist>

      {/* A closed list IS correct here: work_orders_assignee_type_check permits
          exactly these three values, so anything else is a constraint
          violation, not tenant configuration. */}
      <select
        name="assignee_type"
        defaultValue=""
        className="min-h-14 w-full rounded-md border border-border bg-bg px-2 text-base text-text outline-none focus:border-accent sm:min-h-0 sm:w-40 sm:py-2 sm:text-sm"
      >
        <option value="">Assignee type…</option>
        <option value="crew">Crew</option>
        <option value="department">Department</option>
        <option value="subcontractor">Subcontractor</option>
      </select>

      <input
        name="assignee_ref"
        placeholder="Assignee…"
        className="min-h-14 w-full rounded-md border border-border bg-bg px-2 text-base text-text outline-none focus:border-accent sm:min-h-0 sm:w-36 sm:py-2 sm:text-sm"
      />

      {siblingTrades.length > 0 && (
        <select
          name="predecessor_id"
          defaultValue=""
          className="min-h-14 w-full rounded-md border border-border bg-bg px-2 text-base text-text outline-none focus:border-accent sm:min-h-0 sm:w-44 sm:py-2 sm:text-sm"
        >
          <option value="">No predecessor</option>
          {siblingTrades.map((t) => (
            <option key={t.id} value={t.id}>
              After {t.trade}
            </option>
          ))}
        </select>
      )}

      <button
        type="submit"
        className="min-h-14 rounded-md bg-accent-strong px-4 text-base font-medium text-white sm:min-h-0 sm:py-2 sm:text-sm"
      >
        Add trade
      </button>
    </form>
  );
}
