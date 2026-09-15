-- NO DOLLARS IN THE FIELD — THE GUARD EXTENDED TO WHAT THE PROPERTY ACTUALLY COVERS. Track S · 2026-09-14.
--
-- THE PROPERTY (controller): A MEMBER WITHOUT view_financials MUST NOT BE ABLE TO READ A MONEY
-- VALUE, OR A VALUE FROM WHICH A MONEY VALUE CAN BE DERIVED, FROM ANY TABLE — NOR THE CONTENT OF
-- A RECORD WHOSE PARENT THEY ARE FORBIDDEN TO SEE.
--
-- DENOMINATOR, derived from the catalog: 51 owned tables · 560 columns. Qualifying: 22 money or
-- money-bearing columns in 11 tables, plus the whole rows of 4 child-content tables of a guarded
-- parent (34 columns, 2 already counted) — 54 columns in 14 tables.
-- COVERAGE BEFORE: 4 tables guarded by a restrictive can_view_financials policy (deals, estimates,
-- estimate_line_items, products); 3 unreachable by any member (leads and proposals staff/platform
-- only; structtech_state no authenticated grant); 7 member-readable and UNGUARDED — closed here.
--
-- PROVED BEFORE THIS RAN (rolled back): as `authenticated`, a synthetic office member of BMR and
-- StructTech with view_estimates=true and view_financials=false read 0 deals — and 174 deal_notes,
-- 634 deal_activity rows (5 of them `value_set`, money in text), 10 follow_ups with subject and
-- recipient, 4 signatures, 4 org_invoices amounts, 1 client_roadmaps revenue_leak_monthly and 6
-- audit_leads monthly_leak values.
--
-- THE GUARD: a RESTRICTIVE SELECT policy, scoped TO authenticated (rule 8: a policy left TO public
-- is evaluated for anon — audit_leads keeps its anonymous lead-form INSERT, which SELECT policies
-- do not touch), testing can_view_financials(org_id) — the same predicate the four guarded parents
-- use, on the child's own org_id, so a child is readable exactly when its parent is.
--
-- NAMED, NOT CLOSED HERE (dated 2026-09-14):
--   · work_order_agreements.snapshot copies estimate HEADER content (contact name, phone, email,
--     site address, squares) — no money; 0 rows; already restricted to master viewers. Its gate is
--     a decision about what a sign-off document may copy, and remote signing (Task 2) reshapes it.
--   · Deliberate copies a crew needs, no money: jobs.service_address_* (from the deal),
--     material_items.name/quantity/unit (from the estimate line). A1.5's crew guarantees.
--   · Not money, not derivable: purchase_orders / purchase_order_lines / purchase_order_line_promises
--     (A2.3 ruled no money on a PO) and check_ins.hours (no rate is stored anywhere).
--   · SECURITY DEFINER surface: 17 functions read these tables; none returns their rows or a money
--     value to a member caller (writers, and fetch_roadmap_by_token, which is token-scoped).

create policy "no dollars in the field - deal_notes" on public.deal_notes
  as restrictive for select to authenticated using (public.can_view_financials(org_id));
create policy "no dollars in the field - deal_activity" on public.deal_activity
  as restrictive for select to authenticated using (public.can_view_financials(org_id));
create policy "no dollars in the field - follow_ups" on public.follow_ups
  as restrictive for select to authenticated using (public.can_view_financials(org_id));
create policy "no dollars in the field - signatures" on public.signatures
  as restrictive for select to authenticated using (public.can_view_financials(org_id));
create policy "no dollars in the field - org_invoices" on public.org_invoices
  as restrictive for select to authenticated using (public.can_view_financials(org_id));
create policy "no dollars in the field - client_roadmaps" on public.client_roadmaps
  as restrictive for select to authenticated using (public.can_view_financials(org_id));
create policy "no dollars in the field - audit_leads" on public.audit_leads
  as restrictive for select to authenticated using (public.can_view_financials(org_id));

do $$
declare t text;
begin
  foreach t in array array['deal_notes','deal_activity','follow_ups','signatures','org_invoices','client_roadmaps','audit_leads'] loop
    if not exists (select 1 from pg_policy pol where pol.polrelid = ('public.' || t)::regclass
                    and not pol.polpermissive and pol.polcmd = 'r'
                    and pg_get_expr(pol.polqual, pol.polrelid) ~ 'can_view_financials') then
      raise exception 'restrictive financial guard missing on %', t;
    end if;
  end loop;
end $$;