// Client-safe: no server-only imports.
//
// HOTFIX (pre-merge gap): estimates.status now persists the rebuilt
// vocabulary (draft/presented/signed/void) since the Chunk 1 migration, but
// this file's switches still only recognized the pre-rebuild vocabulary
// (preliminary/validated/...). "draft" matched no case, so maxAllowedStep()
// fell through to its default of 1 and clampStep() permanently pinned every
// new estimate to Step 1 — the old wizard couldn't advance past Step 1 at
// all. This file is deleted outright by the estimate-builder-rebuild branch
// (the new document has no step gating); until that merges, the step gate
// is neutered here rather than taught the new vocabulary, matching SCOPE
// §2.8 ("never block the user") and keeping the diff on a file that's going
// away anyway as small as possible.

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

// eslint-disable-next-line @typescript-eslint/no-unused-vars -- kept for call-site compatibility (EstimateFlowShell passes status)
export function maxAllowedStep(_status: string): number {
  return STEP_COUNT;
}

export function clampStep(requested: number | undefined, status: string): number {
  if (!requested || Number.isNaN(requested)) return defaultStep(status);
  return Math.max(1, Math.min(requested, STEP_COUNT));
}

export const STEP_LABELS = [
  "Preliminary",
  "Validate & adjust",
  "Present",
  "Sign",
] as const;
