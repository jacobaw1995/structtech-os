-- WH SUPPLIER CATALOG — Landing Zone DDL
-- ejlhrykcdfcyeooooodx

CREATE TABLE IF NOT EXISTS wh_systems (
  id              uuid PRIMARY KEY,
  org_id          uuid NOT NULL REFERENCES organizations(id),
  name            text NOT NULL,
  slug            text NOT NULL,
  hero_image_url  text,
  tagline         text,
  description     text,
  display_order   int  DEFAULT 0,
  active          boolean DEFAULT true,
  created_at      timestamptz DEFAULT now(),
  UNIQUE (org_id, slug)
);

CREATE TABLE IF NOT EXISTS wh_stages (
  id              uuid PRIMARY KEY,
  org_id          uuid NOT NULL REFERENCES organizations(id),
  system_id       uuid NOT NULL REFERENCES wh_systems(id) ON DELETE CASCADE,
  name            text NOT NULL,
  display_order   int  NOT NULL,
  active          boolean NOT NULL DEFAULT true
);

CREATE TABLE IF NOT EXISTS wh_categories (
  id              uuid PRIMARY KEY,
  org_id          uuid NOT NULL REFERENCES organizations(id),
  system_id       uuid NOT NULL REFERENCES wh_systems(id) ON DELETE CASCADE,
  stage_id        uuid REFERENCES wh_stages(id),
  name            text NOT NULL,
  slug            text NOT NULL,
  microcopy       text,
  image_url       text,
  required        boolean DEFAULT false,
  badge           text DEFAULT 'OPTIONAL',
  skip_label      text,
  display_order   int  DEFAULT 0,
  active          boolean DEFAULT true,
  catalog_section text,
  created_at      timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS wh_products (
  id                  uuid PRIMARY KEY,
  org_id              uuid NOT NULL REFERENCES organizations(id),
  name                text NOT NULL,
  sku                 text,
  description         text,
  gauge               text,
  finish              text,
  image_url           text,
  unit_type           text DEFAULT 'linear_foot',
  unit_size           text,
  base_price          numeric(10,2),
  active              boolean DEFAULT true,
  display_order       int  DEFAULT 0,
  product_type        text,
  catalog_section     text,
  compatible_systems  text[] DEFAULT '{}',
  created_at          timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_wh_products_catalog_section    ON wh_products (catalog_section);
CREATE INDEX IF NOT EXISTS idx_wh_products_compatible_systems ON wh_products USING GIN (compatible_systems);

CREATE TABLE IF NOT EXISTS wh_colors (
  id               uuid PRIMARY KEY,
  org_id           uuid NOT NULL REFERENCES organizations(id),
  name             text NOT NULL,
  hex_code         text,
  swatch_image_url text,
  active           boolean DEFAULT true,
  display_order    int  DEFAULT 0,
  created_at       timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS wh_product_colors (
  product_id      uuid NOT NULL REFERENCES wh_products(id) ON DELETE CASCADE,
  color_id        uuid NOT NULL REFERENCES wh_colors(id)   ON DELETE CASCADE,
  price_modifier  numeric(10,2) DEFAULT 0,
  PRIMARY KEY (product_id, color_id)
);

CREATE TABLE IF NOT EXISTS wh_length_options (
  id              uuid PRIMARY KEY,
  org_id          uuid NOT NULL REFERENCES organizations(id),
  label           text NOT NULL,
  value_ft        numeric(5,2) NOT NULL,
  active          boolean DEFAULT true,
  display_order   int  DEFAULT 0
);

CREATE TABLE IF NOT EXISTS wh_product_lengths (
  product_id        uuid NOT NULL REFERENCES wh_products(id)       ON DELETE CASCADE,
  length_option_id  uuid NOT NULL REFERENCES wh_length_options(id) ON DELETE CASCADE,
  PRIMARY KEY (product_id, length_option_id)
);

CREATE TABLE IF NOT EXISTS wh_category_products (
  category_id  uuid NOT NULL REFERENCES wh_categories(id) ON DELETE CASCADE,
  product_id   uuid NOT NULL REFERENCES wh_products(id)   ON DELETE CASCADE,
  PRIMARY KEY (category_id, product_id)
);

-- RLS
ALTER TABLE wh_systems           ENABLE ROW LEVEL SECURITY;
ALTER TABLE wh_stages            ENABLE ROW LEVEL SECURITY;
ALTER TABLE wh_categories        ENABLE ROW LEVEL SECURITY;
ALTER TABLE wh_products          ENABLE ROW LEVEL SECURITY;
ALTER TABLE wh_colors            ENABLE ROW LEVEL SECURITY;
ALTER TABLE wh_product_colors    ENABLE ROW LEVEL SECURITY;
ALTER TABLE wh_length_options    ENABLE ROW LEVEL SECURITY;
ALTER TABLE wh_product_lengths   ENABLE ROW LEVEL SECURITY;
ALTER TABLE wh_category_products ENABLE ROW LEVEL SECURITY;

-- All authenticated users can read (shared catalog — all contractor tenants)
CREATE POLICY "Authenticated read wh_systems"           ON wh_systems           FOR SELECT USING (auth.role() = 'authenticated');
CREATE POLICY "Authenticated read wh_stages"            ON wh_stages            FOR SELECT USING (auth.role() = 'authenticated');
CREATE POLICY "Authenticated read wh_categories"        ON wh_categories        FOR SELECT USING (auth.role() = 'authenticated');
CREATE POLICY "Authenticated read wh_products"          ON wh_products          FOR SELECT USING (auth.role() = 'authenticated');
CREATE POLICY "Authenticated read wh_colors"            ON wh_colors            FOR SELECT USING (auth.role() = 'authenticated');
CREATE POLICY "Authenticated read wh_product_colors"    ON wh_product_colors    FOR SELECT USING (auth.role() = 'authenticated');
CREATE POLICY "Authenticated read wh_length_options"    ON wh_length_options    FOR SELECT USING (auth.role() = 'authenticated');
CREATE POLICY "Authenticated read wh_product_lengths"   ON wh_product_lengths   FOR SELECT USING (auth.role() = 'authenticated');
CREATE POLICY "Authenticated read wh_category_products" ON wh_category_products FOR SELECT USING (auth.role() = 'authenticated');

-- WH org members can write (uses existing my_org_ids() helper)
CREATE POLICY "WH org write wh_systems"
  ON wh_systems FOR ALL
  USING (org_id IN (SELECT my_org_ids()))
  WITH CHECK (org_id IN (SELECT my_org_ids()));

CREATE POLICY "WH org write wh_stages"
  ON wh_stages FOR ALL
  USING (org_id IN (SELECT my_org_ids()))
  WITH CHECK (org_id IN (SELECT my_org_ids()));

CREATE POLICY "WH org write wh_categories"
  ON wh_categories FOR ALL
  USING (org_id IN (SELECT my_org_ids()))
  WITH CHECK (org_id IN (SELECT my_org_ids()));

CREATE POLICY "WH org write wh_products"
  ON wh_products FOR ALL
  USING (org_id IN (SELECT my_org_ids()))
  WITH CHECK (org_id IN (SELECT my_org_ids()));

CREATE POLICY "WH org write wh_colors"
  ON wh_colors FOR ALL
  USING (org_id IN (SELECT my_org_ids()))
  WITH CHECK (org_id IN (SELECT my_org_ids()));

CREATE POLICY "WH org write wh_length_options"
  ON wh_length_options FOR ALL
  USING (org_id IN (SELECT my_org_ids()))
  WITH CHECK (org_id IN (SELECT my_org_ids()));

CREATE POLICY "WH org write wh_product_colors"
  ON wh_product_colors FOR ALL
  USING (product_id IN (SELECT id FROM wh_products WHERE org_id IN (SELECT my_org_ids())));

CREATE POLICY "WH org write wh_product_lengths"
  ON wh_product_lengths FOR ALL
  USING (product_id IN (SELECT id FROM wh_products WHERE org_id IN (SELECT my_org_ids())));

CREATE POLICY "WH org write wh_category_products"
  ON wh_category_products FOR ALL
  USING (category_id IN (SELECT id FROM wh_categories WHERE org_id IN (SELECT my_org_ids())));
