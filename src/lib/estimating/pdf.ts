import { PDFDocument, StandardFonts, rgb, type PDFFont, type PDFPage } from "pdf-lib";
import { buildDocumentLayout, type DocumentLayout } from "@/lib/estimating/document-layout";
import type { Database } from "@/lib/supabase/database.types";
import type { EstimateBranding } from "@/lib/estimating/branding";

type Estimate = Database["public"]["Tables"]["estimates"]["Row"];
type LineItem = Database["public"]["Tables"]["estimate_line_items"]["Row"];
type Signature = Database["public"]["Tables"]["signatures"]["Row"];

// Server-only (pdf-lib runs fine in a Node route handler, not the Edge
// runtime — the [estimateId]/pdf route this feeds must not opt into
// `export const runtime = "edge"`).
//
// Chunk 5 PDF parity: this file no longer decides what a field says or
// whether it shows — buildDocumentLayout() (document-layout.ts) does that
// ONCE, and EstimateDocument.tsx (the on-screen editor) calls the exact
// same function. Every draw call below reads a pre-formatted string off
// `layout`; there is no separate money()/date() formatting here anymore,
// and no separate "should the tax row show" logic — if a field is on
// screen and not here (or vice versa), that's a bug in this file, not a
// second copy of the rules that could silently diverge from the first.
//
// locked: true always — a PDF is an inherently static, final-looking
// snapshot regardless of the underlying estimate.status (a draft's PDF
// preview should still read like a finished document: the smart-merge
// customer block, optional rows only where populated), matching what this
// file already did before Chunk 5, now sourced from the shared builder
// instead of ad hoc here.

const PAGE_WIDTH = 612; // US Letter, points
const PAGE_HEIGHT = 792;
const MARGIN = 56;

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
  const layout = buildDocumentLayout({ estimate, lineItems, signature, branding, locked: true });

  const doc = await PDFDocument.create();
  const page = doc.addPage([PAGE_WIDTH, PAGE_HEIGHT]);
  const bold = await doc.embedFont(StandardFonts.HelveticaBold);
  const regular = await doc.embedFont(StandardFonts.Helvetica);
  const mono = await doc.embedFont(StandardFonts.Courier);

  let y = PAGE_HEIGHT - MARGIN;

  y = drawHeader(page, { bold, regular }, y, layout);
  y -= 28;

  y = drawCustomerBlock(page, { bold, regular }, y, layout);
  y -= 20;

  y = drawJobSite(page, { bold, regular }, y, layout);
  y -= 20;

  y = drawLineItems(page, { bold, regular, mono }, y, layout);
  y -= 12;

  y = drawTotals(page, { bold, regular, mono }, y, layout);
  y -= 24;

  if (layout.signature.signed) {
    y = await drawSignedBlock(doc, page, { bold, regular }, y, layout);
    y -= 24;
  }

  if (layout.notes) {
    drawNotes(page, regular, y, layout.notes.value);
  }

  return doc.save();
}

function drawHeader(
  page: PDFPage,
  fonts: { bold: PDFFont; regular: PDFFont },
  y: number,
  layout: DocumentLayout
): number {
  page.drawText(layout.header.companyName, {
    x: MARGIN,
    y,
    size: 18,
    font: fonts.bold,
    color: rgb(0.13, 0.13, 0.13),
  });
  y -= 18;

  if (layout.header.companyContactLine) {
    page.drawText(layout.header.companyContactLine, {
      x: MARGIN,
      y,
      size: 9,
      font: fonts.regular,
      color: rgb(0.4, 0.4, 0.4),
    });
    y -= 14;
  }

  // Right-aligned header block — ESTIMATE label, status, number, dates —
  // same fields EstimateDocument.tsx shows in its own header, in the same
  // order.
  let ry = PAGE_HEIGHT - MARGIN;
  const rx = PAGE_WIDTH - MARGIN - 160;
  page.drawText("ESTIMATE", {
    x: rx,
    y: ry,
    size: 14,
    font: fonts.bold,
    color: rgb(0.16, 0.31, 0.62),
  });
  page.drawText(layout.header.statusLabel, {
    x: rx + 90,
    y: ry,
    size: 9,
    font: fonts.regular,
    color: rgb(0.4, 0.4, 0.4),
  });
  ry -= 16;

  if (layout.header.estimateNumber) {
    page.drawText(layout.header.estimateNumber, {
      x: rx,
      y: ry,
      size: 10,
      font: fonts.regular,
      color: rgb(0.2, 0.2, 0.2),
    });
    ry -= 13;
  }

  const dateLine = layout.header.validUntil
    ? `${layout.header.estimateDate.value} · valid until ${layout.header.validUntil.value}`
    : layout.header.estimateDate.value;
  page.drawText(dateLine, {
    x: rx,
    y: ry,
    size: 9,
    font: fonts.regular,
    color: rgb(0.5, 0.5, 0.5),
  });

  return y;
}

function drawCustomerBlock(
  page: PDFPage,
  fonts: { bold: PDFFont; regular: PDFFont },
  y: number,
  layout: DocumentLayout
): number {
  const lines = layout.customer.summaryLines ?? [];
  for (let i = 0; i < lines.length; i++) {
    page.drawText(lines[i], {
      x: MARGIN,
      y,
      size: i === 0 ? 12 : 10,
      font: i === 0 ? fonts.bold : fonts.regular,
      color: rgb(0.2, 0.2, 0.2),
    });
    y -= i === 0 ? 16 : 13;
  }
  return y;
}

function drawJobSite(
  page: PDFPage,
  fonts: { bold: PDFFont; regular: PDFFont },
  y: number,
  layout: DocumentLayout
): number {
  if (layout.jobSite.address.value && layout.jobSite.address.value !== "—") {
    page.drawText(layout.jobSite.address.value, {
      x: MARGIN,
      y,
      size: 10,
      font: fonts.regular,
      color: rgb(0.3, 0.3, 0.3),
    });
    y -= 13;
  }
  if (layout.jobSite.measurements) {
    const { squares, pitch } = layout.jobSite.measurements;
    page.drawText(`${squares.value} · pitch ${pitch.value}`, {
      x: MARGIN,
      y,
      size: 9,
      font: fonts.regular,
      color: rgb(0.5, 0.5, 0.5),
    });
    y -= 13;
  }
  return y;
}

function drawLineItems(
  page: PDFPage,
  fonts: { bold: PDFFont; regular: PDFFont; mono: PDFFont },
  y: number,
  layout: DocumentLayout
): number {
  const colDesc = MARGIN;
  const colQty = PAGE_WIDTH - MARGIN - 220;
  const colUnit = PAGE_WIDTH - MARGIN - 160;
  const colPrice = PAGE_WIDTH - MARGIN - 110;
  const colTotal = PAGE_WIDTH - MARGIN - 55;

  page.drawLine({
    start: { x: MARGIN, y },
    end: { x: PAGE_WIDTH - MARGIN, y },
    thickness: 1,
    color: rgb(0.1, 0.1, 0.1),
  });
  y -= 16;

  page.drawText("Description", { x: colDesc, y, size: 9, font: fonts.bold });
  page.drawText("Qty", { x: colQty, y, size: 9, font: fonts.bold });
  page.drawText("Unit", { x: colUnit, y, size: 9, font: fonts.bold });
  page.drawText("Rate", { x: colPrice, y, size: 9, font: fonts.bold });
  page.drawText("Total", { x: colTotal, y, size: 9, font: fonts.bold });
  y -= 14;

  for (const row of layout.lineItems.rows) {
    page.drawText(row.description, {
      x: colDesc,
      y,
      size: 10,
      font: fonts.regular,
      maxWidth: colQty - colDesc - 12,
    });
    page.drawText(row.quantity, { x: colQty, y, size: 10, font: fonts.mono });
    page.drawText(row.unit, { x: colUnit, y, size: 10, font: fonts.mono, color: rgb(0.5, 0.5, 0.5) });
    page.drawText(row.unitPrice, { x: colPrice, y, size: 10, font: fonts.mono });
    page.drawText(row.lineTotal, { x: colTotal, y, size: 10, font: fonts.mono });
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

function drawTotals(
  page: PDFPage,
  fonts: { bold: PDFFont; regular: PDFFont; mono: PDFFont },
  y: number,
  layout: DocumentLayout
): number {
  const labelX = PAGE_WIDTH - MARGIN - 160;
  const valueX = PAGE_WIDTH - MARGIN - 90;

  y -= 18;
  page.drawText("Subtotal", { x: labelX, y, size: 10, font: fonts.regular, color: rgb(0.4, 0.4, 0.4) });
  page.drawText(layout.totals.subtotal, { x: valueX, y, size: 10, font: fonts.mono });

  if (layout.totals.tax) {
    y -= 15;
    page.drawText(`Tax (${layout.totals.tax.percentField.value}%)`, {
      x: labelX,
      y,
      size: 10,
      font: fonts.regular,
      color: rgb(0.4, 0.4, 0.4),
    });
    page.drawText(layout.totals.tax.amount, { x: valueX, y, size: 10, font: fonts.mono });
  }

  y -= 20;
  page.drawText("Total", { x: labelX, y, size: 13, font: fonts.bold });
  page.drawText(layout.totals.total, { x: valueX, y, size: 13, font: fonts.mono });

  if (layout.totals.presentedNote) {
    y -= 14;
    page.drawText(layout.totals.presentedNote, {
      x: labelX,
      y,
      size: 8,
      font: fonts.regular,
      color: rgb(0.55, 0.55, 0.55),
      maxWidth: PAGE_WIDTH - MARGIN - labelX,
    });
  }

  return y;
}

async function drawSignedBlock(
  doc: PDFDocument,
  page: PDFPage,
  fonts: { bold: PDFFont; regular: PDFFont },
  y: number,
  layout: DocumentLayout
): Promise<number> {
  page.drawText("Signed", { x: MARGIN, y, size: 10, font: fonts.bold });
  y -= 14;

  // signature_data is a canvas toDataURL() PNG ("data:image/png;base64,...")
  // — SignaturePad is the only producer. A malformed/non-PNG value falls
  // back to text-only rather than failing the whole PDF.
  const dataUrl = layout.signature.imageDataUrl;
  const match = dataUrl ? /^data:image\/png;base64,(.+)$/.exec(dataUrl) : null;
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

  if (layout.signature.signerLine) {
    page.drawText(layout.signature.signerLine, { x: MARGIN, y, size: 10, font: fonts.regular });
    y -= 13;
  }
  if (layout.signature.dateLine) {
    page.drawText(layout.signature.dateLine, {
      x: MARGIN,
      y,
      size: 9,
      font: fonts.regular,
      color: rgb(0.5, 0.5, 0.5),
    });
  }
  return y;
}

function drawNotes(page: PDFPage, font: PDFFont, y: number, notes: string): void {
  if (!notes) return;
  page.drawText(notes, {
    x: MARGIN,
    y,
    size: 8,
    font,
    color: rgb(0.5, 0.5, 0.5),
    maxWidth: PAGE_WIDTH - MARGIN * 2,
    lineHeight: 11,
  });
}
