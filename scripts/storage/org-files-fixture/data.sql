-- Synthetic fixture. No real org, user or file. Loaded as superuser (bypasses RLS).
-- Org A has a MASTER and a TRADE work order; org B has a TRADE work order.
-- Members: A owner, A office, A crew (field), A member whose view_master_work_order
-- was switched OFF per member, B owner. Permission rows are the live
-- default_permissions_for_role() output for each role, as org_members carries them.
insert into storage.buckets (id, name, public) values
  ('org-files','org-files',false), ('product-photos','product-photos',true), ('pdf-files','pdf-files',false);

insert into public.org_members values
  ('aaaaaaaa-0000-0000-0000-000000000001','a0000000-0000-0000-0000-00000000000a','owner',
    '{"view_financials":true,"view_estimates":true,"view_field":true,"view_master_work_order":true}'),
  ('aaaaaaaa-0000-0000-0000-000000000001','a0000000-0000-0000-0000-00000000000f','office',
    '{"view_financials":true,"view_estimates":true,"view_field":true,"view_master_work_order":true}'),
  ('aaaaaaaa-0000-0000-0000-000000000001','a0000000-0000-0000-0000-0000000000c1','field',
    '{"view_financials":false,"view_estimates":false,"view_field":true,"view_master_work_order":false}'),
  ('aaaaaaaa-0000-0000-0000-000000000001','a0000000-0000-0000-0000-0000000000e0','member',
    '{"view_financials":true,"view_estimates":true,"view_field":true,"view_master_work_order":false}'),
  ('bbbbbbbb-0000-0000-0000-000000000002','b0000000-0000-0000-0000-00000000000b','owner',
    '{"view_financials":true,"view_estimates":true,"view_field":true,"view_master_work_order":true}');

insert into public.work_orders values
  ('aaaa0000-0000-0000-0000-000000000a57','aaaaaaaa-0000-0000-0000-000000000001','master'),
  ('aaaa0000-0000-0000-0000-000000000ade','aaaaaaaa-0000-0000-0000-000000000001','trade'),
  ('bbbb0000-0000-0000-0000-000000000bde','bbbbbbbb-0000-0000-0000-000000000002','trade');

insert into storage.objects (bucket_id, name) values
  ('org-files','aaaaaaaa-0000-0000-0000-000000000001/office-uploads/aaaa0000-0000-0000-0000-000000000ade/n1-roof-A-trade.jpg'),
  ('org-files','aaaaaaaa-0000-0000-0000-000000000001/work-order-docs/aaaa0000-0000-0000-0000-000000000a57/n2-plan-A-master.pdf'),
  ('org-files','bbbbbbbb-0000-0000-0000-000000000002/office-uploads/bbbb0000-0000-0000-0000-000000000bde/n3-roof-B-trade.jpg'),
  -- forged: B's prefix naming A's work order, created by a path that bypassed RLS
  ('org-files','bbbbbbbb-0000-0000-0000-000000000002/office-uploads/aaaa0000-0000-0000-0000-000000000ade/n4-forged.jpg'),
  -- a category no policy covers
  ('org-files','aaaaaaaa-0000-0000-0000-000000000001/estimate-pdfs/aaaa0000-0000-0000-0000-000000000ade/n5-priced.pdf'),
  -- malformed names in the same bucket: must compare false, never raise
  ('org-files','not-a-uuid/office-uploads/also-not/n6.jpg'),
  ('org-files','n7-top-level.jpg'),
  -- controls
  ('product-photos','catalog/p1.jpg'),
  ('pdf-files','work-orders/w1.pdf');
