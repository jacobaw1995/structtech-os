-- Defense-in-depth: the orders tables are never read directly by anon (guest reads go
-- through the get_wh_order security-definer RPC). RLS already returns 0 rows to anon;
-- revoking the table-level SELECT grant also removes them from anon's GraphQL discovery.
-- Zero functional impact. authenticated SELECT is preserved (contractors read own orders
-- via PostgREST). wh_settings anon SELECT is intentionally NOT revoked (whitelist needs it).
REVOKE SELECT ON public.wh_orders           FROM anon;
REVOKE SELECT ON public.wh_order_line_items FROM anon;
REVOKE SELECT ON public.wh_spec_files       FROM anon;
REVOKE SELECT ON public.wh_drivers          FROM anon;
