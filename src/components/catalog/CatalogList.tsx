import Link from "next/link";
import { formatUnitPrice, formatMarkup } from "@/lib/catalog/format";
import type { Database } from "@/lib/supabase/database.types";
import { setProductActive, deleteProduct } from "@/lib/catalog/actions";

type Product = Database["public"]["Tables"]["products"]["Row"];

// Extracted from the catalog page during the U-W1.2 design pass so the list
// can be RENDERED AND LOOKED AT without a signed-in session. The page is behind
// requireModuleAccess; the states that matter most visually — no financials,
// view-only, archived rows, a missing price, a name long enough to wrap — are
// states no fixture-free browser check could reach. Reviewing a copy of the
// markup would be a check that cannot fail (task directive §3), so the real
// page renders THIS component and nothing else renders the rows.
//
// It is a server component: the two forms are server actions and stay so.

export function CatalogList({
  orgId,
  products,
  canViewFinancials,
  canManageCatalog,
  confirmingDelete,
  editingId,
  editSlot,
  editActions,
  href,
}: {
  orgId: string;
  products: Product[];
  canViewFinancials: boolean;
  canManageCatalog: boolean;
  confirmingDelete: string | null;
  // The edit form stays IN PLACE of the row it edits rather than moving to the
  // top of the page — on a list of near-identical item names, "which one am I
  // editing" is answered by position and nothing else. The page owns the form
  // (it holds the server action and the datalists); the list owns where it goes.
  editingId?: string | null;
  editSlot?: React.ReactNode;
  editActions?: React.ReactNode;
  // The page owns URL state (search, category, archived) and every control in
  // here is a GET link, so the page hands down the one function that knows how
  // to keep that state intact.
  href: (overrides: Record<string, string | null>) => string;
  children?: React.ReactNode;
}) {
  return (
    <div className="rounded-lg border border-border bg-surface">
      {/* Column headers exist only where there are columns. Below sm each item
          is a self-labelling card, so a header row there would be a legend for
          a layout that isn't in use. */}
      <div className="hidden border-b border-border px-4 py-2 text-xs uppercase tracking-wide text-muted sm:grid sm:grid-cols-[minmax(0,1fr)_7rem_7rem_13rem] sm:gap-4">
        <span>Item</span>
        <span className="text-right">Cost</span>
        <span className="text-right">Sell</span>
        <span />
      </div>

      <ul>
        {products.map((product) => {
          if (editingId === product.id && canManageCatalog) {
            return (
              <li
                key={product.id}
                className="border-b border-border bg-accent-soft/40 px-4 py-3 last:border-0"
              >
                {editSlot}
                {editActions}
              </li>
            );
          }

          const cost = canViewFinancials ? formatUnitPrice(product.cost) : null;
          const sell = canViewFinancials ? formatUnitPrice(product.sell) : null;
          const markup = canViewFinancials ? formatMarkup(product.markup) : null;

          const money = !canViewFinancials ? (
            /* ONE chip, spanning both money columns. Two identical
               "Restricted" chips per row — which is what the first draft
               rendered, and what looking at it showed — is the same fact
               said twice and eight times down the page. */
            <div className="hidden sm:col-span-2 sm:block sm:text-right">
              <Restricted />
            </div>
          ) : (
            <>
              {/* Cost is MUTED and sell is not. On screen the first draft gave
                  them the same weight, and the number Isaac opens this page to
                  read is sell — cost is buying information. Markup rides under
                  cost as an annotation rather than claiming a fourth column;
                  that is the check-out's step-7 question answered. */}
              <div className="hidden text-right sm:block">
                <div className="tabular-nums text-sm text-muted">
                  {cost ?? <span>Not set</span>}
                </div>
                {markup && (
                  <div className="text-[11px] tabular-nums text-muted">+{markup}</div>
                )}
              </div>
              <div className="hidden text-right sm:block">
                {sell ? (
                  <span className="tabular-nums text-[15px] font-semibold text-text">{sell}</span>
                ) : (
                  <span className="text-sm text-muted">Not set</span>
                )}
              </div>
            </>
          );

          const identity = (
            <div className="min-w-0">
              <div className="flex flex-wrap items-baseline gap-x-2 gap-y-1">
                <span className="font-medium text-text">{product.name}</span>
                {!product.active && (
                  <span className="rounded bg-surface2 px-1.5 py-0.5 text-xs text-muted">
                    Archived
                  </span>
                )}
              </div>
              <p className="text-xs text-muted">
                {[product.category, product.unit].filter(Boolean).join(" · ") ||
                  "No category or unit"}
              </p>
            </div>
          );

          const mobilePrice = (
            <p className="mt-1 flex flex-wrap items-baseline gap-x-3 text-sm sm:hidden">
              {!canViewFinancials ? (
                <Restricted />
              ) : (
                <>
                  <span className="text-base font-semibold tabular-nums text-text">
                    {sell ?? <span className="text-sm font-normal text-muted">No sell price</span>}
                  </span>
                  <span className="text-xs tabular-nums text-muted">
                    {cost ? `cost ${cost}` : "no cost set"}
                    {markup ? ` · +${markup}` : ""}
                  </span>
                </>
              )}
            </p>
          );

          return (
            <li
              key={product.id}
              className={`border-b border-border last:border-0 ${
                product.active ? "" : "bg-surface2/50"
              }`}
            >
              {/* MOBILE: the whole row is one 56dp+ target that opens the edit
                  form in place. Seen at 375px, the first draft spent roughly
                  half of every card on an Edit/Archive/Delete button group,
                  which on a 60-item catalog is a dozen screens of buttons
                  between you and the price you came to read. Archive and
                  Delete moved INTO that edit form — one tap further, nothing
                  removed (§2.6), nothing disabled (§2.8), and the explicit
                  Edit action §2.8's 7/24 clarification asks for on established
                  reference data is now the whole card instead of a 12px link. */}
              {canManageCatalog ? (
                <Link
                  href={href({ edit: product.id })}
                  className="flex min-h-14 items-center gap-3 px-4 py-3 sm:hidden"
                >
                  <span className="min-w-0 flex-1">
                    {identity}
                    {mobilePrice}
                  </span>
                  <span aria-hidden="true" className="shrink-0 text-lg text-muted">
                    ›
                  </span>
                </Link>
              ) : (
                <div className="px-4 py-3 sm:hidden">
                  {identity}
                  {mobilePrice}
                </div>
              )}

              {/* DESKTOP: room for the three controls, and a mouse does not
                  mis-tap. Same actions, laid out as columns. */}
              <div className="hidden px-4 py-3 sm:grid sm:grid-cols-[minmax(0,1fr)_7rem_7rem_13rem] sm:items-center sm:gap-4">
                {identity}
                {money}
                <div className="flex items-center justify-end gap-2">
                  {!canManageCatalog ? (
                    <span className="text-xs text-muted">View only</span>
                  ) : confirmingDelete === product.id ? (
                    <DeleteConfirm orgId={orgId} product={product} href={href} />
                  ) : (
                    <>
                      <Link
                        href={href({ edit: product.id })}
                        className="inline-flex h-9 items-center rounded-md border border-border px-3 text-sm font-medium text-text"
                      >
                        Edit
                      </Link>
                      <ArchiveButton orgId={orgId} product={product} className="h-9 rounded-md px-3 text-sm text-muted hover:text-text" />
                      {/* Delete is not a peer of Edit and does not look like
                          one — no border, warn-coloured, and it opens a
                          confirm rather than deleting. It was a 12px text link
                          8px from Archive until today. */}
                      <Link
                        href={href({ confirm: product.id })}
                        aria-label={`Delete ${product.name}`}
                        /* Muted at rest, warn on hover. Seen on screen, seven
                           orange "Delete"s down the right edge made the most
                           destructive action the most colourful thing in the
                           list. The warn colour belongs at the moment of
                           danger — which is the confirm — not permanently. */
                        className="inline-flex h-9 items-center rounded-md px-3 text-sm text-muted hover:text-warn"
                      >
                        Delete
                      </Link>
                    </>
                  )}
                </div>
              </div>
            </li>
          );
        })}
      </ul>
    </div>
  );
}

// "Restricted", not "—" and not an absent column. The em-dash and the missing
// column both say "there is nothing here"; only "Restricted" says the true
// thing, which is that there IS a price and this role does not see it.
export function Restricted() {
  return (
    <span className="inline-block rounded bg-surface2 px-1.5 py-0.5 text-xs text-muted">
      Restricted
    </span>
  );
}


export function ArchiveButton({
  orgId,
  product,
  className,
}: {
  orgId: string;
  product: Product;
  className: string;
}) {
  return (
    <form action={setProductActive}>
      <input type="hidden" name="orgId" value={orgId} />
      <input type="hidden" name="productId" value={product.id} />
      <input type="hidden" name="active" value={product.active ? "false" : "true"} />
      <button type="submit" className={className}>
        {product.active ? "Archive" : "Restore"}
      </button>
    </form>
  );
}

export function DeleteConfirm({
  orgId,
  product,
  href,
}: {
  orgId: string;
  product: Product;
  href: (overrides: Record<string, string | null>) => string;
}) {
  // Two taps, and the second one says what it will do rather than "OK".
  // SCOPE §2.8's 7/24 clarification: "never block" is not "never confirm" —
  // established reference data gets an explicit action so a stray thumb on a
  // job site cannot destroy it. The RPC still refuses when estimate lines
  // reference the item, and names the count.
  return (
    <>
      <form action={deleteProduct}>
        <input type="hidden" name="orgId" value={orgId} />
        <input type="hidden" name="productId" value={product.id} />
        <button
          type="submit"
          className="min-h-14 rounded-md bg-warn px-3 text-sm font-medium text-white sm:min-h-0 sm:h-9"
        >
          Delete for good
        </button>
      </form>
      <Link
        href={href({ confirm: null })}
        className="inline-flex min-h-14 items-center rounded-md border border-border px-3 text-sm font-medium text-text sm:min-h-0 sm:h-9"
      >
        Cancel
      </Link>
    </>
  );
}
