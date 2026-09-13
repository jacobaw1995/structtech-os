-- =============================================================================
-- COLLAPSED-STATE SWEEP — a principle turned into a query.
-- Track S · first run 2026-09-12. READ-ONLY. Safe to run against production.
--
-- WHY THIS EXISTS: "a principle you cannot turn into a sweep is a principle you
-- will only apply where you happen to look." Material Matrix held one correctly
-- for two hours on a single column, then ran it as a query and found two more in
-- minutes — one of which would have published ~128 half-built products to a live
-- storefront. This file is the query. It is written to run against the SHARED
-- table space, so Material Matrix can run it against their own tables by changing
-- the OWNED filter below.
--
-- THE INSTRUMENT DOES NOT GRADE. IT NARROWS. Every section returns CANDIDATES
-- with the evidence a human needs, and a candidate becomes a finding only when a
-- BEHAVIOURAL probe proves it. The regex counts over-match common names like
-- `status` and `role`; they rank, they do not decide.
--
-- THREE AXES
--   AXIS 1  Can this value mean two things?
--           (a default that a writer can also write deliberately; a stored value
--            that could have been an input OR a derived output)
--   AXIS 2  Does this column's default act OUTSIDE its own row?
--           publish · expose · notify · unblock · grant · charge
--   AXIS 3  A guard proved at the FUNCTION is not proved reachable from the TABLE.
--           Grade each unreachable guard as ONE of:
--             SAFE       a CONSTRAINT prevents the value (defence in depth)
--             DANGEROUS  a DEFAULT substitutes one (a silent answer)
--           "It refuses correctly" is not an accepted answer.
--
-- CHANGE THIS TO RUN IT ON ANOTHER PROJECT'S TABLES:
--   StructTech excludes wh_* (Material Matrix), tg_agenda_*, migration_bmr_*
--   Material Matrix would INCLUDE only wh_*.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 0 · THE DENOMINATOR. Report this with every finding: a finding without its
--     denominator is a sighting, not a sweep.
-- -----------------------------------------------------------------------------
with owned as (
  select c.table_name, c.column_name, c.column_default
  from information_schema.columns c
  join information_schema.tables t
    on t.table_schema = c.table_schema and t.table_name = c.table_name and t.table_type = 'BASE TABLE'
  where c.table_schema = 'public'
    and c.table_name !~ '^wh_' and c.table_name !~ '^tg_agenda_' and c.table_name !~ '^migration_bmr_'
)
select count(distinct table_name) as tables,
       count(*)                                                   as columns,
       count(*) filter (where column_default is not null)         as columns_with_default,
       count(*) filter (where column_default is not null
         and column_default !~* '^(gen_random_uuid|now|uuid_generate|nextval|CURRENT_(DATE|TIMESTAMP))')
                                                                  as non_boilerplate_defaults
from owned;

-- -----------------------------------------------------------------------------
-- 1+2 · EVERY NON-BOILERPLATE COLUMN DEFAULT, with who writes and who reads it.
--     A default with WRITERS is an axis-1 candidate (the default value is
--     indistinguishable from a deliberate write of the same value).
--     A default with READERS in a predicate is an axis-2 candidate (the default
--     decides something). Rank by readers; then PROBE the top of the list.
-- -----------------------------------------------------------------------------
with owned as (
  select c.table_name, c.column_name, c.data_type, c.is_nullable, c.column_default
  from information_schema.columns c
  join information_schema.tables t
    on t.table_schema = c.table_schema and t.table_name = c.table_name and t.table_type = 'BASE TABLE'
  where c.table_schema = 'public'
    and c.table_name !~ '^wh_' and c.table_name !~ '^tg_agenda_' and c.table_name !~ '^migration_bmr_'
    and c.column_default is not null
    and c.column_default !~* '^(gen_random_uuid|now|uuid_generate|nextval|CURRENT_(DATE|TIMESTAMP))'
),
fn  as (select p.proname, p.prosrc from pg_proc p join pg_namespace n on n.oid = p.pronamespace
        where n.nspname = 'public' and p.prosrc is not null and p.proname !~ '^wh_'),
pol as (select pol.polname,
               coalesce(pg_get_expr(pol.polqual, pol.polrelid), '') || ' ' ||
               coalesce(pg_get_expr(pol.polwithcheck, pol.polrelid), '') as expr
        from pg_policy pol)
select o.table_name || '.' || o.column_name as col,
       o.data_type, left(o.column_default, 40) as default_value,
       (select count(*) from fn  where fn.prosrc ~* ('\m' || o.column_name || '\M')
                                   and fn.prosrc ~* ('\m' || o.table_name  || '\M')) as function_mentions,
       (select count(*) from pol where pol.expr  ~* ('\m' || o.column_name || '\M'))   as policy_mentions,
       case
         when o.data_type = 'boolean' then 'AXIS 2 — a boolean default publishes, exposes or unblocks; probe what reads it'
         when o.data_type = 'jsonb'   then 'AXIS 1 — does {} / [] mean "unset" AND "deliberately empty"?'
         when o.column_name ~ '(price|cost|quantity|hours|amount)' then 'AXIS 1+2 — does 0/1 mean "chosen" AND "nobody set it"? it may CHARGE'
         when o.column_name ~ '(role|permission)'                  then 'AXIS 2 — a default role GRANTS; find a writer that omits it'
         when o.column_name ~ '(source|mode|kind)'                 then 'AXIS 1 — attribution: does the default claim an origin it did not have?'
         else 'rank by readers'
       end as what_to_ask
from owned o
order by policy_mentions desc, function_mentions desc, col;

-- -----------------------------------------------------------------------------
-- 3a · AXIS 3 — RPC PARAMETER DEFAULTS THAT SUBSTITUTE A VALUE.
--     A parameter whose DEFAULT is a real value (not NULL) answers for a caller
--     who omitted it. If the body ALSO refuses on that parameter being null or
--     non-positive, the refusal is UNREACHABLE BY OMISSION — the DANGEROUS kind.
--     First run: add_purchase_order_line(p_quantity_ordered DEFAULT 1) with a
--     `is null or <= 0` guard. Omitted -> ordered 1. Explicit null -> refused.
-- -----------------------------------------------------------------------------
select p.proname, m[1] as param, m[3] as default_value,
       (p.prosrc ~* ('\m' || m[1] || '\M\s+is\s+null'))  as guards_null,
       (p.prosrc ~* ('\m' || m[1] || '\M\s*<=?\s*0'))    as guards_nonpositive,
       coalesce(array_to_string(p.proacl, ' '), 'NULL=PUBLIC') ~ 'authenticated=X' as app_callable,
       case when (p.prosrc ~* ('\m' || m[1] || '\M\s+is\s+null') or p.prosrc ~* ('\m' || m[1] || '\M\s*<=?\s*0'))
            then '*** UNREACHABLE GUARD — the default substitutes; probe by OMITTING the argument ***'
            else 'no guard; still a silent answer for an omitted argument' end as grade_hint
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace,
     lateral regexp_matches(pg_get_function_arguments(p.oid),
                            '(p_[a-z_]+) ([a-z ]+?) DEFAULT ((?!NULL)[^,]+)', 'g') as m
where n.nspname = 'public' and p.proname !~ '^wh_'
order by (p.prosrc ~* ('\m' || m[1] || '\M\s+is\s+null') or p.prosrc ~* ('\m' || m[1] || '\M\s*<=?\s*0')) desc,
         p.proname;

-- -----------------------------------------------------------------------------
-- 3b · AXIS 3 — A GUARD THAT LIVES ONLY IN AN RPC, ON A TABLE RLS LETS YOU WRITE
--     DIRECTLY. If a table has an INSERT or UPDATE policy for `authenticated`,
--     every rule enforced only inside the RPC is bypassable by writing the table.
--     A column DEFAULT then supplies the answer the RPC would have computed.
--     First run: schedule_blocks — the RPC computes ready_by_conflict and refuses
--     under enforce_stage_gating; a direct INSERT took ready_by_conflict DEFAULT
--     false and SAVED past an opted-in block.
--     This section lists the tables to probe; the probe is a direct write.
-- -----------------------------------------------------------------------------
select c.relname as table_name,
       string_agg(distinct case pol.polcmd when 'a' then 'INSERT' when 'w' then 'UPDATE' when '*' then 'ALL' end, ', ') as direct_write_commands,
       (select string_agg(col.column_name || ' DEFAULT ' || left(col.column_default, 20), ' · ')
          from information_schema.columns col
         where col.table_schema = 'public' and col.table_name = c.relname and col.column_default is not null
           and col.column_default !~* '^(gen_random_uuid|now|uuid_generate|nextval|CURRENT_(DATE|TIMESTAMP))')
         as defaults_a_direct_write_would_take,
       'PROBE: write this table directly as a member who holds the gating capability, in the state the RPC refuses' as probe
from pg_policy pol
join pg_class c on c.oid = pol.polrelid
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public' and pol.polcmd in ('a', 'w', '*')
  and c.relname !~ '^wh_' and c.relname !~ '^tg_agenda_' and c.relname !~ '^migration_bmr_'
  and exists (select 1 from pg_roles r where r.oid = any(pol.polroles) and r.rolname = 'authenticated')
group by c.relname
order by c.relname;

-- -----------------------------------------------------------------------------
-- 4 · WHAT THE FIX ITSELF CAN BREAK — run BEFORE applying a change this sweep
--     motivated. Added 2026-09-12 after the first fix broke three things that
--     every structural check passed.
--
--   4a  ADDING A COLUMN breaks every function that RETURNS SETOF <table> and
--       projects columns BY NAME (typically to mask money). Nothing binds the
--       projection to the row type until the function is CALLED — rule 15, but
--       for ADD COLUMN, not only rename/retype. First run: list_products and
--       fetch_product failed 42804 (12 columns vs 15) the moment
--       collapsed_state added three pricing columns.
--   4b  KEY PRESENCE IS NOT INTENT. Before reading "the patch has key X" as "the
--       user chose X", read the FORM that builds the patch. First run: the catalog
--       edit form always sends sell, blank as null; the material row always
--       resends its prefilled ready_by. Both turned a no-op resubmission into a
--       deliberate-looking write — the axis-1 collapse, reintroduced by the fix.
--       This is not queryable from the catalog: grep src for every caller of the RPC.
-- -----------------------------------------------------------------------------
select p.proname,
       pg_get_function_identity_arguments(p.oid) as args,
       t.typname as returns_setof_table,
       (p.prosrc ~* 'return\s+query\s+select\s+(?!\*)') as projects_by_name,
       'CALL THIS AS A MEMBER after adding a column to ' || t.typname
         || ' — as postgres it may return before the RETURN QUERY and prove nothing' as action
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
join pg_type t on t.oid = p.prorettype
join pg_class c on c.oid = t.typrelid and c.relkind = 'r'
where n.nspname = 'public' and p.proretset and p.proname !~ '^wh_'
order by projects_by_name desc, t.typname, p.proname;
