-- StructTech OS — update_intake_checklist_field null-safety fix
--
-- Found live while browser-verifying the fix pass above: submitting an
-- incomplete/empty value from a checklist row's <input type="datetime-local">
-- (or any input the browser reports back as "") reaches this RPC as SQL
-- NULL for p_value. jsonb_set() is strict — ANY NULL argument makes the
-- whole call return NULL — so `jsonb_set(v_intake, path, NULL, true)` set
-- v_intake itself to NULL, and the subsequent `update deals set
-- intake_checklist = NULL` hit the column's NOT NULL constraint and
-- surfaced a raw Postgres error in the UI banner instead of just clearing
-- that one field. Confirmed no data corruption occurred (the constraint
-- violation rolled back the whole statement), but the UX was broken.
--
-- Fix: coalesce a NULL p_value to the JSON null literal before calling
-- jsonb_set, so clearing a field writes {"key": null} for that one key
-- instead of nulling the entire intake_checklist column. Same signature —
-- CREATE OR REPLACE, no DROP needed.

create or replace function public.update_intake_checklist_field(p_deal_id uuid, p_field_path text[], p_value jsonb)
returns void
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_org_id uuid;
  v_intake jsonb;
  v_value jsonb;
begin
  if array_length(p_field_path, 1) is null or array_length(p_field_path, 1) not between 1 and 2 then
    raise exception 'p_field_path must have 1 or 2 elements, got %', p_field_path;
  end if;

  select org_id, coalesce(intake_checklist, '{}'::jsonb)
  into v_org_id, v_intake
  from public.deals where id = p_deal_id;

  if v_org_id is null or v_org_id not in (select my_org_ids()) then
    raise exception 'deal not found or not accessible: %', p_deal_id;
  end if;

  -- jsonb_set is strict (NULL in -> NULL out); coalesce so a cleared/empty
  -- field writes JSON null for that one key, not NULL for the whole column.
  v_value := coalesce(p_value, 'null'::jsonb);

  if array_length(p_field_path, 1) = 2 then
    v_intake := jsonb_set(
      v_intake,
      p_field_path[1:1],
      coalesce(v_intake -> p_field_path[1], '{}'::jsonb),
      true
    );
  end if;

  v_intake := jsonb_set(v_intake, p_field_path, v_value, true);

  update public.deals
  set intake_checklist = v_intake,
      updated_at = now()
  where id = p_deal_id;
end;
$function$;
