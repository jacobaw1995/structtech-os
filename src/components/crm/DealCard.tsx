import Link from "next/link";
import type { Database } from "@/lib/supabase/database.types";
import { formatMoney } from "@/lib/crm/stages";

type Deal = Database["public"]["Tables"]["deals"]["Row"];

export function DealCard({
  deal,
  href,
  selected,
  nextAction,
  canViewFinancials = true,
}: {
  deal: Deal;
  href: string;
  selected: boolean;
  nextAction: string | null;
  canViewFinancials?: boolean;
}) {
  return (
    <Link
      href={href}
      className={`flex flex-col gap-1.5 rounded-md border bg-surface p-3 text-left transition-colors hover:border-accent ${
        selected ? "border-accent ring-1 ring-accent" : "border-border"
      }`}
    >
      <span className="text-sm font-medium text-text">
        {deal.company || deal.contact_name}
      </span>
      {deal.company && (
        <span className="text-xs text-muted">{deal.contact_name}</span>
      )}
      {/* deal.value is already nulled server-side for a caller without
          view_financials (fetch_deal / the pipeline list query, Phase A
          capability model) — hiding the line outright rather than
          rendering formatMoney(null)'s "—" avoids implying "no value set"
          when the real reason is "not visible to you". */}
      {canViewFinancials && (
        <span className="font-mono text-sm text-text">
          {formatMoney(deal.value)}
        </span>
      )}
      {nextAction && (
        <span className="w-fit rounded-full bg-accent-soft px-2 py-0.5 text-xs text-accent-strong">
          {nextAction}
        </span>
      )}
    </Link>
  );
}
