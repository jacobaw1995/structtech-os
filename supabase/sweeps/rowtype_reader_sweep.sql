-- =============================================================================
-- ROW-TYPE READER SWEEP — "a reader that breaks the next time its table gains a column".
-- Track S · first run 2026-09-13. READ-ONLY (sections 0-2). Safe against production.
--
-- WHY THIS EXISTS. On 2026-09-12 migration collapsed_state added three columns to
-- `products`. The migration SUCCEEDED. `list_products` and `fetch_product` — declared
-- RETURNS SETOF products but projecting a NAMED column list, to mask money — then failed
-- 42804 at CALL time for ~6 minutes (21:29-21:35 EDT). Nothing binds a function's
-- projection to its table's row type until the function runs.
--
-- THE STANDING RULE:
--   A FUNCTION THAT RETURNS A TABLE'S ROW TYPE BUT SELECTS A NAMED COLUMN LIST IS A
--   READER THAT BREAKS THE NEXT TIME THAT TABLE GAINS A COLUMN.
-- AND ITS INVERSE, proved 2026-09-13 (section 3): a function declaring RETURNS TABLE(...)
-- or OUT parameters whose result is fed by `select *` from a table breaks the same way.
--
-- THE POPULATION IS DERIVED FROM THE CATALOG, NOT THE REPO. The repo is not the database.
--
-- GRADES
--   BREAKS    a result-feeding select list is a NAMED column list (row-type form), or is
--             star-shaped (RETURNS TABLE / OUT form)
--   SAFE      every result-feeding select is `*`, `alias.*` or `(record).*` (row-type form);
--             or a %rowtype variable filled by a star select and emitted by RETURN NEXT;
--             or a named list against a declared RETURNS TABLE (a table column add cannot
--             change a list you wrote out)
--   UNGRADED  no result-feeding select found (dynamic SQL, RETURN NEXT of computed values,
--             anything the patterns below do not recognise). NEVER round this into SAFE.
--
-- THE REGEX GRADE IS A PREDICTION. Section 3 is the CALIBRATION that proves it can fail:
-- add a column in a ROLLED-BACK transaction and CALL every function AS A MEMBER, so the
-- result-feeding statement actually executes. Re-run section 3 whenever the population
-- changes shape. A zero BREAKS with no calibration is not evidence the class is empty.
--
-- FIRST RUN, 2026-09-13
--   Denominator: 50 owned tables (public base tables minus wh_*, tg_agenda_*,
--   migration_bmr_*; 85 base tables in public in all) · 354 functions in public
--   (188 C-language extension functions, 127 plpgsql, 39 sql; 340 not wh_*) ·
--   13 return an owned table's row type (all SETOF; 0 non-setof; 0 return a view row type).
--   Adjacent forms, graded separately: 6 RETURNS TABLE (1 of them wh_*, Material Matrix's),
--   1 standalone composite (membership_context), 0 RETURNS SETOF record.
--   Grades (row-type form): BREAKS 2 — list_products, fetch_product (both `products`).
--                           SAFE 11. UNGRADED 0.
--   Calibration: all 13 matched their regex grade. Known BREAKS reproduced in BOTH
--   languages and at ZERO rows (list_products on an org with no products; synthetic
--   named-list sql -> 42P13; synthetic named-list plpgsql -> 42804; synthetic RETURNS
--   TABLE fed by * -> 42804). Every SAFE function ran after the column add.
--   Adjacent (section 2): 6 RETURNS TABLE. The instrument grades 4 SAFE (named lists;
--   job_master_sign_off and fetch_roadmap_by_token calibrated) and 2 UNGRADED —
--   derive_catalog_price (assigns OUT variables, no result select) and
--   role_capability_matrix (result select sits behind a WITH). Both were then READ BY HAND:
--   neither feeds a table's columns into its result, so neither is a table-add reader.
--   That is a human grade, recorded as one; the instrument's UNGRADED stands.
--   membership_context -> TYPE-COUPLED: not a table-add reader (it breaks if the TYPE
--   gains an attribute — a different trigger).
--   Callers of the two BREAKS (merged tree at main eacaf48):
--     list_products  src/app/w/[orgId]/estimating/catalog/page.tsx:90
--                    src/app/w/[orgId]/estimating/[estimateId]/page.tsx:68  (line-item picker)
--     fetch_product  no app call site (named only in src/lib/permissions/model.ts:306,
--                    a mirror string); no database function, view or policy calls either.
--   NOT FIXED — by ruling. The BREAKS stay BREAKS until a directive says otherwise.
--
-- YESTERDAY'S INSTRUMENT WAS WRONG, AND THIS IS WHY IT IS REPLACED RATHER THAN EXTENDED:
-- collapsed_state_sweep.sql §4 tested `return query select (?!\*)`, which graded
-- fetch_work_order_agreement (`select a.*`) as by-name — a FALSE POSITIVE — and could not
-- see SQL-language bodies or RETURN NEXT at all. It never discriminated.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 0 · DENOMINATOR — state it FIRST, with what it was counted in.
-- -----------------------------------------------------------------------------
with owned as (
  select c.reltype from pg_class c join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and c.relkind in ('r','p')
    and c.relname !~ '^(wh_|tg_agenda_|migration_bmr_)'
), fns as (
  select p.*, l.lanname from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace join pg_language l on l.oid = p.prolang
  where n.nspname = 'public'
)
select
  (select count(*) from owned)                                              as owned_tables,
  (select count(*) from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relkind in ('r','p'))                  as base_tables_in_public,
  (select count(*) from fns)                                                as functions_in_public,
  (select count(*) from fns where proname !~ '^wh_')                        as functions_not_wh,
  (select count(*) from fns f join owned o on o.reltype = f.prorettype)     as population_rowtype_readers,
  (select count(*) from fns f join pg_class c on c.reltype = f.prorettype
    where c.relkind in ('v','m'))                                           as return_view_rowtype,
  (select count(*) from fns where coalesce(proargmodes::text[] && array['t','o','b'], false))
                                                                            as adjacent_returns_table_or_out,
  (select count(*) from fns f join pg_type t on t.oid = f.prorettype
    where t.typtype = 'c' and not exists (select 1 from pg_class c where c.reltype = f.prorettype
                                          and c.relkind in ('r','p','v','m')))
    -- NB a standalone composite type HAS a pg_class row (relkind 'c'); excluding every
    -- pg_class match counted membership_context as 0 on the first draft of this query.
                                                                            as adjacent_standalone_composite,
  (select count(*) from fns where prorettype = 'record'::regtype
    and not coalesce(proargmodes::text[] && array['t','o','b'], false))     as adjacent_setof_record;

-- -----------------------------------------------------------------------------
-- 1 · THE POPULATION, GRADED — functions returning an owned TABLE's row type.
--     Result-feeding selects: sql = every statement-initial SELECT;
--     plpgsql = RETURN QUERY SELECT … and FOR <var> IN SELECT … (the RETURN NEXT path).
-- -----------------------------------------------------------------------------
with owned as (
  select c.relname, c.reltype from pg_class c join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and c.relkind in ('r','p')
    and c.relname !~ '^(wh_|tg_agenda_|migration_bmr_)'
), pop as (
  select p.oid, p.proname, l.lanname, o.relname as table_name,
         regexp_replace(p.prosrc, '--[^\n]*', '', 'g') as src
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  join pg_language l on l.oid = p.prolang
  join owned o on o.reltype = p.prorettype
  where n.nspname = 'public'
), lists as (
  select pop.oid, m[1] as sel_list
  from pop, lateral regexp_matches(pop.src,
     case when pop.lanname = 'sql' then '^\s*select\s+(.*?)\s+from\s'
          else '(?:return\s+query|for\s+\w+\s+in)\s+select\s+(.*?)\s+from\s' end, 'gi') as m
), graded as (
  select oid, sel_list,
         btrim(sel_list) ~* '^(\*|[a-z_][a-z0-9_]*\.\*|\(.*\)\.\*)$' as star
  from lists
)
select pop.proname, pop.table_name, pop.lanname,
       count(g.sel_list) as result_selects,
       case
         when count(g.sel_list) = 0 then 'UNGRADED'
         when bool_or(not g.star) then 'BREAKS'
         when pop.lanname = 'sql' or pop.src ~* 'return\s+query' then 'SAFE'
         when pop.src ~* 'return\s+next\s+\w+'
              and pop.src ~* ('\m\w+\s+(public\.)?' || pop.table_name || '(%rowtype)?\s*;') then 'SAFE'
         else 'UNGRADED'
       end as grade,
       string_agg(left(regexp_replace(g.sel_list, '\s+', ' ', 'g'), 80), ' | ') as select_lists
from pop left join graded g on g.oid = pop.oid
group by pop.oid, pop.proname, pop.table_name, pop.lanname, pop.src
order by grade, pop.table_name, pop.proname;

-- -----------------------------------------------------------------------------
-- 2 · ADJACENT FORM — RETURNS TABLE / OUT parameters. The rule inverts:
--     a NAMED list is SAFE against a table column add; a STAR-fed result BREAKS.
--     Standalone composite types are listed so nobody mistakes them for covered:
--     they break when the TYPE changes, not the table.
-- -----------------------------------------------------------------------------
with fns as (
  select p.oid, p.proname, l.lanname, pg_get_function_result(p.oid) as result_decl,
         regexp_replace(p.prosrc, '--[^\n]*', '', 'g') as src,
         coalesce(p.proargmodes::text[] && array['t','o','b'], false) as table_or_out,
         t.typtype, t.typrelid
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  join pg_language l on l.oid = p.prolang
  join pg_type t on t.oid = p.prorettype
  where n.nspname = 'public'
)
select proname, lanname, result_decl,
       case
         when table_or_out and src ~* '(return\s+query\s+|^\s*)select\s+(\*|[a-z_][a-z0-9_]*\.\*)\s+from\s'
           then 'BREAKS — RETURNS TABLE/OUT fed by *'
         when table_or_out and src ~* '(return\s+query\s+|^\s*)select\s' then 'SAFE — named list against declared columns'
         when table_or_out then 'UNGRADED — no result select recognised (read it)'
         else 'TYPE-COUPLED — breaks if the composite TYPE gains an attribute; not a table-add reader'
       end as grade
from fns
where table_or_out or (typtype = 'c' and typrelid <> 0
                       and not exists (select 1 from pg_class c where c.oid = typrelid and c.relkind in ('r','p','v','m')))
order by grade, proname;

-- -----------------------------------------------------------------------------
-- 3 · CALIBRATION — PROVE THE GRADE CAN FAIL. ROLLED BACK BY CONSTRUCTION.
--     The block ENDS IN RAISE EXCEPTION, so every ALTER and fixture is discarded.
--     It takes ACCESS EXCLUSIVE locks on the altered tables for its duration:
--     lock_timeout bounds the wait; keep it short and run it off-peak.
--     Run as postgres; it switches to `authenticated` with a real member's JWT so each
--     function's guards PASS and the result-feeding statement EXECUTES — a function that
--     returns before its RETURN QUERY proves nothing (the empty instrument that hid in
--     20260913013524's own comment).
--     EDIT BEFORE RE-RUNNING: the member uuid, the ids in `calls`, and the table list must
--     be live values; a call that returns early grades nothing.
-- -----------------------------------------------------------------------------
/*
do $cal$
declare
  r jsonb := '{}'::jsonb; v_pass text; n int; c text; t text; v_cols text;
  v_member text := '09a25143-e069-401b-a49d-a6879fe43d7c';   -- member of every tenant whose rows are named below
  calls text[] := array[
    'select count(*) from public.list_products(''9d32b5a9-e11e-401b-8fa7-969065b004ce'', true)',   -- known BREAKS
    'select count(*) from public.fetch_purchase_order(''1256ba02-18ae-42e9-beaf-46dd85a382a6'')',  -- a SAFE
    'select count(*) from public.zz_probe_named_plpgsql()'                                         -- synthetic BREAKS
    -- … one line per population member, each with an id that passes its guards
  ];
begin
  set local lock_timeout = '3s';
  select string_agg('p.' || quote_ident(attname), ', ' order by attnum) into v_cols
    from pg_attribute where attrelid = 'public.tracker_projects'::regclass and attnum > 0 and not attisdropped;
  execute format('create function public.zz_probe_named_plpgsql() returns setof public.tracker_projects
                  language plpgsql stable as %L',
                 'begin return query select ' || v_cols || ' from public.tracker_projects p where false; end');
  execute 'revoke all on function public.zz_probe_named_plpgsql() from public, anon';
  execute 'grant execute on function public.zz_probe_named_plpgsql() to authenticated';

  foreach v_pass in array array['1_before_add_column', '2_after_add_column'] loop
    if v_pass = '2_after_add_column' then
      perform set_config('role', 'postgres', true);
      foreach t in array array['products', 'purchase_orders', 'tracker_projects'] loop   -- every table in the population
        execute format('alter table public.%I add column zz_rowtype_probe integer', t);
      end loop;
    end if;
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', v_member), true);
    foreach c in array calls loop
      begin
        execute c into n;
        r := r || jsonb_build_object(v_pass || ' ' || substring(c from 'public\.(\w+)'), 'ok rows=' || n);
      exception when others then
        r := r || jsonb_build_object(v_pass || ' ' || substring(c from 'public\.(\w+)'), sqlstate || ' ' || left(sqlerrm, 80));
      end;
    end loop;
  end loop;
  raise exception 'CALIBRATION %', r::text;   -- rolls everything back
end $cal$;
*/
-- EXPECTED: pass 1 all ok (the fixtures work); pass 2 every BREAKS -> 42804 (plpgsql) or
-- 42P13 (sql), every SAFE -> ok. A BREAKS that stays ok in pass 2 means the call never
-- reached its result statement: UNGRADED, not SAFE.
