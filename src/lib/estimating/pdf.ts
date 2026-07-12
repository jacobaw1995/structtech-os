import { PDFDocument, StandardFonts, rgb, type PDFFont, type PDFPage } from "pdf-lib";
import type { Database } from "@/lib/supabase/database.types";
import type { EstimateBranding } from "@/lib/estimating/branding";

type Estimate = Database["public"]["Tables"]["estimates"]["Row"];
type LineItem = Database["public"]["Tables"]["estimate_line_items"]["Row"];
type Signature = Database["public"]["Tables"]["signatures"]["Row"];

// Server-only (pdf-lib runs fine in a Node route handler, not the Edge
// runtime — the [estimateId]/pdf route this feeds must not opt into
// `export const runtime = "edge"`).
//
// Deliberately the ONLY place estimate data becomes a PDF layout. Every
// visual choice (branding, line items, terms) is a parameter, never a
// BMR-specific hardcode — this is the first brick of the tenant-custom
// document-template system (SCOPE.md "Tenant-customizable document
// templates"): a future template editor replaces the layout below, not the
// call sites that invoke it.

const PAGE_WIDTH = 612; // US Letter, points
const PAGE_HEIGHT = 792;
const MARGIN = 56;

function money(value: number | null): string {
  if (value == null) return "—";
  return new Intl.NumberFormat("en-US", {
    style: "currency",
    currency: "USD",
  }).format(value);
}

function date(iso: string | null): string {
  if (!iso) return "—";
  return new Date(iso).toLocaleDateString("en-US", {
    year: "numeric",
    month: "short",
    day: "numeric",
  });
}

export async function renderEstimatePdf({
  estimate,
  lineItems,
  signature,
  branding,
}: {
  estimate: Estimate;
  lineItems: LineItem[];
  signature: Signature | null;
  branding: EstimateBranding;
}): Promise<Uint8Array> {
  const doc = await PDFDocument.create();
  const page = doc.addPage([PAGE_WIDTH, PAGE_HEIGHT]);
  const bold = await doc.embedFont(StandardFonts.HelveticaBold);
  const regular = await doc.embedFont(StandardFonts.Helvetica);
  const mono = await doc.embedFont(StandardFonts.Courier);

  let y = PAGE_HEIGHT - MARGIN;

  y = drawHeader(page, { bold, regular }, y, branding);
  y -= 28;

  y = drawCustomerBlock(page, { bold, regular }, y, estimate);
  y -= 24;

  y = drawLineItems(page, { bold, regular, mono }, y, lineItems);
  y -= 12;

  const total = estimate.presented_total ?? estimate.subtotal;
  y = drawTotal(page, { bold, mono }, y, total);
  y -= 28;

  if (signature) {
    y = await drawSignature(doc, page, { bold, regular }, y, signature);
    y -= 24;
  }

  if (branding.terms) {
    drawTerms(page, regular, y, branding.terms);
  }

  return doc.save();
}

function drawHeader(
  page: PDFPage,
  fonts: { bold: PDFFont; regular: PDFFont },
  y: number,
  branding: EstimateBranding
): number {
  page.drawText(branding.companyName, {
    x: MARGIN,
    y,
    size: 18,
    font: fonts.bold,
    color: rgb(0.13, 0.13, 0.13),
  });
  y -= 18;

  const contactLine = [branding.address, branding.phone, branding.email]
    .filter(Boolean)
    .join("  ·  ");
  if (contactLine) {
    page.drawText(contactLine, {
      x: MARGIN,
      y,
      size: 9,
      font: fonts.regular,
      color: rgb(0.4, 0.4, 0.4),
    });
    y -= 14;
  }

  page.drawText("ESTIMATE", {
    x: PAGE_WIDTH - MARGIN - 80,
    y: PAGE_HEIGHT - MARGIN,
    size: 14,
    font: fonts.bold,
    color: rgb(0.16, 0.31, 0.62),
  });

  return y;
}

function drawCustomerBlock(
  page: PDFPage,
  fonts: { bold: PDFFont; regular: PDFFont },
  y: number,
  estimate: Estimate
): number {
  const lines = [
    estimate.company ?? estimate.contact_name ?? "—",
    estimate.company ? estimate.contact_name : null,
    estimate.site_address,
    [estimate.phone, estimate.email].filter(Boolean).join("  ·  ") || null,
    estimate.squares != null || estimate.pitch != null
      ? `${estimate.squares ?? "—"} squares · pitch ${estimate.pitch ?? "—"}`
      : null,
  ].filter((l): l is string => !!l);

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    page.drawText(line, {
      x: MARGIN,
      y,
      size: i === 0 ? 12 : 10,
      font: i === 0 ? fonts.bold : fonts.regular,
      color: rgb(0.2, 0.2, 0.2),
    });
    y -= i === 0 ? 16 : 13;
  }

  page.drawText(`Estimate #${estimate.id.slice(0, 8)}  ·  ${date(estimate.created_at)}`, {
    x: MARGIN,
    y: y - 4,
    size: 9,
    font: fonts.regular,
    color: rgb(0.55, 0.55, 0.55),
  });

  return y - 4;
}

function drawLineItems(
  page: PDFPage,
  fonts: { bold: PDFFont; regular: PDFFont; mono: PDFFont },
  y: number,
  lineItems: LineItem[]
): number {
  const colDesc = MARGIN;
  const colQty = PAGE_WIDTH - MARGIN - 200;
  const colPrice = PAGE_WIDTH - MARGIN - 130;
  const colTotal = PAGE_WIDTH - MARGIN - 60;

  page.drawLine({
    start: { x: MARGIN, y },
    end: { x: PAGE_WIDTH - MARGIN, y },
    thickness: 1,
    color: rgb(0.1, 0.1, 0.1),
  });
  y -= 16;

  page.drawText("Description", { x: colDesc, y, size: 9, font: fonts.bold });
  page.drawText("Qty", { x: colQty, y, size: 9, font: fonts.bold });
  page.drawText("Unit", { x: colPrice, y, size: 9, font: fonts.bold });
  page.drawText("Total", { x: colTotal, y, size: 9, font: fonts.bold });
  y -= 14;

  for (const item of lineItems) {
    page.drawText(item.description, {
      x: colDesc,
      y,
      size: 10,
      font: fonts.regular,
      maxWidth: colQty - colDesc - 12,
    });
    page.drawText(String(item.quantity), { x: colQty, y, size: 10, font: fonts.mono });
    page.drawText(money(item.unit_price), { x: colPrice, y, size: 10, font: fonts.mono });
    page.drawText(money(item.line_total), { x: colTotal, y, size: 10, font: fonts.mono });
    y -= 16;
  }

  page.drawLine({
    start: { x: MARGIN, y },
    end: { x: PAGE_WIDTH - MARGIN, y },
    thickness: 1,
    color: rgb(0.1, 0.1, 0.1),
  });

  return y;
}

function drawTotal(
  page: PDFPage,
  fonts: { bold: PDFFont; mono: PDFFont },
  y: number,
  total: number
): number {
  y -= 20;
  page.drawText("Total", {
    x: PAGE_WIDTH - MARGIN - 160,
    y,
    size: 13,
    font: fonts.bold,
  });
  page.drawText(money(total), {
    x: PAGE_WIDTH - MARGIN - 90,
    y,
    size: 13,
    font: fonts.mono,
  });
  return y;
}

async function drawSignature(
  doc: PDFDocument,
  page: PDFPage,
  fonts: { bold: PDFFont; regular: PDFFont },
  y: number,
  signature: Signature
): Promise<number> {
  page.drawText("Signed", { x: MARGIN, y, size: 10, font: fonts.bold });
  y -= 14;

  // signature_data is a canvas toDataURL() PNG ("data:image/png;base64,...")
  // — SignaturePad (src/components/estimating/SignaturePad.tsx) is the only
  // producer. A malformed/non-PNG value falls back to text-only rather than
  // failing the whole PDF.
  const match = /^data:image\/png;base64,(.+)$/.exec(signature.signature_data);
  if (match) {
    try {
      const png = await doc.embedPng(Buffer.from(match[1], "base64"));
      const maxWidth = 200;
      const scale = Math.min(1, maxWidth / png.width);
      const h = png.height * scale;
      page.drawImage(png, { x: MARGIN, y: y - h, width: png.width * scale, height: h });
      y -= h + 6;
    } catch {
      // fall through to text-only below
    }
  }

  page.drawText(`${signature.signer_name} (${signature.signer_role})`, {
    x: MARGIN,
    y,
    size: 10,
    font: fonts.regular,
  });
  y -= 13;
  page.drawText(date(signature.signed_at), {
    x: MARGIN,
    y,
    size: 9,
    font: fonts.regular,
    color: rgb(0.5, 0.5, 0.5),
  });
  return y;
}

function drawTerms(page: PDFPage, font: PDFFont, y: number, terms: string): void {
  page.drawText(terms, {
    x: MARGIN,
    y,
    size: 8,
    font,
    color: rgb(0.5, 0.5, 0.5),
    maxWidth: PAGE_WIDTH - MARGIN * 2,
    lineHeight: 11,
  });
}
