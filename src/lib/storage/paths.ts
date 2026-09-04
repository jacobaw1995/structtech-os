// The storage path convention. Every object in the `org-files` bucket is
// addressed as:
//
//     {org_id}/{category}/{entity_id}/{nonce}-{filename}
//
// Segment 1 is the org id and nothing else. It is the tenant boundary, and
// it is a PATH segment rather than a column because storage RLS can only see
// the object's name — `(storage.foldername(name))[1]` is the only thing a
// policy on storage.objects can compare against my_org_ids(). Putting the
// org anywhere else in the path makes the isolation policy unwritable.
//
// Segment 2 is the category. A4.7 wants per-role permissions on office-side
// uploads; that gate reads segment 2, so the categories are fixed here
// rather than free-form (a free-form segment is a hole in a future policy).
//
// The nonce prefix on the filename means two crews uploading IMG_0001.jpg to
// the same check-in do not overwrite each other. Storage upsert defaults to
// false, so without it the second upload fails instead — either way it is a
// bug the crew sees on a roof.

export const ORG_FILES_BUCKET = "org-files";

export const FILE_CATEGORIES = [
  "check-in-photos",
  "estimate-pdfs",
  "work-order-docs",
  "office-uploads",
] as const;

export type FileCategory = (typeof FILE_CATEGORIES)[number];

const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/**
 * Strip a user-supplied filename down to something safe to place in a path.
 * A filename arrives from a phone's camera roll, so it is untrusted input:
 * `/` would forge a path segment (and with it a different org), `..` would
 * traverse, and a leading `.` hides the object from a prefix listing.
 */
export function safeFilename(raw: string): string {
  const base = raw.split(/[\\/]/).pop() ?? "";
  const cleaned = base
    .replace(/[^a-zA-Z0-9._-]/g, "-")
    .replace(/-{2,}/g, "-")
    .replace(/^[.-]+/, "");
  return cleaned.length > 0 ? cleaned.slice(0, 120) : "file";
}

export function buildOrgFilePath(args: {
  orgId: string;
  category: FileCategory;
  entityId: string;
  filename: string;
}): string {
  if (!UUID_RE.test(args.orgId)) {
    throw new Error(`storage: orgId is not a uuid: ${args.orgId}`);
  }
  if (!UUID_RE.test(args.entityId)) {
    throw new Error(`storage: entityId is not a uuid: ${args.entityId}`);
  }
  if (!FILE_CATEGORIES.includes(args.category)) {
    throw new Error(`storage: unknown category: ${args.category}`);
  }
  const nonce = crypto.randomUUID().slice(0, 8);
  return `${args.orgId}/${args.category}/${args.entityId}/${nonce}-${safeFilename(
    args.filename
  )}`;
}

export function buildOrgFilePrefix(args: {
  orgId: string;
  category: FileCategory;
  entityId?: string;
}): string {
  const head = `${args.orgId}/${args.category}`;
  return args.entityId ? `${head}/${args.entityId}` : head;
}

export type ParsedOrgFilePath = {
  orgId: string;
  category: FileCategory;
  entityId: string;
  filename: string;
};

/**
 * Parse a stored path back into its parts, or null if it does not match the
 * convention. Callers use the org id to check a path against the caller's
 * active org BEFORE handing it to storage — RLS is the real barrier, but a
 * path that fails this check is a bug or an attempt, and either is worth
 * refusing at the edge rather than discovering as an empty result.
 */
export function parseOrgFilePath(path: string): ParsedOrgFilePath | null {
  const parts = path.split("/");
  if (parts.length !== 4) return null;
  const [orgId, category, entityId, filename] = parts;
  if (!UUID_RE.test(orgId)) return null;
  if (!UUID_RE.test(entityId)) return null;
  if (!FILE_CATEGORIES.includes(category as FileCategory)) return null;
  if (filename.length === 0) return null;
  return { orgId, category: category as FileCategory, entityId, filename };
}
