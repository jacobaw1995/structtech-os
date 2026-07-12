// Client-safe: no server-only imports. Step navigation is gated by the
// estimate's persisted status, not just the URL — a caller can't type
// ?step=4 into the address bar to skip presenting/signing, because
// clampStep() pulls them back to the highest step that status allows.

export type EstimateStatus =
  | "preliminary"
  | "validated"
  | "presented"
  | "signed"
  | "void";

const STEP_COUNT = 4;

export function defaultStep(status: string): number {
  switch (status as EstimateStatus) {
    case "preliminary":
      return 1;
    case "validated":
      return 2;
    case "presented":
      return 3;
    case "signed":
      return 4;
    default:
      return 1;
  }
}

// The furthest step reachable given what's actually been persisted —
// e.g. a 'preliminary' estimate has no line items validated yet, so step 3
// (present) isn't reachable until update_estimate_details has run at least
// once (status -> 'validated').
export function maxAllowedStep(status: string): number {
  switch (status as EstimateStatus) {
    case "preliminary":
      return 2;
    case "validated":
      return 3;
    case "presented":
      return 4;
    case "signed":
      return 4;
    default:
      return 1;
  }
}

export function clampStep(requested: number | undefined, status: string): number {
  const max = maxAllowedStep(status);
  if (!requested || Number.isNaN(requested)) return Math.min(defaultStep(status), max);
  return Math.max(1, Math.min(requested, max, STEP_COUNT));
}

export const STEP_LABELS = [
  "Preliminary",
  "Validate & adjust",
  "Present",
  "Sign",
] as const;
