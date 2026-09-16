import { LinkSignForm } from "@/components/signing/LinkSignForm";
import {
  SIGN_OUTCOME_COPY,
  copyLineForSigner,
  isSignOutcome,
  type LinkView,
  type SigningDocument,
} from "@/lib/signing/link-states";

// Everything the customer signing page renders, for every state. Split from the
// route (src/app/sign/[token]/page.tsx) so each state can be rendered and measured
// without a live link. See that file for the property this page holds.

export function SigningView({
  view,
  token,
  searchParams,
}: {
  view: LinkView | "error";
  token: string;
  searchParams: { r?: string; copy?: string };
}) {
  const r = isSignOutcome(searchParams.r) ? searchParams.r : null;

  return (
    <main data-sign-state={view === "error" ? "error" : view.state} className="min-h-dvh bg-bg px-4 py-6">
      <div className="mx-auto flex w-full max-w-xl flex-col gap-5">
        {view === "error" ? (
          <Notice title="This page could not load">
            We couldn&rsquo;t reach the estimate just now. Nothing has been signed. Please try the link again in a
            few minutes.
          </Notice>
        ) : view.state === "unavailable" ? (
          <Notice title="This link can't be used">
            There is nothing to sign at this address. The link may be incomplete, it may have been cancelled, or a
            newer link may have replaced it. If you expected to sign an estimate, contact the business that sent it.
          </Notice>
        ) : view.state === "expired" ? (
          <Notice title="This signing link has expired">
            {view.expired_at ? (
              <>
                It stopped working on <Day iso={view.expired_at} />.{" "}
              </>
            ) : null}
            Nothing was signed. Ask {view.business ?? "the business that sent it"} to send you a new link.
          </Notice>
        ) : view.state === "already_signed" ? (
          r === "signed" ? (
            <Notice title="Signed — thank you" tone="done">
              Your signature was saved
              {view.signed_at ? (
                <>
                  {" "}
                  on <Day iso={view.signed_at} />
                </>
              ) : null}
              {view.business ? ` and ${view.business} has it` : ""}.{" "}
              {copyLineForSigner(searchParams.copy, view.business) ?? ""}
            </Notice>
          ) : (
            // A forged ?r=signed on an UNSIGNED link lands in `ready` below and
            // shows nothing extra: the "thank you" needs the database to agree.
            <Notice title="This estimate has already been signed" tone="done">
              {view.signed_at ? (
                <>
                  It was signed on <Day iso={view.signed_at} />.{" "}
                </>
              ) : null}
              There is nothing more to do here. For a copy, contact {view.business ?? "the business that sent it"}.
            </Notice>
          )
        ) : view.state === "document_changed" ? (
          <Notice title="This estimate has changed">
            {view.business ?? "The business"} changed the estimate after sending this link, so it can&rsquo;t be
            signed from here. Nothing was signed. Ask them to send it to you again.
          </Notice>
        ) : (
          <>
            <header>
              <p className="text-sm text-muted">{view.business ?? "Estimate"}</p>
              <h1 className="text-2xl font-semibold text-text">Review and sign</h1>
              <p className="mt-1 text-sm text-muted">
                This link works until <Day iso={view.expires_at} />.
              </p>
            </header>

            {r && r !== "signed" && (
              <p role="alert" className="rounded-lg border border-warn bg-warn-soft px-4 py-3 text-sm text-text">
                {SIGN_OUTCOME_COPY[r]}
              </p>
            )}

            <Document doc={view.document} />

            <section className="rounded-xl border border-border bg-surface p-4">
              <h2 className="mb-3 text-base font-semibold text-text">Sign</h2>
              <LinkSignForm
                token={token}
                documentVersion={view.document_version}
                // Measured 2026-09-16: `total` is presented_total, and it is null on an
                // estimate marked presented without present_estimate() pricing it. The
                // button then names no amount rather than printing "—" as a price.
                total={view.document.total != null ? money(view.document.total) : null}
              />
            </section>
          </>
        )}
      </div>
    </main>
  );
}

function Notice({ title, tone, children }: { title: string; tone?: "done"; children: React.ReactNode }) {
  return (
    <section
      role="status"
      className={`rounded-xl border px-4 py-5 ${tone === "done" ? "border-accent bg-accent-soft" : "border-border bg-surface"}`}
    >
      <h1 className="text-xl font-semibold text-text">{title}</h1>
      <p className="mt-2 text-base leading-relaxed text-text">{children}</p>
    </section>
  );
}

function Document({ doc }: { doc: SigningDocument }) {
  const lines = Array.isArray(doc.lines) ? doc.lines : [];
  return (
    <article className="rounded-xl border border-border bg-surface p-4">
      <div className="flex flex-wrap items-baseline justify-between gap-x-3 gap-y-1">
        <h2 className="text-lg font-semibold text-text">
          Estimate{doc.estimate_number ? ` ${doc.estimate_number}` : ""}
        </h2>
        {doc.estimate_date && (
          <p className="text-sm text-muted">
            <DateOnly value={doc.estimate_date} />
          </p>
        )}
      </div>
      {(doc.contact_name || doc.site_address) && (
        <div className="mt-2 text-sm text-text">
          {doc.contact_name && <p>{doc.contact_name}</p>}
          {doc.site_address && <p className="text-muted">{doc.site_address}</p>}
        </div>
      )}

      {/* Stacked rows, not a table: a four-column table does not fit a phone held
          in one hand, and a sideways scroll hides the prices. */}
      <ul className="mt-4 divide-y divide-border border-y border-border">
        {lines.map((l, i) => (
          <li key={i} className="flex flex-col gap-1 py-3">
            <div className="flex items-baseline justify-between gap-3">
              <p className="min-w-0 text-base text-text">{l.description || "Item"}</p>
              <p className="shrink-0 text-base font-medium tabular-nums text-text">{money(l.line_total)}</p>
            </div>
            <p className="text-sm tabular-nums text-muted">
              {qty(l.quantity)}
              {l.unit ? ` ${l.unit}` : ""} × {money(l.unit_price)}
            </p>
          </li>
        ))}
        {lines.length === 0 && <li className="py-3 text-sm text-muted">This estimate has no line items.</li>}
      </ul>

      <dl className="mt-3 flex flex-col gap-1 text-base">
        <Row label="Subtotal" value={money(doc.subtotal)} />
        {doc.tax_amount != null && Number(doc.tax_amount) !== 0 && (
          <Row label={doc.tax_rate != null ? `Tax (${qty(doc.tax_rate)}%)` : "Tax"} value={money(doc.tax_amount)} />
        )}
        <div className="mt-1 flex items-baseline justify-between border-t border-border pt-2">
          <dt className="font-semibold text-text">Total</dt>
          <dd className="text-xl font-semibold tabular-nums text-text">{money(doc.total)}</dd>
        </div>
      </dl>

      {doc.valid_until && (
        <p className="mt-3 text-sm text-muted">
          Valid until <DateOnly value={doc.valid_until} />.
        </p>
      )}
      {doc.notes_terms && (
        <div className="mt-4">
          <h3 className="text-sm font-semibold text-text">Notes and terms</h3>
          <p className="mt-1 whitespace-pre-line text-sm leading-relaxed text-text">{doc.notes_terms}</p>
        </div>
      )}
    </article>
  );
}

function Row({ label, value }: { label: string; value: string }) {
  return (
    <div className="flex items-baseline justify-between">
      <dt className="text-muted">{label}</dt>
      <dd className="tabular-nums text-text">{value}</dd>
    </div>
  );
}

// Money in sans with tabular figures (controller ruling); cents shown — this is
// the document a customer accepts, not a pipeline summary.
function money(v: number | string | null): string {
  if (v == null) return "—";
  const n = Number(v);
  if (!Number.isFinite(n)) return "—";
  return new Intl.NumberFormat("en-US", { style: "currency", currency: "USD" }).format(n);
}
function qty(v: number | string | null): string {
  if (v == null) return "—";
  const n = Number(v);
  return Number.isFinite(n) ? n.toString() : "—";
}
function Day({ iso }: { iso: string }) {
  return (
    <span className="whitespace-nowrap">
      {new Date(iso).toLocaleDateString("en-US", { year: "numeric", month: "long", day: "numeric", timeZone: "America/New_York" })}
    </span>
  );
}
function DateOnly({ value }: { value: string }) {
  const [y, m, d] = value.split("-").map(Number);
  return (
    <span className="whitespace-nowrap">
      {new Date(Date.UTC(y, m - 1, d)).toLocaleDateString("en-US", { year: "numeric", month: "long", day: "numeric", timeZone: "UTC" })}
    </span>
  );
}
