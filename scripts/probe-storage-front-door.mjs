#!/usr/bin/env node
// X-W1.2 · Front-door storage probe.
//
// Runs against the LIVE storage API with nothing but the publishable anon
// key — the same thing anyone on the internet has. It does not read the
// database, so it cannot be fooled by a policy that exists but is not
// reachable, nor by one that is reachable but does not apply.
//
// Every check below has a failure branch that has actually fired:
//   · deal-files upload SUCCEEDED on 2026-09-03 (that is the finding).
//   · org-files upload was refused on the same run.
// So this is a differential probe, not a list of assertions that pass by
// construction. When Track S drops `anon deal files all`, check 1 flips from
// FAIL to PASS and the flip is the evidence the drop worked.
//
//   node scripts/probe-storage-front-door.mjs
//
// Reads NEXT_PUBLIC_SUPABASE_URL / NEXT_PUBLIC_SUPABASE_ANON_KEY from the
// environment or .env.local. Prints no key material.

import { readFileSync } from "node:fs";
import { randomUUID } from "node:crypto";

function loadEnv() {
  let url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  let key = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
  if (!url || !key) {
    try {
      for (const line of readFileSync(".env.local", "utf8").split("\n")) {
        const m = line.match(/^\s*([A-Z0-9_]+)\s*=\s*(.*)\s*$/);
        if (!m) continue;
        const v = m[2].replace(/^["']|["']$/g, "");
        if (m[1] === "NEXT_PUBLIC_SUPABASE_URL") url ||= v;
        if (m[1] === "NEXT_PUBLIC_SUPABASE_ANON_KEY") key ||= v;
      }
    } catch {
      /* fall through to the check below */
    }
  }
  if (!url || !key) {
    console.error("missing NEXT_PUBLIC_SUPABASE_URL / _ANON_KEY");
    process.exit(2);
  }
  return { url, key };
}

const { url, key } = loadEnv();
const H = { apikey: key, Authorization: `Bearer ${key}` };
const PROBE = `_probe_${randomUUID().slice(0, 8)}.txt`;

async function anonUpload(bucket, objectPath) {
  const res = await fetch(`${url}/storage/v1/object/${bucket}/${objectPath}`, {
    method: "POST",
    headers: { ...H, "Content-Type": "text/plain" },
    body: `x-w1.2 probe ${new Date().toISOString()}`,
  });
  return { status: res.status, body: await res.text() };
}

async function anonDelete(bucket, objectPath) {
  const res = await fetch(`${url}/storage/v1/object/${bucket}/${objectPath}`, {
    method: "DELETE",
    headers: H,
  });
  return { status: res.status, body: await res.text() };
}

const results = [];
function record(name, pass, detail) {
  results.push({ name, pass, detail });
  console.log(`${pass ? "PASS" : "FAIL"}  ${name}\n      ${detail}`);
}

// ---------------------------------------------------------------------------
// 1. anon must NOT be able to write to deal-files.
//    Expected to FAIL until Track S drops the `anon deal files all` policy.
// ---------------------------------------------------------------------------
{
  const up = await anonUpload("deal-files", PROBE);
  const wrote = up.status === 200;
  record(
    "anon cannot write to deal-files",
    !wrote,
    wrote
      ? `anon UPLOADED (HTTP ${up.status}). Policy "anon deal files all" is still present — see supabase/proposals/20260903_x_w1_2_storage_org_isolation.sql §1.`
      : `refused: HTTP ${up.status} ${up.body.slice(0, 120)}`
  );
  if (wrote) {
    // Leave nothing behind. If the delete also succeeds, that is itself the
    // rest of the finding: anon holds DELETE too.
    const del = await anonDelete("deal-files", PROBE);
    console.log(
      `      cleanup: anon DELETE -> HTTP ${del.status} ${del.body.slice(0, 80)}`
    );
  }
}

// ---------------------------------------------------------------------------
// 2. anon must NOT be able to write to org-files (the A4 bucket).
// ---------------------------------------------------------------------------
{
  const orgSegment = randomUUID(); // a well-formed but unowned org id
  const up = await anonUpload("org-files", `${orgSegment}/office-uploads/${randomUUID()}/${PROBE}`);
  const wrote = up.status === 200;
  record(
    "anon cannot write to org-files",
    !wrote,
    wrote
      ? `anon UPLOADED (HTTP ${up.status}) — org-files is NOT closed`
      : `refused: HTTP ${up.status} ${up.body.slice(0, 120)}`
  );
  if (wrote) await anonDelete("org-files", `${orgSegment}/office-uploads/${PROBE}`);
}

// ---------------------------------------------------------------------------
// 3. Control buckets. These SHOULD refuse; if one of them ever accepts, the
//    probe itself is broken or something changed underneath us.
// ---------------------------------------------------------------------------
for (const bucket of ["spec-files", "bot-assets", "pdf-files"]) {
  const up = await anonUpload(bucket, PROBE);
  const wrote = up.status === 200;
  record(
    `control: anon cannot write to ${bucket}`,
    !wrote,
    wrote ? `anon UPLOADED (HTTP ${up.status})` : `refused: HTTP ${up.status}`
  );
  if (wrote) await anonDelete(bucket, PROBE);
}

const failed = results.filter((r) => !r.pass).length;
console.log(`\n${results.length - failed}/${results.length} passed`);
process.exit(failed === 0 ? 0 : 1);
