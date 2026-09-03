import Link from "next/link";

// The find-and-filter bar. Extracted with CatalogList during the U-W1.2 design
// pass for the same reason: this page is behind auth, and a control nobody has
// looked at is how the catalog got called "a table, not a designed surface" in
// the first place.
//
// Everything here is a GET form or a link. No client JS: it survives a reload,
// the browser's own back button undoes a search, and it works on a phone with a
// bad connection halfway through hydrating.
export function CatalogToolbar({
  base,
  query,
  categories,
  activeCategory,
  showInactive,
  href,
}: {
  base: string;
  query: string;
  categories: string[];
  activeCategory: string;
  showInactive: boolean;
  href: (overrides: Record<string, string | null>) => string;
}) {
  return (
    <div className="flex flex-col gap-3">
      <form method="GET" action={base} className="flex items-center gap-2">
        {showInactive && <input type="hidden" name="inactive" value="1" />}
        {activeCategory && <input type="hidden" name="cat" value={activeCategory} />}
        <input
          type="search"
          name="q"
          defaultValue={query}
          placeholder="Search items…"
          aria-label="Search catalog items"
          // text-base below sm: iOS Safari zooms the viewport when a focused
          // input's font-size is under 16px, and on a driveway tablet that
          // means the page jumps every time you tap the search box.
          className="min-h-14 w-full flex-1 rounded-md border border-border bg-surface px-3 text-base text-text outline-none placeholder:text-muted focus:border-accent sm:h-10 sm:min-h-0 sm:text-sm"
        />
        <button
          type="submit"
          className="min-h-14 shrink-0 rounded-md border border-border px-4 text-sm font-medium text-text sm:h-10 sm:min-h-0"
        >
          Search
        </button>
      </form>

      {categories.length > 0 && (
        // Categories come from the WHOLE list, not the filtered one — a chip
        // that vanishes because you typed in the search box is a chip you
        // cannot use to get back out of the search.
        <div className="flex flex-wrap items-center gap-2">
          <Chip href={href({ cat: null })} on={!activeCategory}>
            All
          </Chip>
          {categories.map((c) => (
            <Chip key={c} href={href({ cat: c })} on={activeCategory === c}>
              {c}
            </Chip>
          ))}
        </div>
      )}
    </div>
  );
}

export function CatalogStatusBar({
  showInactive,
  shown,
  total,
  filtered,
  href,
}: {
  showInactive: boolean;
  shown: number;
  total: number;
  filtered: boolean;
  href: (overrides: Record<string, string | null>) => string;
}) {
  return (
    <div className="flex flex-wrap items-center justify-between gap-x-4 gap-y-2 border-b border-border pb-2 text-sm">
      <div className="flex items-center gap-1 rounded-md border border-border p-0.5">
        <Seg href={href({ inactive: null })} on={!showInactive}>
          Active
        </Seg>
        <Seg href={href({ inactive: "1" })} on={showInactive}>
          Incl. archived
        </Seg>
      </div>
      <span className="text-muted">
        {filtered ? (
          <>
            {shown} of {total} item{total === 1 ? "" : "s"} ·{" "}
            <Link href={href({ q: null, cat: null })} className="text-accent-strong hover:underline">
              clear
            </Link>
          </>
        ) : (
          <>
            {total} item{total === 1 ? "" : "s"}
          </>
        )}
      </span>
    </div>
  );
}

function Chip({
  href,
  on,
  children,
}: {
  href: string;
  on: boolean;
  children: React.ReactNode;
}) {
  return (
    <Link
      href={href}
      className={`inline-flex min-h-11 items-center rounded-full border px-3 text-sm sm:h-8 sm:min-h-0 ${
        on
          ? "border-accent bg-accent-soft font-medium text-accent-strong"
          : "border-border text-muted hover:text-text"
      }`}
    >
      {children}
    </Link>
  );
}

function Seg({
  href,
  on,
  children,
}: {
  href: string;
  on: boolean;
  children: React.ReactNode;
}) {
  return (
    <Link
      href={href}
      className={`inline-flex min-h-11 items-center rounded px-3 text-sm sm:h-8 sm:min-h-0 ${
        on ? "bg-accent-soft font-medium text-accent-strong" : "text-muted hover:text-text"
      }`}
    >
      {children}
    </Link>
  );
}
