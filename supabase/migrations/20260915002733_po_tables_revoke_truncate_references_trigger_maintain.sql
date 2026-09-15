-- SECURITY, 2026-09-14 (Track S). The three purchase-order tables created by A2.3
-- (20260907230009) carried `authenticated=arwdDxtm` — TRUNCATE, REFERENCES, TRIGGER and
-- MAINTAIN on top of the house grant. RLS cannot mediate TRUNCATE.
--
-- PROVED BEFORE THIS RAN, rolled back: as `authenticated` with the JWT of a Material Matrix
-- member who has NO membership in Brothers Metal Roofing (and SELECTs 0 PO rows through RLS),
-- `truncate public.purchase_order_line_promises` SUCCEEDED — 1 row -> 0.
--
-- WHY THE SWEEPS MISSED IT: CLAUDE.md rule 8 required only the `anon` revoke on a new table,
-- and the 2026-08-29..31 sweeps measured `anon`. These tables were created on 2026-09-07.
-- Rule 8 is amended today: a new table's grant set is matched to the house standard for BOTH
-- roles.
--
-- HOUSE STANDARD, MEASURED 2026-09-14 over 51 owned tables: `authenticated` holds exactly
-- SELECT, INSERT, UPDATE, DELETE on 44; `anon` holds nothing on 49. MAINTAIN is revoked here
-- too, because the standard does not carry it (reported beside the three the controller named).
-- Rollback: grant truncate, references, trigger, maintain on the three tables to authenticated.

revoke truncate, references, trigger, maintain on table public.purchase_orders from authenticated;
revoke truncate, references, trigger, maintain on table public.purchase_order_lines from authenticated;
revoke truncate, references, trigger, maintain on table public.purchase_order_line_promises from authenticated;

do $$
declare t text; p text;
begin
  foreach t in array array['purchase_orders','purchase_order_lines','purchase_order_line_promises'] loop
    foreach p in array array['TRUNCATE','REFERENCES','TRIGGER','MAINTAIN'] loop
      if has_table_privilege('authenticated', ('public.' || t)::regclass, p) then
        raise exception 'authenticated still holds % on %', p, t;
      end if;
    end loop;
    foreach p in array array['SELECT','INSERT','UPDATE','DELETE'] loop
      if not has_table_privilege('authenticated', ('public.' || t)::regclass, p) then
        raise exception 'authenticated lost % on % — the application writes through it', p, t;
      end if;
    end loop;
  end loop;
end $$;