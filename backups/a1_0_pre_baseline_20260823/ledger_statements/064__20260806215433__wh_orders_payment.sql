BEGIN;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.tables
                 WHERE table_schema = 'public' AND table_name = 'wh_orders') THEN
    RAISE EXCEPTION 'wh_orders not found — are you connected to the structtech project (ejlhrykcdfcyeooooodx)?';
  END IF;
END $$;

ALTER TABLE public.wh_orders
  ADD COLUMN IF NOT EXISTS payment_status           text NOT NULL DEFAULT 'unpaid',
  ADD COLUMN IF NOT EXISTS stripe_payment_intent_id text,
  ADD COLUMN IF NOT EXISTS amount_paid_cents        integer,
  ADD COLUMN IF NOT EXISTS paid_at                  timestamptz;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'wh_orders_payment_status_chk') THEN
    ALTER TABLE public.wh_orders
      ADD CONSTRAINT wh_orders_payment_status_chk
      CHECK (payment_status IN ('unpaid','paid','refunded','not_required'));
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_wh_orders_stripe_pi
  ON public.wh_orders (stripe_payment_intent_id);

COMMIT;
