-- WINDY HILL — ORDERS RLS + GUEST/CONTRACTOR RPCs. Depends on wh_orders_schema.

-- wh_orders: org members read + update their org's orders
DROP POLICY IF EXISTS "wh_orders org read"   ON public.wh_orders;
DROP POLICY IF EXISTS "wh_orders org update" ON public.wh_orders;
CREATE POLICY "wh_orders org read"   ON public.wh_orders
  FOR SELECT TO authenticated USING (org_id IN (SELECT my_org_ids()));
CREATE POLICY "wh_orders org update" ON public.wh_orders
  FOR UPDATE TO authenticated
  USING (org_id IN (SELECT my_org_ids()))
  WITH CHECK (org_id IN (SELECT my_org_ids()));

DROP POLICY IF EXISTS "wh_line_items org read" ON public.wh_order_line_items;
CREATE POLICY "wh_line_items org read" ON public.wh_order_line_items
  FOR SELECT TO authenticated USING (org_id IN (SELECT my_org_ids()));

DROP POLICY IF EXISTS "wh_spec_files org read" ON public.wh_spec_files;
CREATE POLICY "wh_spec_files org read" ON public.wh_spec_files
  FOR SELECT TO authenticated USING (org_id IN (SELECT my_org_ids()));

-- wh_settings: anon reads ONLY a non-secret key whitelist; make_webhook_url + driver_email stay private
DROP POLICY IF EXISTS "wh_settings public read supplier" ON public.wh_settings;
DROP POLICY IF EXISTS "wh_settings anon read whitelist"  ON public.wh_settings;
DROP POLICY IF EXISTS "wh_settings org all"              ON public.wh_settings;
CREATE POLICY "wh_settings anon read whitelist" ON public.wh_settings
  FOR SELECT TO anon
  USING (org_id = '1084baa8-0355-4298-9b98-b876a7581173'
         AND key IN ('stripe_publishable_key', 'maintenance_mode'));
CREATE POLICY "wh_settings org all" ON public.wh_settings
  FOR ALL TO authenticated
  USING (org_id IN (SELECT my_org_ids()))
  WITH CHECK (org_id IN (SELECT my_org_ids()));

DROP POLICY IF EXISTS "wh_drivers org all" ON public.wh_drivers;
CREATE POLICY "wh_drivers org all" ON public.wh_drivers
  FOR ALL TO authenticated
  USING (org_id IN (SELECT my_org_ids()))
  WITH CHECK (org_id IN (SELECT my_org_ids()));

-- RPC: create_wh_order — atomic guest/contractor order creation (org_id un-spoofable; driver_email server-resolved)
DROP FUNCTION IF EXISTS public.create_wh_order(jsonb, jsonb, jsonb, uuid);
CREATE OR REPLACE FUNCTION public.create_wh_order(
  p_order      jsonb,
  p_line_items jsonb DEFAULT '[]'::jsonb,
  p_spec_files jsonb DEFAULT '[]'::jsonb,
  p_org_id     uuid  DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_supplier     uuid := '1084baa8-0355-4298-9b98-b876a7581173';
  v_uid          uuid := auth.uid();
  v_org          uuid;
  v_order_id     uuid;
  v_order_num    text;
  v_driver_email text;
  v_item         jsonb;
BEGIN
  IF v_uid IS NULL THEN
    v_org := v_supplier;
  ELSE
    IF p_org_id IS NOT NULL AND p_org_id IN (SELECT my_org_ids()) THEN
      v_org := p_org_id;
    ELSE
      v_org := COALESCE((SELECT org_id FROM org_members WHERE user_id = v_uid LIMIT 1), v_supplier);
    END IF;
  END IF;

  v_order_num := COALESCE(NULLIF(p_order->>'order_number', ''),
                          'WH-' || (extract(epoch FROM clock_timestamp())*1000)::bigint::text);

  v_driver_email := (SELECT value FROM public.wh_settings
                      WHERE org_id = v_org AND key = 'driver_email');

  INSERT INTO public.wh_orders (
    org_id, order_number, system, customer_id, customer_name, customer_phone,
    customer_email, job_name, fulfillment, order_notes, order_total,
    status, driver_email, webhook_fired, webhook_payload
  ) VALUES (
    v_org, v_order_num, p_order->>'system', v_uid,
    p_order->>'customer_name', p_order->>'customer_phone', p_order->>'customer_email',
    p_order->>'job_name', p_order->>'fulfillment', p_order->>'order_notes',
    NULLIF(p_order->>'order_total','')::numeric,
    COALESCE(NULLIF(p_order->>'status',''), 'pending'),
    v_driver_email, false, p_order->'webhook_payload'
  )
  RETURNING id INTO v_order_id;

  FOR v_item IN SELECT * FROM jsonb_array_elements(COALESCE(p_line_items, '[]'::jsonb))
  LOOP
    INSERT INTO public.wh_order_line_items (
      org_id, order_id, category, description, specs, amount, display_order
    ) VALUES (
      v_org, v_order_id, v_item->>'category', v_item->>'description', v_item->>'specs',
      NULLIF(v_item->>'amount','')::numeric,
      COALESCE(NULLIF(v_item->>'display_order','')::int, 0)
    );
  END LOOP;

  FOR v_item IN SELECT * FROM jsonb_array_elements(COALESCE(p_spec_files, '[]'::jsonb))
  LOOP
    INSERT INTO public.wh_spec_files (
      org_id, order_id, filename, storage_url, description
    ) VALUES (
      v_org, v_order_id, v_item->>'filename',
      COALESCE(v_item->>'storage_url', v_item->>'url'), v_item->>'description'
    );
  END LOOP;

  RETURN jsonb_build_object('order_id', v_order_id, 'order_number', v_order_num);
END $$;

REVOKE ALL ON FUNCTION public.create_wh_order(jsonb, jsonb, jsonb, uuid) FROM public;
GRANT EXECUTE ON FUNCTION public.create_wh_order(jsonb, jsonb, jsonb, uuid) TO anon, authenticated;

-- RPC: get_wh_order — guest confirmation read (curated columns only)
DROP FUNCTION IF EXISTS public.get_wh_order(text, text);
CREATE OR REPLACE FUNCTION public.get_wh_order(
  p_order_number text,
  p_email        text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order jsonb;
BEGIN
  SELECT jsonb_build_object(
           'order_number',   o.order_number,
           'order_date',     o.order_date,
           'created_at',     o.created_at,
           'status',         o.status,
           'system',         o.system,
           'customer_name',  o.customer_name,
           'customer_email', o.customer_email,
           'customer_phone', o.customer_phone,
           'job_name',       o.job_name,
           'fulfillment',    o.fulfillment,
           'order_notes',    o.order_notes,
           'order_total',    o.order_total,
           'pdf_url',        o.pdf_url,
           'line_items', COALESCE((SELECT jsonb_agg(jsonb_build_object(
                                     'category', li.category, 'description', li.description,
                                     'specs', li.specs, 'amount', li.amount) ORDER BY li.display_order)
                                     FROM public.wh_order_line_items li WHERE li.order_id = o.id), '[]'::jsonb),
           'spec_files', COALESCE((SELECT jsonb_agg(jsonb_build_object(
                                     'filename', sf.filename, 'description', sf.description))
                                     FROM public.wh_spec_files sf WHERE sf.order_id = o.id), '[]'::jsonb)
         )
    INTO v_order
    FROM public.wh_orders o
   WHERE o.order_number = p_order_number
     AND lower(o.customer_email) = lower(p_email)
   LIMIT 1;

  RETURN v_order;
END $$;

REVOKE ALL ON FUNCTION public.get_wh_order(text, text) FROM public;
GRANT EXECUTE ON FUNCTION public.get_wh_order(text, text) TO anon, authenticated;
