-- P0 INCIDENT — 2026-08-28. TOKEN ROTATION. THE PART THAT MAKES THE FIX REAL.
--
-- Caught by Material Matrix after the first two migrations were already applied,
-- and it is the difference between a fix and a decoration.
--
-- THE REASONING, because it is the whole point. `token` sits in the SAME ROW the
-- open SELECT policy returned. So every token in this table must be treated as
-- ALREADY DISCLOSED. A definer RPC keyed on those tokens is COSMETIC: anyone who
-- pulled the table while the policy was open keeps PERMANENT access through the
-- new, legitimate path. Closing the door while leaving the stolen keys working is
-- not closing the door.
--
-- Rotation therefore belongs in the incident, not in a follow-up. Existing client
-- links break. THAT IS CORRECT AND IT IS THE POINT — a link that still works is a
-- link an attacker still holds.

-- ---------------------------------------------------------------------------
-- 1 · THE TRIGGER THAT WOULD HAVE ABORTED THIS
-- ---------------------------------------------------------------------------
-- `trg_protect_roadmap` fires BEFORE UPDATE and raises 'immutable columns' when
-- `new.token <> old.token`. It exists to stop the (now-removed) anonymous update
-- path from tampering with identity columns — a sound guard that happens to also
-- forbid the legitimate rotation. It is disabled for this statement ONLY and
-- re-enabled below, inside the same transaction, so there is no window in which
-- the table is unprotected.
alter table public.client_roadmaps disable trigger trg_protect_roadmap;

-- ---------------------------------------------------------------------------
-- 2 · ROTATE EVERY ROW
-- ---------------------------------------------------------------------------
-- gen_random_bytes() is VOLATILE, so it is evaluated per row and every row gets
-- its own value. `token` carries a UNIQUE constraint, so a collision would abort
-- this migration loudly rather than silently merging two clients' roadmaps.
--
-- WIDENED FROM 9 BYTES TO 16 (72 -> 128 bits), and the column default with it.
-- Stated plainly as an addition rather than slipped in: every token here is being
-- replaced anyway, so this is the one moment the change costs nothing, and the
-- old width was chosen when the token was believed to be the only thing standing
-- between the internet and this data. It is not a fix for the incident; it is
-- cheap insurance taken at the only free moment.
update public.client_roadmaps
   set token = encode(gen_random_bytes(16), 'hex');

alter table public.client_roadmaps
  alter column token set default encode(gen_random_bytes(16), 'hex');

-- ---------------------------------------------------------------------------
-- 3 · PROTECTION BACK ON
-- ---------------------------------------------------------------------------
alter table public.client_roadmaps enable trigger trg_protect_roadmap;

-- ---------------------------------------------------------------------------
-- 4 · CONSEQUENCE, RECORDED WHERE THE NEXT READER WILL SEE IT
-- ---------------------------------------------------------------------------
-- EVERY PREVIOUSLY-ISSUED ROADMAP LINK IS NOW DEAD. All 9 must be re-issued to
-- clients from the current values. No old token is recorded anywhere — not in
-- this file, not in the change log, not in the session transcript — because
-- writing down a revoked credential re-creates the exposure it was revoked for.