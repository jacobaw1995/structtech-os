import { EditableField } from "@/components/estimating/EditableField";
import { EstimateContactEditForm } from "@/components/estimating/EstimateContactEditForm";
import { LineItemsEditor } from "@/components/estimating/LineItemsEditor";
import { EstimateSignatureBlock } from "@/components/estimating/EstimateSignatureBlock";
import { buildDocumentLayout } from "@/lib/estimating/document-layout";
import {
  updateEstimateDocumentDetails,
  switchEstimateToManual,
  switchEstimateToGuided,
  voidEstimate,
  deleteEstimate,
  presentEstimate,
} from "@/lib/estimating/actions";
import type { EstimateBranding } from "@/lib/estimating/branding";
import type { Database } from "@/lib/supabase/database.types";

type Estimate = Database["public"]["Tables"]["estimates"]["Row"];
type LineItem = Database["public"]["Tables"]["estimate_line_items"]["Row"];
type Signature = Database["public"]["Tables"]["signatures"]["Row"];

// Chunk 5 — the canonical estimate page IS this document now (the wizard
// is gone). Every field renders from buildDocumentLayout() (document-layout
// .ts) for its DISPLAY string and for whether a section shows at all —
// EditableField instances still read/write the RAW estimate.* value
// directly (an input's defaultValue can't be a pre-formatted string), but
// never invent their own formatting or their own "should this show" logic
// separately from what the layout already decided. That's what keeps this
// file and pdf.ts from drifting: neither has an opinion the other doesn't
// share.
//
// `locked` (signed/void) still gates field editability, exactly as Chunks
// 1-4 established. `presentationMode` is new (Chunk 5): forces the SAME
// read-only rendering regardless of actual status (a draft shown to a
// customer mid-pitch still renders locked) and hides every operator-only
// control (void/delete/build-mode toggle/present button/scope-report
// banners/unpriced markers) — except the signature block, which stays
// fully live so the customer can actually sign at the kitchen table
// (Jacob's Chunk 5 correction — that IS the close).
export function EstimateDocument({
  orgId,
  estimate,
  lineItems,
  signature,
  branding,
  errorMessage,
  scopeUnmapped = [],
  scopeUnparseable = [],
  presentationMode = false,
}: {
  orgId: string;
  estimate: Estimate;
  lineItems: LineItem[];
  signature: Signature | null;
  branding: EstimateBranding;
  errorMessage?: string;
  scopeUnmapped?: string[];
  scopeUnparseable?: string[];
  presentationMode?: boolean;
}) {
  const locked = estimate.status === "signed" || estimate.status === "void";
  const effectivelyLocked = presentationMode || locked;
  const liveTotal = estimate.subtotal + (estimate.tax_amount ?? 0);

  const layout = buildDocumentLayout({
    estimate,
    lineItems,
    signature,
    branding,
    locked: effectivelyLocked,
    scopeUnmapped: presentationMode ? [] : scopeUnmapped,
    scopeUnparseable: presentationMode ? [] : scopeUnparseable,
  });

  const detailsHidden = { orgId, estimateId: estimate.id };
  const opsHidden = { orgId, estimateId: estimate.id };

  // Operator-control visibility — deliberately NOT all the same condition
  // as `effectivelyLocked`. Void must stay available even on a SIGNED
  // estimate (original StepPreliminary rule: "voiding a signed-then-
  // cancelled job is the case that needs to keep working at any status"),
  // so it can't just piggyback on `locked`.
  const showOperatorControls = !presentationMode;
  const canVoid = showOperatorControls && estimate.status !== "void";
  const canDelete = showOperatorControls && estimate.status !== "signed" && estimate.status !== "void";
  const canPresent = showOperatorControls && !locked;
  const canViewAsCustomer = showOperatorControls && estimate.presented_at != null;

  return (
    <div className="mx-auto flex w-full max-w-3xl flex-col gap-6 rounded-2xl border border-border bg-surface p-5 sm:p-8">
      {errorMessage && (
        <p className="rounded-md bg-warn-soft px-3 py-2 text-xs text-text">{errorMessage}</p>
      )}
      {showOperatorControls && (layout.advisories.unmapped.length > 0 || layout.advisories.unparseable.length > 0) && (
        <div className="flex flex-col gap-1 rounded-md bg-warn-soft px-3 py-2 text-xs text-text">
          {layout.advisories.unmapped.length > 0 && (
            <p>
              No line-item mapping configured for: {layout.advisories.unmapped.join(", ")}. Add these to
              this tenant&apos;s scope_line_items config, or they&apos;ll keep being skipped.
            </p>
          )}
          {layout.advisories.unparseable.length > 0 && (
            <p>Couldn&apos;t read a number for: {layout.advisories.unparseable.join(", ")} — skipped, not guessed.</p>
          )}
        </div>
      )}

      {/* Header */}
      <div className="flex flex-col justify-between gap-3 border-b border-border pb-5 sm:flex-row sm:items-start">
        <div>
          <p className="text-lg font-semibold text-text sm:text-xl">{layout.header.companyName}</p>
          {layout.header.companyContactLine && (
            <p className="mt-1 text-xs text-muted">{layout.header.companyContactLine}</p>
          )}
        </div>
        <div className="flex flex-col gap-1 sm:items-end">
          <div className="flex items-center gap-2">
            <span className="text-sm font-semibold uppercase tracking-wide text-accent-strong">
              Estimate
            </span>
            <span className="rounded-full bg-surface2 px-2 py-0.5 text-xs font-medium text-muted">
              {layout.header.statusLabel}
            </span>
            {canVoid && (
              <form action={voidEstimate}>
                <input type="hidden" name="orgId" value={opsHidden.orgId} />
                <input type="hidden" name="estimateId" value={opsHidden.estimateId} />
                <button type="submit" className="text-xs text-muted underline hover:text-warn">
                  Void
                </button>
              </form>
            )}
            {canDelete && (
              <form action={deleteEstimate}>
                <input type="hidden" name="orgId" value={opsHidden.orgId} />
                <input type="hidden" name="estimateId" value={opsHidden.estimateId} />
                <button type="submit" className="text-xs text-muted underline hover:text-warn">
                  Delete
                </button>
              </form>
            )}
          </div>
          {layout.header.estimateNumber && (
            <p className="font-mono text-sm text-text">{layout.header.estimateNumber}</p>
          )}
          <p className="flex items-center gap-1 text-xs text-muted">
            <EditableField
              key={`date-${estimate.id}-${estimate.estimate_date}`}
              value={estimate.estimate_date ?? ""}
              display={layout.header.estimateDate.value}
              placeholder="Add date"
              action={updateEstimateDocumentDetails}
              hidden={detailsHidden}
              name="estimate_date"
              type="date"
              locked={effectivelyLocked}
              className="text-xs text-muted"
            />
            {layout.header.validUntil && (
              <>
                <span>· valid until</span>
                <EditableField
                  key={`valid-${estimate.id}-${estimate.valid_until}`}
                  value={estimate.valid_until ?? ""}
                  display={layout.header.validUntil.value}
                  placeholder="—"
                  action={updateEstimateDocumentDetails}
                  hidden={detailsHidden}
                  name="valid_until"
                  type="date"
                  locked={effectivelyLocked}
                  className="text-xs text-muted"
                />
              </>
            )}
          </p>
        </div>
      </div>

      {/* Customer + job site */}
      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
        <div className="flex flex-col gap-1 rounded-lg bg-surface2 p-3">
          <p className="text-[10px] font-semibold uppercase tracking-wide text-muted">
            {layout.customer.sectionLabel} <span className="normal-case">— from lead</span>
          </p>
          {layout.customer.summaryLines.length === 0 ? (
            <p className="text-sm text-muted">—</p>
          ) : (
            layout.customer.summaryLines.map((line, i) => (
              <p key={i} className={i === 0 ? "text-sm font-semibold text-text" : "text-sm text-text"}>
                {line}
              </p>
            ))
          )}
          {!effectivelyLocked && layout.customer.fields && (
            <EstimateContactEditForm
              orgId={orgId}
              estimateId={estimate.id}
              company={layout.customer.fields.company.value}
              contactName={layout.customer.fields.contactName.value}
              phone={layout.customer.fields.phone.value}
              email={layout.customer.fields.email.value}
            />
          )}
        </div>

        <div className="flex flex-col gap-1 rounded-lg bg-surface2 p-3">
          <p className="text-[10px] font-semibold uppercase tracking-wide text-muted">
            {layout.jobSite.sectionLabel} <span className="normal-case">— from lead</span>
          </p>
          <EditableField
            key={`site-${estimate.id}-${estimate.site_address}`}
            value={estimate.site_address ?? ""}
            display={layout.jobSite.address.value || undefined}
            placeholder="Job site address"
            action={updateEstimateDocumentDetails}
            hidden={detailsHidden}
            name="site_address"
            locked={effectivelyLocked}
            className="text-sm text-text"
            block
          />
          {layout.jobSite.measurements && (
            <p className="flex items-center gap-1 font-mono text-xs text-muted">
              <EditableField
                key={`squares-${estimate.id}-${estimate.squares}`}
                value={estimate.squares != null ? String(estimate.squares) : ""}
                display={layout.jobSite.measurements.squares.value}
                placeholder="— sq"
                action={updateEstimateDocumentDetails}
                hidden={detailsHidden}
                name="squares"
                type="number"
                locked={effectivelyLocked}
                className="font-mono text-xs text-muted"
              />
              <span>· pitch</span>
              <EditableField
                key={`pitch-${estimate.id}-${estimate.pitch}`}
                value={estimate.pitch ?? ""}
                display={layout.jobSite.measurements.pitch.value}
                placeholder="—"
                action={updateEstimateDocumentDetails}
                hidden={detailsHidden}
                name="pitch"
                locked={effectivelyLocked}
                className="font-mono text-xs text-muted"
              />
            </p>
          )}
        </div>
      </div>

      {/* Line items */}
      {showOperatorControls && !locked && (
        <div className="flex items-center justify-between">
          <p className="text-[10px] font-semibold uppercase tracking-wide text-muted">Build mode</p>
          <div className="flex items-center gap-0.5 rounded-full border border-border p-0.5 text-xs">
            <form action={switchEstimateToManual}>
              <input type="hidden" name="orgId" value={orgId} />
              <input type="hidden" name="estimateId" value={estimate.id} />
              <button
                type="submit"
                className={`rounded-full px-2.5 py-1 font-medium ${
                  estimate.build_mode !== "guided" ? "bg-accent-strong text-white" : "text-muted hover:text-text"
                }`}
              >
                Manual
              </button>
            </form>
            <form action={switchEstimateToGuided}>
              <input type="hidden" name="orgId" value={orgId} />
              <input type="hidden" name="estimateId" value={estimate.id} />
              <button
                type="submit"
                className={`rounded-full px-2.5 py-1 font-medium ${
                  estimate.build_mode === "guided" ? "bg-accent-strong text-white" : "text-muted hover:text-text"
                }`}
              >
                Guided
              </button>
            </form>
          </div>
        </div>
      )}
      <LineItemsEditor
        orgId={orgId}
        estimateId={estimate.id}
        lineItems={lineItems}
        locked={effectivelyLocked}
      />

      {/* Totals */}
      <div className="flex flex-col items-end gap-1 border-t border-border pt-4">
        <div className="flex w-full max-w-xs justify-between text-sm text-text sm:w-56">
          <span className="text-muted">Subtotal</span>
          <span className="font-mono">{layout.totals.subtotal}</span>
        </div>
        {layout.totals.tax && (
          <div className="flex w-full max-w-xs justify-between text-sm text-text sm:w-56">
            <span className="flex items-center gap-1 text-muted">
              Tax (
              <EditableField
                key={`tax-${estimate.id}-${estimate.tax_rate}`}
                value={estimate.tax_rate != null ? String(estimate.tax_rate * 100) : ""}
                display={layout.totals.tax.percentField.value}
                placeholder="0"
                action={updateEstimateDocumentDetails}
                hidden={detailsHidden}
                name="tax_rate_percent"
                type="number"
                locked={effectivelyLocked}
                className="w-8 text-muted"
                align="right"
              />
              %)
            </span>
            <span className="font-mono">{layout.totals.tax.amount}</span>
          </div>
        )}
        <div className="flex w-full max-w-xs justify-between border-t border-border pt-1 text-base font-semibold text-text sm:w-56">
          <span>Total</span>
          <span className="font-mono">{layout.totals.total}</span>
        </div>
        {layout.totals.presentedNote && <p className="text-xs text-muted">{layout.totals.presentedNote}</p>}
        {showOperatorControls && layout.totals.unpricedHint && (
          <p className="text-xs text-warn">{layout.totals.unpricedHint}</p>
        )}
        {(canPresent || canViewAsCustomer) && (
          <div className="mt-2 flex gap-2">
            {canPresent && (
              <form action={presentEstimate}>
                <input type="hidden" name="orgId" value={orgId} />
                <input type="hidden" name="estimateId" value={estimate.id} />
                <button
                  type="submit"
                  className="min-h-11 rounded-lg bg-accent-strong px-4 text-sm font-medium text-white"
                >
                  Present to client
                </button>
              </form>
            )}
            {canViewAsCustomer && (
              <a
                href={`/w/${orgId}/estimating/${estimate.id}/present`}
                className="flex min-h-11 items-center rounded-lg border border-border px-4 text-sm font-medium text-text"
              >
                View as customer
              </a>
            )}
          </div>
        )}
      </div>

      {/* Notes / terms */}
      {layout.notes && (
        <div className="flex flex-col gap-1 border-t border-border pt-4">
          <p className="text-[10px] font-semibold uppercase tracking-wide text-muted">Notes &amp; terms</p>
          <EditableField
            key={`notes-${estimate.id}-${estimate.notes_terms}`}
            value={estimate.notes_terms ?? ""}
            display={layout.notes.value || undefined}
            placeholder="Add notes or terms"
            action={updateEstimateDocumentDetails}
            hidden={detailsHidden}
            name="notes_terms"
            type="textarea"
            locked={effectivelyLocked}
            className="text-xs text-muted"
            block
          />
        </div>
      )}

      {/* Signature */}
      <div className="flex flex-col gap-2 border-t border-border pt-4">
        <p className="text-[10px] font-semibold uppercase tracking-wide text-muted">Signature</p>
        <EstimateSignatureBlock
          orgId={orgId}
          estimateId={estimate.id}
          status={estimate.status}
          signed={layout.signature.signed}
          imageDataUrl={layout.signature.imageDataUrl}
          signerLine={layout.signature.signerLine}
          dateLine={layout.signature.dateLine}
          liveTotal={liveTotal}
          presentationMode={presentationMode}
        />
      </div>
    </div>
  );
}
