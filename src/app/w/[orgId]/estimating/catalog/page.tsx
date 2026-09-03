import Link from "next/link";
import { requireModuleAccess } from "@/lib/workspace/context";
import { CatalogList, ArchiveButton, DeleteConfirm } from "@/components/catalog/CatalogList";
import { CatalogToolbar, CatalogStatusBar } from "@/components/catalog/CatalogToolbar";
import type { Database } from "@/lib/supabase/database.types";
import { createProduct, updateProduct } from "@/lib/catalog/actions";
import { PriceFields } from "@/components/catalog/PriceFields";

type Product = Database["public"]["Tables"]["products"]["Row"];

// A2.1 — the tenant-owned catalog. It lives UNDER estimating rather than behind
// a new module key on purpose: it prices estimate lines, `estimating` already
// carries the entitlement x role x view_estimates gate this page needs, and a
// new module key would mean a tenant_modules change for every tenant plus a
// registry entry — scope growth for no access-control gain. A `field` member
// never reaches this route because modulesVisibleForRole('field') returns
// ['field'] only, so the guard redirects before any query runs.
//
// ---------------------------------------------------------------------------
// U-W1.2 DESIGN PASS (2026-09-03). This page shipped 2026-08-26 and its own
// author's report that day called it "a table, not a designed surface." It had
// had no browser check-out since. What changed, and why — read as Isaac, a
// roofing company owner pricing a job, not as someone admiring a table:
//
// 1. SEARCH. The single largest defect. A real catalog is 60-200 items and the
//    only way to find one was to scroll. Name/category/unit substring search
//    plus category chips, both server-rendered off searchParams so they work
//    with JS off and survive a reload.
// 2. CENTS. formatMoney() carries maximumFractionDigits: 0 — job money. Unit
//    price is not job money. See @/lib/catalog/format.
// 3. MONEY IS SANS (controller decision 1.1) — mono's full-width comma renders
//    "$3,100" as "$3 , 100". tabular-nums does the aligning mono was here for.
// 4. NO HORIZONTAL SCROLL. The <table> is gone. One <ul> that stacks as cards
//    below sm and becomes an aligned grid at sm+ — same DOM, no duplicate
//    markup, and the page body can never scroll sideways (check-out step 7's
//    phone question).
// 5. MARKUP LEFT THE LIST (check-out step 7 asked this directly). It is an
//    AUTHORING concern — you set it, you don't read it. It keeps its full
//    bidirectional treatment in the edit form, and appears on the list only as
//    a small annotation under cost. That returned a whole column of width.
// 6. TOUCH TARGETS. Edit/Archive/Delete were 12px text links sitting 8px apart,
//    with Delete unguarded next to Archive. On a driveway tablet in gloves that
//    is a mis-tap waiting to destroy reference data. They are now 56dp controls
//    below sm, and Delete takes two taps — see the `confirm` searchParam.
//
// MONEY VISIBILITY: cost/sell are job money under constraint 7, gated on
// can_view_financials() — NOT has_capability() directly. When it is false the
// price column is STILL RENDERED and reads "Restricted".
//
//   This REVERSES what this file did on 2026-08-26, and the reversal is the
//   point. The old code dropped the money columns entirely, reasoning (in a
//   comment, following DealCard) that an em-dash implies "no value set" when
//   the truth is "not visible to you". That reasoning was right about the
//   em-dash and wrong about the remedy: dropping the column says even less
//   than "—" did. A user sees a catalog with no prices anywhere and cannot
//   tell whether this tenant prices its items at all. Never infer "does not
//   exist" from "cannot see" — a restricted price says restricted.
//
//   NOT EXERCISED. No user with `estimating` visible and can_view_financials()
//   false exists to log in as, so this branch is reasoned and type-checked,
//   never seen. It is stated here rather than reported as a pass.
// ---------------------------------------------------------------------------

export default async function CatalogPage({
  params,
  searchParams,
}: {
  params: { orgId: string };
  searchParams: {
    edit?: string;
    error?: string;
    inactive?: string;
    q?: string;
    cat?: string;
    add?: string;
    confirm?: string;
  };
}) {
  const ctx = await requireModuleAccess(params.orgId, "estimating");
  const supabase = ctx.supabase;

  const showInactive = searchParams.inactive === "1";
  const query = (searchParams.q ?? "").trim();
  const activeCategory = searchParams.cat ?? "";

  const [{ data: productRows }, { data: financials }, { data: canManage }] = await Promise.all([
    // Single security-definer RPC rather than a direct select, because the
    // money-nulling for a caller without financials lives in the RPC body —
    // the second of the two layers. The RESTRICTIVE policy is the first.
    supabase.rpc("list_products", {
      p_org_id: params.orgId,
      p_include_inactive: showInactive,
    }),
    supabase.rpc("can_view_financials", { p_org_id: params.orgId }),
    // A2.1c / Step 2 — Jacob's decision (2026-08-26): the person who builds
    // estimates maintains the item list, so catalog writes moved off
    // manager-tier onto the `manage_catalog` capability, which office roles
    // now carry by default. Read access is unchanged and is NOT gated on it.
    supabase.rpc("has_capability", { p_org_id: params.orgId, p_capability: "manage_catalog" }),
  ]);

  const all = (productRows ?? []) as Product[];
  const canViewFinancials = financials === true;
  const canManageCatalog = canManage === true;

  // Categories come from the WHOLE list, not the filtered one — a chip that
  // vanishes because you typed in the search box is a chip you cannot use to
  // clear the search.
  const categories = Array.from(
    new Set(all.map((p) => p.category).filter((c): c is string => Boolean(c)))
  ).sort((a, b) => a.localeCompare(b));

  // Filtering happens here rather than in list_products because the RPC has no
  // search parameter and adding one is schema work (Track S). At BMR's current
  // catalog size that is the right trade; at a few thousand items it is not,
  // and this comment is where the next person should start.
  const needle = query.toLowerCase();
  const products = all.filter((p) => {
    if (activeCategory && (p.category ?? "") !== activeCategory) return false;
    if (!needle) return true;
    return [p.name, p.category, p.unit]
      .filter((v): v is string => Boolean(v))
      .some((v) => v.toLowerCase().includes(needle));
  });

  const editing = searchParams.edit
    ? all.find((p) => p.id === searchParams.edit) ?? null
    : null;
  const confirmingDelete = searchParams.confirm ?? null;

  // Every control on this page is a GET link, so each one has to carry the
  // rest of the page's state or it silently throws the user's search away.
  const base = `/w/${params.orgId}/estimating/catalog`;
  function href(overrides: Record<string, string | null>) {
    const next = new URLSearchParams();
    const current: Record<string, string> = {};
    if (showInactive) current.inactive = "1";
    if (query) current.q = query;
    if (activeCategory) current.cat = activeCategory;
    for (const [k, v] of Object.entries({ ...current, ...overrides })) {
      if (v) next.set(k, v);
    }
    const qs = next.toString();
    return qs ? `${base}?${qs}` : base;
  }

  // The add form opens on request, and opens on its own when there is nothing
  // to look at — an empty catalog has no list to get out of the way of. This
  // is disclosure, not blocking (SCOPE §2.8): the button that opens it is
  // always present and never disabled.
  const addOpen = searchParams.add === "1" || (all.length === 0 && canManageCatalog);

  return (
    <div className="mx-auto flex h-full w-full max-w-5xl flex-col gap-4">
      {/* Breadcrumb above the title, not a link floating at the right edge.
          Seen on screen, "Back to estimating" sitting opposite the h1 read as
          a peer of the page title rather than as the way out of it. */}
      <Link
        href={`/w/${params.orgId}/estimating`}
        className="inline-flex min-h-11 items-center self-start text-sm text-muted hover:text-accent-strong sm:min-h-0"
      >
        ← Estimating
      </Link>

      <div className="flex items-start justify-between gap-4">
        <div className="min-w-0">
          <h1 className="text-2xl font-semibold text-text">Product catalog</h1>
          <p className="text-sm text-muted">
            {ctx.active.org_name} · the item list your estimates price from
          </p>
        </div>
        {/* Add lives in the title row rather than in the vertical flow. On
            screen it had been a full-width accent button sitting BETWEEN the
            category chips and the active/archived switch — the loudest thing
            on the page, splitting the two filter controls, for the action
            performed least often. Hidden from a caller without
            `manage_catalog`: §2.8 forbids blocking an action the user is
            permitted to take, not hiding one they are not. */}
        {canManageCatalog && !addOpen && (
          <Link
            href={href({ add: "1" })}
            className="inline-flex min-h-14 shrink-0 items-center rounded-md bg-accent-strong px-4 text-sm font-medium text-white sm:h-10 sm:min-h-0"
          >
            + Add item
          </Link>
        )}
      </div>

      {searchParams.error && (
        <p className="rounded-lg border border-warn bg-warn-soft px-4 py-3 text-sm text-text">
          {searchParams.error}
        </p>
      )}

      {all.length > 0 && (
        <CatalogToolbar
          base={base}
          query={query}
          categories={categories}
          activeCategory={activeCategory}
          showInactive={showInactive}
          href={href}
        />
      )}

      {canManageCatalog && addOpen && (
        <form
          action={createProduct}
          className="rounded-lg border border-accent bg-surface p-4"
        >
          <input type="hidden" name="orgId" value={params.orgId} />
          <div className="mb-3 flex items-center justify-between gap-3">
            <h2 className="text-sm font-semibold text-text">New catalog item</h2>
            {all.length > 0 && (
              <Link
                href={href({ add: null })}
                className="inline-flex min-h-11 items-center text-xs text-muted hover:underline"
              >
                Close
              </Link>
            )}
          </div>
          <div className="flex flex-wrap items-end gap-3">
            <Field label="Name" name="name" required className="min-w-[14rem] flex-1" />
            <Field label="Category" name="category" list="catalog-categories" defaultValue={activeCategory} />
            <Field label="Unit" name="unit" list="catalog-units" />
            {canViewFinancials && <PriceFields />}
            <button
              type="submit"
              className="min-h-14 rounded-md bg-accent-strong px-4 text-sm font-medium text-white sm:min-h-0 sm:h-10"
            >
              Add item
            </button>
          </div>
          {!canViewFinancials && (
            <p className="mt-3 text-xs text-muted">
              Pricing is restricted for your role. This item will be created without
              a price; someone who can see pricing can set it.
            </p>
          )}
          {/* Free text with suggestions, never a closed list — the same decision
              §5.1 recorded for work-order `trade`: tenants do not share a
              category or unit vocabulary, so a hardcoded <select> would undo
              the config-driven model in the UI layer. */}
          <datalist id="catalog-categories">
            {categories.map((c) => (
              <option key={c} value={c} />
            ))}
          </datalist>
          <datalist id="catalog-units">
            {["ea", "sq", "lf", "sf", "hr", "day", "roll", "bundle"].map((u) => (
              <option key={u} value={u} />
            ))}
          </datalist>
        </form>
      )}

      <CatalogStatusBar
        showInactive={showInactive}
        shown={products.length}
        total={all.length}
        filtered={Boolean(query || activeCategory)}
        href={href}
      />

      {all.length === 0 ? (
        <p className="text-sm text-muted">
          {!canManageCatalog
            ? // A view-only reader has no add form above them, so telling them
              // to use it would be pointing at a control that is not there.
              showInactive
              ? "This tenant has no catalog items, archived or otherwise."
              : "This tenant has no active catalog items yet."
            : showInactive
              ? "No catalog items yet, archived or otherwise. Add the first one above."
              : "No active catalog items yet. Add one above — you can price an estimate line from it once it exists."}
        </p>
      ) : products.length === 0 ? (
        <p className="text-sm text-muted">
          Nothing matches{query ? ` “${query}”` : ""}
          {activeCategory ? ` in ${activeCategory}` : ""}.{" "}
          <Link href={href({ q: null, cat: null })} className="text-accent-strong hover:underline">
            Clear the filters
          </Link>{" "}
          to see all {all.length}.
          {!showInactive && (
            <>
              {" "}
              It may be archived —{" "}
              <Link href={href({ inactive: "1" })} className="text-accent-strong hover:underline">
                include archived items
              </Link>
              .
            </>
          )}
        </p>
      ) : (
        <CatalogList
          orgId={params.orgId}
          products={products}
          canViewFinancials={canViewFinancials}
          canManageCatalog={canManageCatalog}
          confirmingDelete={confirmingDelete}
          editingId={editing?.id ?? null}
          href={href}
          editSlot={
            editing && (
              <form action={updateProduct} className="flex flex-wrap items-end gap-3">
                <input type="hidden" name="orgId" value={params.orgId} />
                <input type="hidden" name="productId" value={editing.id} />
                <Field
                  label="Name"
                  name="name"
                  required
                  defaultValue={editing.name}
                  className="min-w-[14rem] flex-1"
                />
                <Field
                  label="Category"
                  name="category"
                  defaultValue={editing.category ?? ""}
                  list="catalog-categories-edit"
                />
                <Field label="Unit" name="unit" defaultValue={editing.unit ?? ""} />
                {canViewFinancials && (
                  <PriceFields
                    defaultCost={editing.cost}
                    defaultSell={editing.sell}
                    defaultMarkup={editing.markup}
                  />
                )}
                <button
                  type="submit"
                  className="min-h-14 rounded-md bg-accent-strong px-4 text-sm font-medium text-white sm:min-h-0 sm:h-10"
                >
                  Save
                </button>
                <Link
                  href={href({ edit: null })}
                  className="inline-flex min-h-14 items-center rounded-md border border-border px-4 text-sm text-muted sm:min-h-0 sm:h-10"
                >
                  Cancel
                </Link>
                <datalist id="catalog-categories-edit">
                  {categories.map((c) => (
                    <option key={c} value={c} />
                  ))}
                </datalist>
              </form>
            )
          }
          editActions={
            editing && (
              /* Archive and Delete live here as well as on the desktop row,
                 because below sm the row IS the Edit link and has no button
                 group of its own. Nothing is lost on a phone — §2.6 is full
                 CRUD from the UI, not full CRUD from a particular viewport. */
              <div className="flex flex-wrap items-center gap-2 border-t border-border pt-3">
                {confirmingDelete === editing.id ? (
                  <DeleteConfirm
                    orgId={params.orgId}
                    product={editing}
                    // Cancelling a delete from inside the edit form returns to
                    // the EDIT form, not to the list — the user backed out of
                    // one action, not two.
                    href={(o) => href({ ...o, edit: editing.id })}
                  />
                ) : (
                  <>
                    <ArchiveButton
                      orgId={params.orgId}
                      product={editing}
                      className="min-h-14 rounded-md border border-border px-4 text-sm text-text sm:min-h-0 sm:h-9"
                    />
                    <Link
                      href={href({ edit: editing.id, confirm: editing.id })}
                      className="inline-flex min-h-14 items-center rounded-md px-3 text-sm text-warn sm:min-h-0 sm:h-9"
                    >
                      Delete
                    </Link>
                  </>
                )}
              </div>
            )
          }
        />
      )}
    </div>
  );
}

function Field({
  label,
  className,
  ...props
}: {
  label: string;
  className?: string;
} & React.InputHTMLAttributes<HTMLInputElement>) {
  return (
    <label className={`flex flex-col gap-1 ${className ?? ""}`}>
      <span className="text-xs font-medium text-muted">{label}</span>
      <input
        {...props}
        // text-base below sm, not text-sm: iOS Safari zooms the whole viewport
        // when a focused input's font-size is under 16px, which on a driveway
        // tablet means the page jumps every time you tap a field.
        className="min-h-14 rounded-md border border-border bg-surface px-3 text-base text-text outline-none focus:border-accent sm:min-h-0 sm:h-10 sm:text-sm"
      />
    </label>
  );
}
