-- WINDY HILL — ORDERS SCHEMA (structural only). Target: ejlhrykcdfcyeooooodx.
-- Tables created EMPTY; org_id added; wh_ prefixed. No Stripe columns (Thursday).

-- Guard: fail loudly if run against the wrong project (catalog absent).
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.tables
                 WHERE table_schema = 'public' AND table_name = 'wh_products') THEN
    RAISE EXCEPTION 'wh_products not found — are you connected to the structtech project (ejlhrykcdfcyeooooodx)?';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.organizations
                 WHERE id = '1084baa8-0355-4298-9b98-b876a7581173') THEN
    RAISE EXCEPTION 'Material Matrix supplier org (1084baa8-...) not found in organizations.';
  END IF;
END $$;

CREATE TABLE IF NOT EXISTS public.wh_orders (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id           uuid NOT NULL DEFAULT '1084baa8-0355-4298-9b98-b876a7581173'
                     REFERENCES public.organizations(id),
  order_number     text NOT NULL UNIQUE,
  order_date       timestamptz DEFAULT now(),
  system           text,
  customer_id      uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  customer_name    text,
  customer_phone   text,
  customer_email   text,
  job_name         text,
  fulfillment      text,
  order_notes      text,
  order_total      numeric(10,2),
  status           text DEFAULT 'pending',
  driver_email     text,
  webhook_fired    boolean DEFAULT false,
  webhook_payload  jsonb,
  pdf_url          text,
  pdf_generated_at timestamptz,
  created_at       timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.wh_order_line_items (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id        uuid NOT NULL DEFAULT '1084baa8-0355-4298-9b98-b876a7581173'
                  REFERENCES public.organizations(id),
  order_id      uuid NOT NULL REFERENCES public.wh_orders(id) ON DELETE CASCADE,
  category      text,
  description   text,
  specs         text,
  amount        numeric(10,2),
  display_order int DEFAULT 0
);

CREATE TABLE IF NOT EXISTS public.wh_spec_files (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id      uuid NOT NULL DEFAULT '1084baa8-0355-4298-9b98-b876a7581173'
                REFERENCES public.organizations(id),
  order_id    uuid NOT NULL REFERENCES public.wh_orders(id) ON DELETE CASCADE,
  filename    text,
  storage_url text,
  description text,
  created_at  timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.wh_settings (
  org_id     uuid NOT NULL DEFAULT '1084baa8-0355-4298-9b98-b876a7581173'
               REFERENCES public.organizations(id),
  key        text NOT NULL,
  value      text,
  updated_at timestamptz DEFAULT now(),
  PRIMARY KEY (org_id, key)
);

CREATE TABLE IF NOT EXISTS public.wh_drivers (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id     uuid NOT NULL DEFAULT '1084baa8-0355-4298-9b98-b876a7581173'
               REFERENCES public.organizations(id),
  name       text NOT NULL,
  email      text NOT NULL,
  phone      text,
  active     boolean DEFAULT true,
  created_at timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_wh_orders_org_id         ON public.wh_orders (org_id);
CREATE INDEX IF NOT EXISTS idx_wh_orders_customer_id     ON public.wh_orders (customer_id);
CREATE INDEX IF NOT EXISTS idx_wh_orders_order_number    ON public.wh_orders (order_number);
CREATE INDEX IF NOT EXISTS idx_wh_orders_customer_email  ON public.wh_orders (lower(customer_email));
CREATE INDEX IF NOT EXISTS idx_wh_line_items_order_id     ON public.wh_order_line_items (order_id);
CREATE INDEX IF NOT EXISTS idx_wh_line_items_org_id       ON public.wh_order_line_items (org_id);
CREATE INDEX IF NOT EXISTS idx_wh_spec_files_order_id     ON public.wh_spec_files (order_id);
CREATE INDEX IF NOT EXISTS idx_wh_spec_files_org_id       ON public.wh_spec_files (org_id);
CREATE INDEX IF NOT EXISTS idx_wh_drivers_org_id          ON public.wh_drivers (org_id);

ALTER TABLE public.wh_orders           ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.wh_order_line_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.wh_spec_files       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.wh_settings         ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.wh_drivers          ENABLE ROW LEVEL SECURITY;
