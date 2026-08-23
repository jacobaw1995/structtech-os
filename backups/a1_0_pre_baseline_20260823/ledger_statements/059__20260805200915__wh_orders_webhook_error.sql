ALTER TABLE public.wh_orders
  ADD COLUMN IF NOT EXISTS webhook_error text;
