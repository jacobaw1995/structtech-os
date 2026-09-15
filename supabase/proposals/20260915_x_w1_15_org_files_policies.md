# X-W1.15 · `org-files` policies for work-order files — proposal for Track S

**Status:** proposal. Track X has applied nothing. The policy text is
[`20260915_x_w1_15_org_files_policies.sql`](20260915_x_w1_15_org_files_policies.sql),
and that exact file is what the fixture loads.
**Unblocks:** Phase A field items #7 *office-side roof-data / photo upload* (`fb9c4f6f`)
and #8 *per-role file permissions* (`4b4d153e`) — directive A4.7, *"roof data and
photos load from the office and a crew role cannot delete them."*
**Written:** 2026-09-15 (America/New_York).

## 1 · Ground, re-derived 2026-09-15 (read-only queries)

| Fact | Measured |
|---|---|
| Objects in storage | **50**: `pdf-files` 15, `product-photos` 35, every other bucket 0 |
| Name shape | all 50 at depth 2 (`<category>/<file>`); **0** have a UUID first segment |
| `org-files` | private, 25 MB limit, **0 objects, 0 policies** |
| Policies on `storage.objects` | 6: four `product-photos` (public read + three `my_wh_role()` writes), two `spec-files`. None mention `org-files` |
| `storage.objects` grants | `anon` and `authenticated` both hold SELECT/INSERT/UPDATE/DELETE **and TRUNCATE** (`has_table_privilege`; not probed). RLS is the only barrier |
| `pdf-files` | 15 objects, no policy, so no API caller can read them. `product-photos` is public-read cross-tenant by design |
| Production members | owner 3, agency_admin 1, member 1. **No `field` member exists**, so crew behaviour can only be proved on a fixture |
| Work orders | master 2, trade 1 |

The 9/04 statement holds today. Rule 13 applies to `org-files` as it stands: **it is
closed only because it has no policy.** Any permissive policy on `storage.objects`
without a `bucket_id` filter would open it.

## 2 · Design: what enforces the path

The name is `{org_id}/{category}/{work_order_id}/{nonce}-{file}`
([`src/lib/storage/paths.ts`](../../src/lib/storage/paths.ts)). **No step depends on
anyone remembering that.** Each policy checks the name against rows, as the caller:

1. Segment 1 must be one of the caller's orgs (`my_org_ids()`).
2. Segment 3 must be a work order **the caller can see through `work_orders`' own
   RLS**, and its `org_id` must equal segment 1.
3. Writes and deletes also need `can_view_master_work_order(org)`. Owner, admin,
   agency_admin, office and member hold it by default; **field and
   client_portal_viewer do not**, and it can be switched per member.

Point 2 is how *"a crew member must not reach a file their role cannot reach in the
app"* holds without a second copy of the rule. Crew can't see a master work order
(restrictive policy `crew cannot reach master work orders`), so they can't see its
files either. If the crew gate on `work_orders` changes, file access follows it.

Also deliberate:
- **No casts on the name.** All comparisons are text. See §3, where the cast
  measurably breaks reads.
- **No UPDATE policy.** Storage moves and upserts are UPDATEs, so refusing them means
  a file can't be moved into another org's prefix or overwritten.
- **Only two categories** (`office-uploads`, `work-order-docs`). `check-in-photos`
  and `estimate-pdfs` stay closed until someone decides their entity and role
  mapping.
- **No new function**, so no new EXECUTE surface. Everything is `to authenticated`.

**What would reopen it (rule 13):** a permissive policy on `work_orders` that widens
who can read work orders, or a change to `can_view_master_work_order` or
`has_capability`. Those are changes to the entity and the capability themselves,
reviewable where they're made. That's the intent: files follow the work order.

## 3 · Fixture — the check can fail

`bash scripts/storage/org-files-fixture/run.sh` builds a throwaway local PostgreSQL 17
cluster. It mirrors the live function bodies and policies verbatim (read 2026-09-15)
and uses synthetic data only:
- org A with a master and a trade work order;
- org B with a trade work order;
- an owner, office, crew and a member with `view_master_work_order` off in A, and an
  owner in B;
- a forged object (B's prefix naming A's work order), an uncovered category, and two
  malformed names;
- controls in `product-photos` and `pdf-files`.

It runs one suite four times and exits 0 only if the proposal passes and both
mutants are caught.

| Suite | Result |
|---|---|
| **before** (no policy, production today) | 11/11 pass: every reader sees nothing, and office upload is refused |
| **proposal** | **24/24 pass** |
| **mutant-entity** (work-order join removed) | **8 fail.** Crew reads the master's plan; crew deletes and uploads; B reads the forged file; an A prefix naming B's work order is accepted |
| **mutant-tenant** (join and `my_org_ids` removed) | **13 fail.** B reads and deletes A's files; A writes into B's prefix |

What the 24 tests cover, in groups:
- **Tenant isolation:** T1, T2 and T10.
- **Crew reach:** reads the trade file but not the master (T3); can't delete (T7);
  can't upload (T14).
- **Per-member switch:** a member with the capability off behaves like crew (T5, T9).
- **Forged paths:** T11, T15 and T16.
- **Uncovered category, extra depth, malformed name** (refused, no error): T17–T19.
- **Moves refused:** T20.
- **Controls, unchanged in every suite:** anon and crew still read `product-photos`,
  `pdf-files` stays unreadable, and a full scan of `storage.objects` raises nothing
  (C1–C4).

**The forged-object result matters most.** With only the prefix checked (mutant-entity
T2), org B reads an object under B's own prefix that names A's work order. That's
the case a naming convention can't stop and a row check can.

**The 9/03 cast, measured.** With the unguarded `::uuid` policy, one malformed name
in the bucket makes every `org-files` read by an owner raise `invalid input syntax
for type uuid`. The regex-guarded version worked on this plan, but SQL doesn't
promise `AND` order, so "worked here" isn't a guarantee. The 9/03 text claimed it
short-circuits; **that claim was mine and it was wrong**, and this proposal
supersedes it.

**What the fixture can't prove:** the Storage API's own queries (signed upload urls,
list, remove), and the real `org_members` and `work_orders` rows. Those are §4.

## 4 · Proof plan after Track S applies

Take an advisor count before and after (rule 9). Then, through the **Storage API**
with real JWTs, not SQL, check in this order:

1. **Crew refusal at signing.** Create a synthetic `field` member in a test org
   (never a real BMR record). Their `createSignedUploadUrl` on a trade work order
   must be refused with an RLS message. This is the claim the upload path rests on,
   and it is **unverified** until now.
2. **The signed-url token binds the path.** An office user's signed url must not
   accept a PUT to a different path.
3. The office uploads to a trade and a master work order. The owner of a second org
   lists and signs neither (both are empty, with no error).
4. The crew member lists the trade file but not the master's. Their remove returns
   **nothing removed**; they can't delete.
5. Controls: `product-photos` anon read is unchanged, and `pdf-files` is still
   unreadable.
6. Clean up the synthetic objects and the member.

## 5 · App side — built, needs no migration (Track X)

- **Office, coordination work order page:** a "Roof data + photos" section with a
  list, add, and remove.
- **Crew, field work order, Packet tab:** the same list, view only.
- **Upload:** the route `POST …/coordination/[workOrderId]/files/upload-url` checks
  the session, that the work order is visible in this org, and
  `can_view_master_work_order`. Only then does it ask storage for a signed upload url
  with the user's JWT (confirmed on a stub: the storage call carries the user's
  `sub`, not the anon key). The browser PUTs the file directly: Vercel caps function
  bodies at 4.5 MB, and the browser uses plain `fetch` with no Supabase client (the
  tripwire passes, and fails when one is added).
- **Delete:** a server action that requires the path to name this org, this work
  order and `office-uploads`. "Nothing removed" is reported as `delete_refused`,
  never as success.
- **Named states, codes only:** `off`, `uploaded`, `upload_refused`,
  `upload_failed`, `too_large`, `wrong_type`, `deleted`, `delete_refused`,
  `delete_failed`. An unknown code renders nothing.
- **`off` is configuration** (`ORG_FILES_ENABLED`). Without policies, a read is an
  empty list with no error, which looks the same as "no files yet".

## 6 · Decisions that aren't Track X's

1. **Delete and write follow `view_master_work_order`.** No file-specific capability
   exists. Options: accept the mapping (works today, and crew can't delete), or add a
   `manage_files` capability. That changes `default_permissions_for_role` and needs a
   backfill of `org_members.permissions`, so it's Track S and Jacob's call.
2. **`client_portal_viewer` can read trade work orders,** so under this policy it can
   read their files. That comes from the `work_orders` policies, not from this file.
   Say whether that's intended.
3. The remaining categories (`check-in-photos` for A4.3, `estimate-pdfs`).

## 7 · For Jacob, after Track S applies and §4 passes

In Vercel → Project → Settings → Environment Variables, set `ORG_FILES_ENABLED` to
`true` for Production, then redeploy. No credential is involved.
