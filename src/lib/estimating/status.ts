// Client-safe: no server-only imports.

export function estimateStatusLabel(status: string): string {
  switch (status) {
    case "draft":
      return "Draft";
    case "presented":
      return "Presented";
    case "signed":
      return "Signed";
    case "void":
      return "Void";
    default:
      return status;
  }
}

export function estimateStatusClasses(status: string): string {
  switch (status) {
    case "signed":
      return "bg-accent-soft text-accent-strong";
    case "presented":
      return "bg-warn-soft text-text";
    case "void":
      return "bg-surface2 text-muted line-through";
    default:
      return "bg-surface2 text-muted";
  }
}
