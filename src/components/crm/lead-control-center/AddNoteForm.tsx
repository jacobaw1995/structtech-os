import { addDealNote } from "@/lib/crm/actions";

export function AddNoteForm({ orgId, dealId }: { orgId: string; dealId: string }) {
  return (
    <form action={addDealNote} className="flex flex-col gap-2">
      <input type="hidden" name="orgId" value={orgId} />
      <input type="hidden" name="dealId" value={dealId} />
      <textarea
        name="content"
        required
        rows={2}
        placeholder="Add a note…"
        className="min-h-14 rounded-md border border-border bg-bg px-2 py-1.5 text-base text-text outline-none focus:border-accent sm:min-h-0 sm:text-sm"
      />
      <button type="submit" className="min-h-14 self-end rounded-md bg-accent-strong px-3 text-sm font-medium text-white sm:min-h-0 sm:py-1 sm:text-xs">
        Add note
      </button>
    </form>
  );
}
