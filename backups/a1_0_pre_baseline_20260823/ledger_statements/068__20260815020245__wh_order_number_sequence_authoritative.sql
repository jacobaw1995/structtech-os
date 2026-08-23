-- 1. Sequence for 5-digit WO numbers. 1-digit prefix + 4-digit sequence.
--    Prefix 1 = Material Matrix. First order = 10001. Past 19999 it rolls
--    into the 2#### band naturally (plain monotonic counter, no special-casing).
CREATE SEQUENCE IF NOT EXISTS public.wh_order_number_seq
  AS bigint
  INCREMENT BY 1
  START WITH 10001
  MINVALUE 10001
  NO MAXVALUE
  NO CYCLE;

-- 2. create_wh_order becomes the AUTHORITATIVE allocator: it pulls the number
--    from the sequence and IGNORES any order_number the client supplies.
--    order_number stays TEXT with its existing unique index; on a 23505
--    collision it re-allocates (nextval again) rather than failing the order.
CREATE OR REPLACE FUNCTION public.create_wh_order(
  p_order jsonb,
  p_line_items jsonb DEFAULT '[]'::jsonb,
  p_spec_files jsonb DEFAULT '[]'::jsonb,
  p_org_id uuid DEFAULT NULL::uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_supplier     uuid := '1084baa8-0355-4298-9b98-b876a7581173';
  v_uid          uuid := auth.uid();
  v_org          uuid;
  v_order_id     uuid;
  v_order_num    text;
  v_driver_email text;
  v_item         jsonb;
  v_attempt      int;
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

  v_driver_email := (SELECT value FROM public.wh_settings
                      WHERE org_id = v_org AND key = 'driver_email');

  -- Authoritative order_number allocation. The client's order_number is ignored
  -- entirely. Retry on unique_violation (23505) by re-allocating from the sequence.
  <<alloc>>
  FOR v_attempt IN 1..20 LOOP
    v_order_num := nextval('public.wh_order_number_seq')::text;
    BEGIN
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
      EXIT alloc;  -- inserted cleanly with a unique number
    EXCEPTION WHEN unique_violation THEN
      IF v_attempt >= 20 THEN
        RAISE EXCEPTION 'create_wh_order: could not allocate a unique order_number after % attempts', v_attempt;
      END IF;
      -- fall through: next loop iteration re-allocates via nextval()
    END;
  END LOOP;

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
END $function$;
