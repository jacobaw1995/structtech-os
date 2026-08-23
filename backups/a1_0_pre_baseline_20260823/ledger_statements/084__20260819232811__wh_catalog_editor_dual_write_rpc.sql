-- CP3 step 10 — the family/variation editor write path.
-- ONE security-definer RPC performing the ENTIRE dual write in ONE transaction,
-- per CP3-PLAN.md §5.1. Either both models move together or neither does.

alter table public.wh_product_variations add column if not exists image_url text;
comment on column public.wh_product_variations.image_url is
  'Per-variation photo. Storefront resolver order: variation -> family -> category -> repo convention.';

create or replace function public.wh_save_catalog_family(p_family jsonb, p_variations jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $fn$
declare
  v_org       uuid := '1084baa8-0355-4298-9b98-b876a7581173';
  v_role      text;
  v_family_id uuid;
  v_new_fam   boolean;
  v_systems   text[];
  v_ptype     text;
  v_section   text;
  v_type_id   uuid;
  v_elem      jsonb;
  v_var_id    uuid;
  v_prod_id   uuid;
  v_name      text;
  v_prod_name text;
  v_price     numeric(10,2);
  v_unit      text;
  v_cur_price numeric(10,2);
  v_cur_from  timestamptz;
  v_close_at  timestamptz;
  v_opened    boolean;
  v_status    text;
  v_colors    uuid[];
  v_cats      uuid[];
  v_results   jsonb := '[]'::jsonb;
begin
  -- ── Authorisation. SECURITY DEFINER bypasses RLS, so this IS the gate. ────
  v_role := public.my_wh_role();
  if v_role is null then
    raise exception 'Your account is not set up as a Material Matrix team member, so nothing was saved. Ask an admin to add you.'
      using errcode = '42501';
  end if;
  if v_role not in ('admin','assistant') then
    raise exception 'Your role (%) can view the catalog but not change it. Nothing was saved.', v_role
      using errcode = '42501';
  end if;
  if v_org not in (select public.my_org_ids()) then
    raise exception 'Your account is not a member of the Material Matrix organisation, so nothing was saved.'
      using errcode = '42501';
  end if;

  -- ── Validation, in the language of the screen ────────────────────────────
  if coalesce(btrim(p_family->>'name'), '') = '' then
    raise exception 'This product needs a name before it can be saved.' using errcode = '23514';
  end if;
  if p_variations is null or jsonb_typeof(p_variations) <> 'array'
     or jsonb_array_length(p_variations) = 0 then
    raise exception 'Add at least one option to "%" before saving. Every product needs one option, even if it is just "Standard".',
      btrim(p_family->>'name') using errcode = '23514';
  end if;

  v_systems := coalesce(array(select jsonb_array_elements_text(
                 case when jsonb_typeof(p_family->'compatible_systems') = 'array'
                      then p_family->'compatible_systems' else '[]'::jsonb end)), '{}'::text[]);
  v_ptype   := nullif(btrim(coalesce(p_family->>'product_type','')), '');
  v_section := nullif(btrim(coalesce(p_family->>'catalog_section','')), '');
  v_type_id := nullif(p_family->>'type_id', '')::uuid;

  -- ── Family ───────────────────────────────────────────────────────────────
  v_family_id := nullif(p_family->>'id', '')::uuid;
  v_new_fam   := v_family_id is null;

  begin
    if v_new_fam then
      insert into public.wh_product_families
        (org_id, name, slug, product_type, type_id, catalog_section,
         compatible_systems, image_url, status, display_order)
      values
        (v_org, btrim(p_family->>'name'), nullif(btrim(coalesce(p_family->>'slug','')),''),
         v_ptype, v_type_id, v_section, v_systems,
         nullif(btrim(coalesce(p_family->>'image_url','')),''),
         coalesce(nullif(p_family->>'status',''), 'live'),
         coalesce((p_family->>'display_order')::int, 0))
      returning id into v_family_id;
    else
      update public.wh_product_families
         set name               = btrim(p_family->>'name'),
             slug               = nullif(btrim(coalesce(p_family->>'slug','')),''),
             product_type       = v_ptype,
             type_id            = v_type_id,
             catalog_section    = v_section,
             compatible_systems = v_systems,
             image_url          = nullif(btrim(coalesce(p_family->>'image_url','')),''),
             status             = coalesce(nullif(p_family->>'status',''), 'live'),
             display_order      = coalesce((p_family->>'display_order')::int, 0)
       where id = v_family_id and org_id = v_org;
      if not found then
        raise exception 'That product no longer exists — someone may have deleted it. Reload the page and try again.'
          using errcode = 'P0002';
      end if;
    end if;
  exception when unique_violation then
    raise exception 'There is already a product called "%". Use a different name.', btrim(p_family->>'name')
      using errcode = '23505';
  end;

  -- ── Each option: mirror row FIRST, then variation, then price/colors/cats ─
  for v_elem in select * from jsonb_array_elements(p_variations)
  loop
    v_var_id := nullif(v_elem->>'id', '')::uuid;
    v_name   := btrim(coalesce(v_elem->>'name', ''));
    if v_name = '' then
      raise exception 'One of the options on "%" has no name. Give every option a name (for example 4", or 26 GA Smooth).',
        btrim(p_family->>'name') using errcode = '23514';
    end if;

    v_price := nullif(btrim(coalesce(v_elem->>'price','')), '')::numeric(10,2);
    if v_price is not null and v_price < 0 then
      raise exception 'The price for "%" cannot be negative.', v_name using errcode = '23514';
    end if;
    v_unit   := nullif(btrim(coalesce(v_elem->>'price_unit','')), '');
    v_status := coalesce(nullif(v_elem->>'status',''), 'live');

    v_colors := coalesce(array(select jsonb_array_elements_text(
                  case when jsonb_typeof(v_elem->'color_ids') = 'array'
                       then v_elem->'color_ids' else '[]'::jsonb end))::uuid[], '{}'::uuid[]);
    v_cats   := coalesce(array(select jsonb_array_elements_text(
                  case when jsonb_typeof(v_elem->'category_ids') = 'array'
                       then v_elem->'category_ids' else '[]'::jsonb end))::uuid[], '{}'::uuid[]);

    -- existing mirror row, if this option already exists
    v_prod_id := null;
    if v_var_id is not null then
      select source_product_id into v_prod_id
        from public.wh_product_variations where id = v_var_id and org_id = v_org;
    end if;

    -- Storefront display name. The live catalog uses THREE different conventions
    -- ("Fascia Trim — 4\" Crinkle", "1 1/2\" Copper Screws", bare "Vented Soffit"),
    -- so this is never auto-derived for an existing product: renaming a live
    -- product silently is worse than an imperfect default. Explicit value wins,
    -- then the existing name, and only a brand-new row gets a derived default.
    v_prod_name := nullif(btrim(coalesce(v_elem->>'product_name','')), '');
    if v_prod_name is null and v_prod_id is not null then
      select name into v_prod_name from public.wh_products where id = v_prod_id;
    end if;
    if v_prod_name is null then
      v_prod_name := case
        when jsonb_array_length(p_variations) = 1
             and lower(v_name) in ('standard','default','one size')
        then btrim(p_family->>'name')
        else btrim(p_family->>'name') || ' — ' || v_name end;
    end if;

    -- ── Mirror row (wh_products) — still authoritative for the storefront ──
    if v_prod_id is null then
      insert into public.wh_products
        (org_id, name, sku, base_price, unit_type, gauge, finish, active, image_url,
         product_type, catalog_section, compatible_systems, display_order)
      values
        (v_org, v_prod_name, nullif(btrim(coalesce(v_elem->>'sku','')),''), v_price, v_unit,
         nullif(btrim(coalesce(v_elem->>'gauge','')),''), nullif(btrim(coalesce(v_elem->>'finish','')),''),
         (v_status = 'live'), nullif(btrim(coalesce(v_elem->>'image_url','')),''),
         v_ptype, v_section, v_systems, coalesce((v_elem->>'display_order')::int, 0))
      returning id into v_prod_id;
    else
      update public.wh_products
         set name = v_prod_name,
             sku = nullif(btrim(coalesce(v_elem->>'sku','')),''),
             base_price = v_price,
             unit_type = v_unit,
             gauge = nullif(btrim(coalesce(v_elem->>'gauge','')),''),
             finish = nullif(btrim(coalesce(v_elem->>'finish','')),''),
             active = (v_status = 'live'),
             image_url = nullif(btrim(coalesce(v_elem->>'image_url','')),''),
             product_type = v_ptype,
             catalog_section = v_section,
             compatible_systems = v_systems,
             display_order = coalesce((v_elem->>'display_order')::int, 0)
       where id = v_prod_id;
    end if;

    -- ── Variation row, bridged to the mirror ────────────────────────────────
    if v_var_id is null then
      insert into public.wh_product_variations
        (org_id, family_id, source_product_id, name, sku, price, price_unit,
         gauge, finish, status, display_order, image_url, type_id)
      values
        (v_org, v_family_id, v_prod_id, v_name, nullif(btrim(coalesce(v_elem->>'sku','')),''),
         v_price, v_unit, nullif(btrim(coalesce(v_elem->>'gauge','')),''),
         nullif(btrim(coalesce(v_elem->>'finish','')),''), v_status,
         coalesce((v_elem->>'display_order')::int, 0),
         nullif(btrim(coalesce(v_elem->>'image_url','')),''), v_type_id)
      returning id into v_var_id;
    else
      update public.wh_product_variations
         set family_id = v_family_id, source_product_id = v_prod_id, name = v_name,
             sku = nullif(btrim(coalesce(v_elem->>'sku','')),''),
             price = v_price, price_unit = v_unit,
             gauge = nullif(btrim(coalesce(v_elem->>'gauge','')),''),
             finish = nullif(btrim(coalesce(v_elem->>'finish','')),''),
             status = v_status,
             display_order = coalesce((v_elem->>'display_order')::int, 0),
             image_url = nullif(btrim(coalesce(v_elem->>'image_url','')),''),
             type_id = v_type_id
       where id = v_var_id and org_id = v_org;
      if not found then
        raise exception 'One of the options on "%" no longer exists. Reload the page and try again.',
          btrim(p_family->>'name') using errcode = 'P0002';
      end if;
    end if;

    -- ── Price ALWAYS goes through history. Never an in-place overwrite. ─────
    v_opened := false;
    if v_price is not null then
      select price, effective_from into v_cur_price, v_cur_from
        from public.wh_price_history
       where variation_id = v_var_id and effective_to is null;

      if v_cur_price is null then
        insert into public.wh_price_history
          (org_id, variation_id, price, price_unit, effective_from, changed_by, note)
        values (v_org, v_var_id, v_price, v_unit, now(), auth.uid(),
                coalesce(nullif(v_elem->>'price_note',''), 'First price set in the catalog editor'));
        v_opened := true;

      elsif v_cur_price is distinct from v_price then
        -- effective_to must be strictly > effective_from. now() is frozen for the
        -- whole transaction, so a period opened in THIS transaction would close at
        -- its own start instant and trip the sanity check. Nudge forward 1us.
        v_close_at := greatest(now(), v_cur_from + interval '1 microsecond');

        update public.wh_price_history
           set effective_to = v_close_at
         where variation_id = v_var_id and effective_to is null;

        -- New period starts exactly where the old one ended: no gap, no overlap
        -- ([a,c) then [c,d) do not intersect under tstzrange).
        insert into public.wh_price_history
          (org_id, variation_id, price, price_unit, effective_from, changed_by, note)
        values (v_org, v_var_id, v_price, v_unit, v_close_at, auth.uid(),
                coalesce(nullif(v_elem->>'price_note',''),
                         format('Price changed from %s to %s in the catalog editor', v_cur_price, v_price)));
        v_opened := true;
      end if;
    end if;

    -- ── Colours: BOTH models ───────────────────────────────────────────────
    delete from public.wh_variation_colors
     where variation_id = v_var_id and color_id <> all(v_colors);
    insert into public.wh_variation_colors (org_id, variation_id, color_id)
    select v_org, v_var_id, c from unnest(v_colors) c
    on conflict (variation_id, color_id) do nothing;

    delete from public.wh_product_colors
     where product_id = v_prod_id and color_id <> all(v_colors);
    insert into public.wh_product_colors (product_id, color_id)
    select v_prod_id, c from unnest(v_colors) c
    on conflict (product_id, color_id) do nothing;

    -- ── Category membership (storefront reads this) ────────────────────────
    delete from public.wh_category_products
     where product_id = v_prod_id and category_id <> all(v_cats);
    insert into public.wh_category_products (category_id, product_id)
    select c, v_prod_id from unnest(v_cats) c
    on conflict (category_id, product_id) do nothing;

    v_results := v_results || jsonb_build_object(
      'variation_id', v_var_id, 'product_id', v_prod_id, 'option_name', v_name,
      'storefront_name', v_prod_name, 'price_period_opened', v_opened);
  end loop;

  return jsonb_build_object(
    'family_id', v_family_id, 'created', v_new_fam,
    'option_count', jsonb_array_length(p_variations), 'options', v_results);
end
$fn$;

revoke all on function public.wh_save_catalog_family(jsonb, jsonb) from public, anon;
grant execute on function public.wh_save_catalog_family(jsonb, jsonb) to authenticated;
