// Pure: turns what signed_copy_by_link returns into the signed-copy renderer's
// inputs. Split from link-actions.ts so the mapping can be run against a real
// payload without a signing session. Track U, U-W1.21, 2026-09-17.
import { parseEstimateBranding, type EstimateBranding } from "@/lib/estimating/branding";
import type { Database } from "@/lib/supabase/database.types";

type Estimate = Database["public"]["Tables"]["estimates"]["Row"];
type LineItem = Database["public"]["Tables"]["estimate_line_items"]["Row"];
type Signature = Database["public"]["Tables"]["signatures"]["Row"];

/**
 * THE NARROWED PAYLOAD (Track S, 20260918003303). signed_copy_by_link returns
 * ONLY what the copy prints: 17 estimate fields, 7 line fields (scope_key became
 * `scope_generated`), the 4-field signer block, 5 branding fields, `to`,
 * `copy_state`, `signature_id`. No ids beyond signature_id, no tenant config.
 * These types are that shape; anything the renderer reads that the token does
 * not grant is filled with null here, never fetched some other way.
 */
type CopyEstimate = Pick<
  Estimate,
  | "estimate_number" | "estimate_date" | "valid_until" | "status" | "presented_at" | "presented_total"
  | "subtotal" | "tax_rate" | "tax_amount" | "company" | "contact_name" | "phone" | "email"
  | "site_address" | "squares" | "pitch" | "notes_terms"
>;
type CopyLine = {
  description: string; quantity: number; unit: string | null; unit_price: number;
  line_total: number | null; sort_order: number; scope_generated: boolean;
};
type CopySigner = { signer_name: string; signer_role: string; signed_at: string; signature_data: string };
type CopyBranding = { company_name: string | null; address: string | null; phone: string | null; email: string | null; terms: string | null };

export function copyInputsFromPayload(
  p: Record<string, unknown>
): { estimate: Estimate; lineItems: LineItem[]; signature: Signature; branding: EstimateBranding } | null {
  const signatureId = typeof p.signature_id === "string" ? p.signature_id : null;
  const e = p.estimate as CopyEstimate | undefined;
  const sig = p.signature as CopySigner | undefined;
  if (!signatureId || !e || !sig) return null;

  // Rebuilt from the printed fields only. Columns the token no longer grants
  // (ids, org, timestamps, build mode) are null or a placeholder: the renderer
  // does not print them.
  const estimate = {
    ...e,
    id: "", org_id: "", deal_id: null, signed_at: sig.signed_at, created_at: "", updated_at: "",
    build_mode: null, email: typeof p.to === "string" ? p.to : e.email,
  } as unknown as Estimate;
  const lineItems = ((p.line_items ?? []) as CopyLine[]).map((l, i) => ({
    id: `line-${i}`, org_id: "", estimate_id: "", product_id: null, created_at: "", updated_at: "",
    description: l.description, quantity: l.quantity, unit: l.unit, unit_price: l.unit_price,
    line_total: l.line_total, sort_order: l.sort_order,
    scope_key: l.scope_generated ? "scope" : null,
  })) as unknown as LineItem[];
  const signature = {
    id: signatureId, org_id: "", estimate_id: "", pdf_url: null, sign_token: null, sign_link_id: null,
    created_at: sig.signed_at, ...sig,
  } as unknown as Signature;
  const b = (p.branding ?? {}) as CopyBranding;
  return {
    estimate,
    lineItems,
    signature,
    branding: parseEstimateBranding({ branding: b }, b.company_name ?? "Estimate"),
  };
}
