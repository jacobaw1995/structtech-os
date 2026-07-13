"use client";

import { createContext, useContext } from "react";

// EstimateFlowShell provides this; every other step reads the toggle
// through the `group-data-[outdoor=true]/flow:*` CSS variant instead (see
// that file's comment for why server components can't consume context).
// This context exists only for SignaturePad, which draws with the raw
// canvas 2D API — a code path CSS can't reach — so it's the one place that
// genuinely needs the boolean at runtime rather than through a class name.
export const OutdoorModeContext = createContext(false);

export function useOutdoorMode(): boolean {
  return useContext(OutdoorModeContext);
}
