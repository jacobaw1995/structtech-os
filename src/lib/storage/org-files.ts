import "server-only";

import { createClient } from "@/lib/supabase/server";
import {
  ORG_FILES_BUCKET,
  buildOrgFilePath,
  buildOrgFilePrefix,
  parseOrgFilePath,
  type FileCategory,
} from "@/lib/storage/paths";

// The server-side file layer. Three paths — upload, read, delete — plus a
// list, all against the private `org-files` bucket.
//
// WHAT THIS LAYER STORES IN POSTGRES IS A PATH, NEVER A URL. A signed URL
// expires, so persisting one produces dead links; a public URL would take
// the tenant check out of the read path entirely. Persisting the path keeps
// every read going back through RLS with the reader's own identity, which is
// what makes a photo taken on a BMR roof unreadable from a StructTech
// session six months later.
//
// Every function here calls getSession() first (CLAUDE.md rule 1) — without
// it the storage request carries no auth header, auth.uid() is null, and the
// isolation policy refuses everything for reasons that look like a bug.
//
// The org-vs-path check in each function is DEFENCE IN DEPTH, not the
// control. The control is the storage.objects policy (see
// supabase/proposals/). If that policy is absent this layer fails closed:
// measured 2026-09-03, an INSERT into org-files as `authenticated` with a
// real BMR owner's claims returns 42501 "new row violates row-level security
// policy".

export type StorageResult<T> =
  | { ok: true; data: T }
  | { ok: false; error: string };

const DEFAULT_SIGNED_URL_TTL_SECONDS = 60 * 60; // one hour

async function authed() {
  const supabase = createClient();
  const {
    data: { session },
  } = await supabase.auth.getSession();
  return { supabase, session };
}

/**
 * Reject a path that does not belong to the org the caller is acting in.
 * A caller passes both, so a mismatch means the path came from somewhere
 * other than this org's own records.
 */
function pathBelongsToOrg(path: string, orgId: string): boolean {
  const parsed = parseOrgFilePath(path);
  return parsed !== null && parsed.orgId === orgId;
}

export async function uploadOrgFile(args: {
  orgId: string;
  category: FileCategory;
  entityId: string;
  file: File | Blob;
  filename: string;
  contentType?: string;
}): Promise<StorageResult<{ path: string }>> {
  const { supabase, session } = await authed();
  if (!session) return { ok: false, error: "not signed in" };

  let path: string;
  try {
    path = buildOrgFilePath({
      orgId: args.orgId,
      category: args.category,
      entityId: args.entityId,
      filename: args.filename,
    });
  } catch (e) {
    return { ok: false, error: (e as Error).message };
  }

  const { error } = await supabase.storage
    .from(ORG_FILES_BUCKET)
    .upload(path, args.file, {
      // upsert stays false: the nonce in the path already makes collisions
      // impossible, so an upsert could only ever overwrite somebody else's
      // object after a path-construction bug.
      upsert: false,
      contentType: args.contentType,
    });

  if (error) return { ok: false, error: error.message };
  return { ok: true, data: { path } };
}

/**
 * The read path. Returns a short-lived signed URL for a private object.
 */
export async function signOrgFile(args: {
  orgId: string;
  path: string;
  expiresInSeconds?: number;
}): Promise<StorageResult<{ url: string; expiresInSeconds: number }>> {
  const { supabase, session } = await authed();
  if (!session) return { ok: false, error: "not signed in" };
  if (!pathBelongsToOrg(args.path, args.orgId)) {
    return { ok: false, error: "path does not belong to this org" };
  }

  const expiresInSeconds =
    args.expiresInSeconds ?? DEFAULT_SIGNED_URL_TTL_SECONDS;

  const { data, error } = await supabase.storage
    .from(ORG_FILES_BUCKET)
    .createSignedUrl(args.path, expiresInSeconds);

  if (error || !data) {
    return { ok: false, error: error?.message ?? "could not sign url" };
  }
  return { ok: true, data: { url: data.signedUrl, expiresInSeconds } };
}

/**
 * Sign many paths at once — a check-in gallery is N photos and N round trips
 * would be N times the latency on a phone with one bar of signal.
 */
export async function signOrgFiles(args: {
  orgId: string;
  paths: string[];
  expiresInSeconds?: number;
}): Promise<StorageResult<Record<string, string>>> {
  const { supabase, session } = await authed();
  if (!session) return { ok: false, error: "not signed in" };

  const foreign = args.paths.filter((p) => !pathBelongsToOrg(p, args.orgId));
  if (foreign.length > 0) {
    return { ok: false, error: `${foreign.length} path(s) not in this org` };
  }
  if (args.paths.length === 0) return { ok: true, data: {} };

  const { data, error } = await supabase.storage
    .from(ORG_FILES_BUCKET)
    .createSignedUrls(
      args.paths,
      args.expiresInSeconds ?? DEFAULT_SIGNED_URL_TTL_SECONDS
    );

  if (error || !data) {
    return { ok: false, error: error?.message ?? "could not sign urls" };
  }

  const urls: Record<string, string> = {};
  for (const row of data) {
    if (row.path && row.signedUrl) urls[row.path] = row.signedUrl;
  }
  return { ok: true, data: urls };
}

export async function deleteOrgFile(args: {
  orgId: string;
  path: string;
}): Promise<StorageResult<{ path: string }>> {
  const { supabase, session } = await authed();
  if (!session) return { ok: false, error: "not signed in" };
  if (!pathBelongsToOrg(args.path, args.orgId)) {
    return { ok: false, error: "path does not belong to this org" };
  }

  const { error } = await supabase.storage
    .from(ORG_FILES_BUCKET)
    .remove([args.path]);

  if (error) return { ok: false, error: error.message };
  return { ok: true, data: { path: args.path } };
}

export type OrgFileListing = {
  path: string;
  name: string;
  sizeBytes: number | null;
  mimeType: string | null;
  createdAt: string | null;
};

export async function listOrgFiles(args: {
  orgId: string;
  category: FileCategory;
  entityId?: string;
  limit?: number;
}): Promise<StorageResult<OrgFileListing[]>> {
  const { supabase, session } = await authed();
  if (!session) return { ok: false, error: "not signed in" };

  const prefix = buildOrgFilePrefix(args);
  const { data, error } = await supabase.storage
    .from(ORG_FILES_BUCKET)
    .list(prefix, { limit: args.limit ?? 100, sortBy: { column: "created_at", order: "desc" } });

  if (error) return { ok: false, error: error.message };

  return {
    ok: true,
    data: (data ?? [])
      // A folder placeholder comes back with a null id; it is not a file.
      .filter((row) => row.id !== null)
      .map((row) => ({
        path: `${prefix}/${row.name}`,
        name: row.name,
        sizeBytes:
          typeof row.metadata?.size === "number" ? row.metadata.size : null,
        mimeType:
          typeof row.metadata?.mimetype === "string"
            ? row.metadata.mimetype
            : null,
        createdAt: row.created_at ?? null,
      })),
  };
}
