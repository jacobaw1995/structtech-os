import { formatMoney } from "@/lib/crm/stages";
import { formatQty, formatDateOnly } from "@/lib/estimating/format";
import { estimateStatusLabel } from "@/lib/estimating/status";
import type { EstimateBranding } from "@/lib/estimating/branding";
import type { Database } from "@/lib/supabase/database.types";

type Estimate = Database["public"]["Tables"]["estimates"]["Row"];
type LineItem = Database["public"]["Tables"]["estimate_line_items"]["Row"];
type Signature = Database["public"]["Tables"]["signatures"]["Row"];

// Chunk 5 of the estimate builder rebuild — the ONE place that decides what
// the document contains and how it's formatted. The editor (EstimateDocument
// .tsx) renders this to JSX; the PDF route (pdf.ts) renders it to pdf-lib
// draw calls; Present Mode renders it plainly. All three call this SAME
// function — a field added to one and not the other is impossible by
// construction, since neither renderer has its own copy of "what fields
// exist" or "how they're formatted." That's the whole point: pdf-lib draw
// calls can't share JSX, but they CAN share the data both are drawn from.
//
// Every string here is pre-formatted (money/date/qty) using the SAME
// helpers every renderer would otherwise have needed its own copy of.
// Conditional inclusion (does the tax row show at all? does valid_until?)
// is decided HERE, once — every renderer just maps over whatever's present,
// never re-implements "should this show" logic itself.
//
// `.editable` metadata (which action/field a value maps to) is NOT
// populated here — the editor keeps its own direct EditableField wiring
// (it needs the RAW value for an input's defaultValue, not just the
// formatted display string this module produces). PDF/Present never look
// at it regardless. This is the one place this module is thinner than the
// originally-sketched shape; flagging it rather than pretending otherwise.

// timestamptz only (presented_at, signed_at) — real offset, new Date(iso)
// is correct. Bare `date` columns (estimate_date, valid_until) use
// formatDateOnly instead (see lib/estimating/format.ts for why).
function fullDate(iso: string | null): string {
  if (!iso) return "—";
  return new Date(iso).toLocaleDateString("en-US", {
    year: "numeric",
    month: "short",
    day: "numeric",
  });
}

export type DocumentField = {
  key: string;
  value: string; // pre-formatted, "—" for empty
};

export type DocumentLineItemRow = {
  id: string;
  description: string;
  quantity: string;
  unit: string;
  unitPrice: string;
  lineTotal: string;
  unpriced: boolean;
  scopeGenerated: boolean;
};

export type DocumentLayout = {
  header: {
    companyName: string;
    companyContactLine: string | null;
    statusLabel: string;
    estimateNumber: string | null;
    estimateDate: DocumentField;
    validUntil: DocumentField | null;
  };
  customer: {
    sectionLabel: string;
    summaryLines: string[]; // always populated — always the display, regardless of lock state
    fields: { company: DocumentField; contactName: DocumentField; phone: DocumentField; email: DocumentField } | null; // present only when editable (feeds the explicit Edit form)
  };
  jobSite: {
    sectionLabel: string;
    address: DocumentField;
    measurements: { squares: DocumentField; pitch: DocumentField } | null;
  };
  lineItems: {
    sectionLabel: string;
    rows: DocumentLineItemRow[];
  };
  totals: {
    subtotal: string;
    tax: { percentField: DocumentField; amount: string } | null;
    total: string;
    presentedNote: string | null;
    unpricedHint: string | null; // operator-only — PDF/Present ignore
  };
  notes: DocumentField | null;
  signature: {
    signed: boolean;
    imageDataUrl?: string;
    signerLine?: string;
    dateLine?: string;
  };
  advisories: { unmapped: string[]; unparseable: string[] }; // operator-only — PDF/Present ignore
};

export function buildDocumentLayout(input: {
  estimate: Estimate;
  lineItems: LineItem[];
  signature: Signature | null;
  branding: EstimateBranding;
  locked: boolean;
  scopeUnmapped?: string[];
  scopeUnparseable?: string[];
}): DocumentLayout {
  const { estimate, lineItems, signature, branding, locked } = input;

  const tax = estimate.tax_amount ?? 0;
  const liveTotal = estimate.subtotal + tax;
  const hasBeenPresented = estimate.presented_at != null;
  const editedSincePresented =
    hasBeenPresented &&
    estimate.presented_total != null &&
    Math.abs(estimate.presented_total - liveTotal) > 0.001;

  const summaryLines = [
    estimate.company || estimate.contact_name || "Untitled",
    estimate.company && estimate.contact_name ? estimate.contact_name : null,
    [estimate.phone, estimate.email].filter(Boolean).join("  ·  ") || null,
  ].filter((l): l is string => !!l);

  const unpricedCount = lineItems.filter((li) => li.unit_price === 0).length;

  return {
    header: {
      companyName: branding.companyName,
      companyContactLine:
        [branding.address, branding.phone, branding.email].filter(Boolean).join("  ·  ") || null,
      statusLabel: estimateStatusLabel(estimate.status),
      estimateNumber: estimate.estimate_number, // null on any pre-rebuild row — omit, never "EST-null"
      estimateDate: {
        key: "estimate_date",
        value: estimate.estimate_date ? formatDateOnly(estimate.estimate_date) : "—",
      },
      validUntil:
        !locked || estimate.valid_until
          ? { key: "valid_until", value: estimate.valid_until ? formatDateOnly(estimate.valid_until) : "—" }
          : null,
    },
    customer: {
      sectionLabel: "Customer",
      // Task A (7/24 walkthrough): always available now, not just when
      // locked — the editor shows this as plain-text display too (established
      // contact data, not a field being gathered), with edits routed through
      // an explicit Edit disclosure (fields, below) instead of tap-to-edit.
      summaryLines,
      fields: locked
        ? null
        : {
            company: { key: "company", value: estimate.company ?? "" },
            contactName: { key: "contact_name", value: estimate.contact_name ?? "" },
            phone: { key: "phone", value: estimate.phone ?? "" },
            email: { key: "email", value: estimate.email ?? "" },
          },
    },
    jobSite: {
      sectionLabel: "Job site",
      address: { key: "site_address", value: estimate.site_address ?? "" },
      measurements:
        !locked || estimate.squares != null || estimate.pitch != null
          ? {
              squares: {
                key: "squares",
                value: estimate.squares != null ? `${formatQty(estimate.squares)} sq` : "— sq",
              },
              pitch: { key: "pitch", value: estimate.pitch ?? "—" },
            }
          : null,
    },
    lineItems: {
      sectionLabel: "Line items",
      rows: lineItems.map((item) => ({
        id: item.id,
        description: item.description,
        quantity: formatQty(item.quantity),
        unit: item.unit || "—",
        unitPrice: formatMoney(item.unit_price),
        lineTotal: formatMoney(item.line_total),
        unpriced: item.unit_price === 0,
        scopeGenerated: item.scope_key != null,
      })),
    },
    totals: {
      subtotal: formatMoney(estimate.subtotal),
      tax:
        !locked || estimate.tax_rate != null
          ? {
              percentField: {
                key: "tax_rate_percent",
                // Round before formatQty — 0.07 * 100 is 7.000000000000001
                // in IEEE 754 binary float, and formatQty's Number(...)
                // .toString() faithfully preserves that noise instead of
                // hiding it. Rounding to 4 decimal places keeps any real
                // fractional tax rate (8.25%) while killing the artifact.
                value: estimate.tax_rate != null ? formatQty(Math.round(estimate.tax_rate * 100 * 10000) / 10000) : "0",
              },
              amount: formatMoney(tax),
            }
          : null,
      total: formatMoney(liveTotal),
      presentedNote: hasBeenPresented
        ? `Presented ${estimate.presented_total != null ? formatMoney(estimate.presented_total) : "—"} on ${fullDate(
            estimate.presented_at
          )}${editedSincePresented ? " — edited since" : ""}`
        : null,
      unpricedHint:
        !locked && unpricedCount > 0
          ? `${unpricedCount} line item${unpricedCount === 1 ? "" : "s"} ${unpricedCount === 1 ? "has" : "have"} no price.`
          : null,
    },
    notes:
      !locked || estimate.notes_terms || branding.terms
        ? { key: "notes_terms", value: estimate.notes_terms || branding.terms || "" }
        : null,
    signature: {
      signed: !!signature,
      imageDataUrl: signature?.signature_data,
      signerLine: signature ? `${signature.signer_name} (${signature.signer_role})` : undefined,
      dateLine: signature ? fullDate(signature.signed_at) : undefined,
    },
    advisories: {
      unmapped: input.scopeUnmapped ?? [],
      unparseable: input.scopeUnparseable ?? [],
    },
  };
}
