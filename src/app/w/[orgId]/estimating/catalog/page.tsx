import Link from "next/link";
import { requireModuleAccess } from "@/lib/workspace/context";
import { formatMoney } from "@/lib/crm/stages";
import type { Database } from "@/lib/supabase/database.types";
import {
  createProduct,
  updateProduct,
  setProductActive,
  deleteProduct,
} from "@/lib/catalog/actions";

type Product = Database["public"]["Tables"]["products"]["Row"];

// A2.1 — the tenant-owned catalog. It lives UNDER estimating rather than behind
// a new module key on purpose: it prices estimate lines, `estimating` already
// carries the entitlement x role x view_estimates gate this page needs, and a
// new module key would mean a tenant_modules change for every tenant plus a
// registry entry — scope growth for no access-control gain. A `field` member
// never reaches this route because modulesVisibleForRole('field') returns
// ['field'] only, so the guard redirects before any query runs.
//
// MONEY: cost/sell/markup are job money under constraint 7. can_view_financials()
// gates them, NOT has_capability() directly — after A2.0 the former is a thin
// wrapper over the latter, so this is about which NAME the code depends on, and
// the closed-default name is the one that reads correctly to whoever maintains
// it. When it is false the money COLUMNS are dropped from the table entirely
// rather than rendered as "—", following DealCard's precedent: an em-dash
// implies "no value set" when the real reason is "not visible to you".

export default async function CatalogPage({
  params,
  searchParams,
}: {
  params: { orgId: string };
  searchParams: { edit?: string; error?: string; inactive?: string };
}) {
  const ctx = await requireModuleAccess(params.orgId, "estimating");
  const supabase = ctx.supabase;

  const showInactive = searchParams.inactive === "1";

  const [{ data: productRows }, { data: financials }] = await Promise.all([
    // Single security-definer RPC rather than a direct select, because the
    // money-nulling for a caller without financials lives in the RPC body —
    // the second of the two layers. The RESTRICTIVE policy is the first.
    supabase.rpc("list_products", {
      p_org_id: params.orgId,
      p_include_inactive: showInactive,
    }),
    supabase.rpc("can_view_financials", { p_org_id: params.orgId }),
  ]);

  const products = (productRows ?? []) as Product[];
  const canViewFinancials = financials === true;
  const editing = searchParams.edit
    ? products.find((p) => p.id === searchParams.edit) ?? null
    : null;

  return (
    <div className="flex h-full flex-col gap-4">
      <div className="flex items-start justify-between gap-4">
        <div>
          <h1 className="text-2xl font-semibold text-text">Product catalog</h1>
          <p className="text-sm text-muted">{ctx.active.org_name}</p>
        </div>
        <Link
          href={`/w/${params.orgId}/estimating`}
          className="text-sm text-accent-strong hover:underline"
        >
          Back to estimating
        </Link>
      </div>

      {searchParams.error && (
        <p className="rounded-lg border border-warn bg-warn-soft px-4 py-3 text-sm text-text">
          {searchParams.error}
        </p>
      )}

      {/* Create. Never disabled and never gated on the list being empty
          (SCOPE §2.8 — guidance is advisory, the software does not block). */}
      <form
        action={createProduct}
        className="rounded-lg border border-border bg-surface p-4"
      >
        <input type="hidden" name="orgId" value={params.orgId} />
        <div className="flex flex-wrap items-end gap-3">
          <Field label="Name" name="name" required className="min-w-[14rem] flex-1" />
          <Field label="Category" name="category" list="catalog-categories" />
          <Field label="Unit" name="unit" list="catalog-units" />
          {canViewFinancials && (
            <>
              <Field label="Cost" name="cost" type="number" step="0.01" />
              <Field label="Sell" name="sell" type="number" step="0.01" />
            </>
          )}
          <button
            type="submit"
            className="h-10 rounded-md bg-accent-strong px-4 text-sm font-medium text-white"
          >
            Add item
          </button>
        </div>
        {/* Free text with suggestions, never a closed list — the same decision
            §5.1 recorded for work-order `trade`: tenants do not share a
            category or unit vocabulary, so a hardcoded <select> would undo
            the config-driven model in the UI layer. */}
        <datalist id="catalog-categories">
          {Array.from(
            new Set(
              products
                .map((p) => p.category)
                .filter((c): c is string => Boolean(c))
            )
          ).map((c) => (
            <option key={c} value={c} />
          ))}
        </datalist>
        <datalist id="catalog-units">
          {["ea", "sq", "lf", "sf", "hr", "day", "roll", "bundle"].map((u) => (
            <option key={u} value={u} />
          ))}
        </datalist>
      </form>

      <div className="flex items-center gap-3 text-sm">
        <Link
          href={`/w/${params.orgId}/estimating/catalog${showInactive ? "" : "?inactive=1"}`}
          className="text-accent-strong hover:underline"
        >
          {showInactive ? "Hide archived items" : "Show archived items"}
        </Link>
        <span className="text-muted">
          {products.length} item{products.length === 1 ? "" : "s"}
        </span>
      </div>

      {products.length === 0 ? (
        <p className="text-sm text-muted">
          {showInactive
            ? "No catalog items yet, archived or otherwise. Add the first one above."
            : "No active catalog items yet. Add one above — you can price an estimate line from it once it exists."}
        </p>
      ) : (
        <div className="overflow-x-auto rounded-lg border border-border bg-surface">
          <table className="w-full text-sm">
            <thead className="border-b border-border text-left text-xs uppercase tracking-wide text-muted">
              <tr>
                <th className="px-4 py-2">Name</th>
                <th className="px-4 py-2">Category</th>
                <th className="px-4 py-2">Unit</th>
                {canViewFinancials && (
                  <>
                    <th className="px-4 py-2 text-right">Cost</th>
                    <th className="px-4 py-2 text-right">Sell</th>
                    <th className="px-4 py-2 text-right">Markup</th>
                  </>
                )}
                <th className="px-4 py-2" />
              </tr>
            </thead>
            <tbody>
              {products.map((product) =>
                editing?.id === product.id ? (
                  <tr key={product.id} className="border-b border-border last:border-0">
                    <td colSpan={canViewFinancials ? 7 : 4} className="px-4 py-3">
                      <form action={updateProduct} className="flex flex-wrap items-end gap-3">
                        <input type="hidden" name="orgId" value={params.orgId} />
                        <input type="hidden" name="productId" value={product.id} />
                        <Field label="Name" name="name" required defaultValue={product.name} className="min-w-[14rem] flex-1" />
                        <Field label="Category" name="category" defaultValue={product.category ?? ""} />
                        <Field label="Unit" name="unit" defaultValue={product.unit ?? ""} />
                        {canViewFinancials && (
                          <>
                            <Field label="Cost" name="cost" type="number" step="0.01" defaultValue={product.cost ?? ""} />
                            <Field label="Sell" name="sell" type="number" step="0.01" defaultValue={product.sell ?? ""} />
                          </>
                        )}
                        <button type="submit" className="h-10 rounded-md bg-accent-strong px-4 text-sm font-medium text-white">
                          Save
                        </button>
                        <Link
                          href={`/w/${params.orgId}/estimating/catalog`}
                          className="h-10 rounded-md border border-border px-4 text-sm leading-10 text-muted"
                        >
                          Cancel
                        </Link>
                      </form>
                    </td>
                  </tr>
                ) : (
                  <tr key={product.id} className="border-b border-border last:border-0">
                    <td className="px-4 py-3 text-text">
                      {product.name}
                      {!product.active && (
                        <span className="ml-2 rounded bg-surface2 px-1.5 py-0.5 text-xs text-muted">
                          Archived
                        </span>
                      )}
                    </td>
                    <td className="px-4 py-3 text-muted">{product.category ?? "—"}</td>
                    <td className="px-4 py-3 text-muted">{product.unit ?? "—"}</td>
                    {canViewFinancials && (
                      <>
                        <td className="px-4 py-3 text-right font-mono text-text">{formatMoney(product.cost)}</td>
                        <td className="px-4 py-3 text-right font-mono text-text">{formatMoney(product.sell)}</td>
                        <td className="px-4 py-3 text-right font-mono text-muted">
                          {product.markup === null ? "—" : `${product.markup}%`}
                        </td>
                      </>
                    )}
                    <td className="px-4 py-3">
                      <div className="flex items-center justify-end gap-2">
                        <Link
                          href={`/w/${params.orgId}/estimating/catalog?edit=${product.id}${showInactive ? "&inactive=1" : ""}`}
                          className="text-xs text-accent-strong hover:underline"
                        >
                          Edit
                        </Link>
                        <form action={setProductActive}>
                          <input type="hidden" name="orgId" value={params.orgId} />
                          <input type="hidden" name="productId" value={product.id} />
                          <input type="hidden" name="active" value={product.active ? "false" : "true"} />
                          <button type="submit" className="text-xs text-muted hover:underline">
                            {product.active ? "Archive" : "Restore"}
                          </button>
                        </form>
                        <form action={deleteProduct}>
                          <input type="hidden" name="orgId" value={params.orgId} />
                          <input type="hidden" name="productId" value={product.id} />
                          <button type="submit" className="text-xs text-warn hover:underline">
                            Delete
                          </button>
                        </form>
                      </div>
                    </td>
                  </tr>
                )
              )}
            </tbody>
          </table>
        </div>
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
        className="h-10 rounded-md border border-border bg-surface px-3 text-sm text-text"
      />
    </label>
  );
}
