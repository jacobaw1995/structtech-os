# KNOWN DIVERGENCE — the accepted state of the migration ledger as of A1.0

**THIS IS THE KNOWN, ACCEPTED DIVERGENCE AS OF A1.0.** `supabase migration list` will
report every entry below, permanently, and **that report is TRUE** — these migrations
really were applied without a repo file, and these files really were applied without a
ledger row. Nothing here is a defect to be chased. **A future *real* divergence is
anything in that command's output that is NOT in this file.** Check by diffing the
command's output against this list. **Never by reading the raw output** — it is 108
entries long and a genuinely new row would disappear into it.

**This file lives at `supabase/_KNOWN_DIVERGENCE.md`, deliberately one level ABOVE
`supabase/migrations/`.** It used to sit inside that directory, where the CLI printed
`Skipping migration _KNOWN_DIVERGENCE.md...` on every invocation — a file whose job is
keeping that output clean should not be the thing dirtying it.

## `migration repair` was NOT used on any of these. Here is why.

Both of its modes were measured against a local PostgreSQL 17.11 restore of the ledger
on 2026-08-23 (CLI 2.115.0, via `--db-url`; production never touched):

- **`--status applied` REFUSES any version without a matching repo file** —
  `LegacyMigrationFileNotFoundError`. That is exactly what an orphan is, so this mode is
  unavailable for all 69 below.
- **`--status reverted` DELETES the row.** It does not mark it reverted; there is no
  status column. After running it, `supabase migration list` would report that these 69
  migrations **were never applied.**

That second point is the whole decision. Erasing the rows would not tidy a noisy
diagnostic — **it would make the tool lie**, replacing a true report with a false one,
and it would destroy the only surviving copy of 204,782 characters of source
(`supabase_migrations.schema_migrations.statements`; see
`../backups/a1_0_pre_baseline_20260823/`). **A noisy-but-true diagnostic beats a
clean-but-false one.**

Writing files for all 69 instead would be a *backfill* — a reversal of A1.0's standing
decision to take a baseline reset. That it became cheaper once the source was recovered
is a reason to re-examine the decision deliberately, not to reverse it inside a hygiene
task.

## THE ASSERTION — what `supabase migration list` reports, and what to compare it to

Run it without a linked project:

```bash
supabase migration list --db-url "$SUPABASE_DB_URL" --output-format json
```

**POST-A1.0 EXPECTED OUTPUT — pin these numbers. Measured 2026-08-23 immediately after the archive:**

| | count |
|---|---|
| total entries | **108** |
| MATCHED (local **and** remote) | **0** |
| DB-ONLY (remote, no local file) | **107** |
| REPO-ONLY (local file, no ledger row) | **1** — `20260823143943_baseline.sql` |

**Anything outside those three numbers is a REAL divergence and must be investigated.**

**Why MATCHED is 0 and not 8.** Before A1.0 the command reported **8 matched / 99 DB-only /
44 repo-only**, because 44 historical files still sat in `supabase/migrations/`. A1.0 moved
all 52 of them to `_archive_pre_baseline/`, which the CLI does not scan. So every ledger row
is now DB-only. **That is the intended end state, not a regression** — the baseline replaces
those files, and their content is preserved in the archive folder and in
`../backups/a1_0_pre_baseline_20260823/ledger_statements/`.

**Why the baseline itself is REPO-ONLY, permanently.** `20260823143943_baseline.sql` has no
ledger row because **A1.0 deliberately wrote nothing to `supabase_migrations`.** It was taken
with `pg_dump`, which cannot write to that table; `supabase db pull`, which can, was not used.
**Expect this row forever. It is not an error, and it must not be "fixed" with
`migration repair`** — doing so would overwrite the ledger from a file (measured behaviour,
directive §4.7.4).

## RECONCILING THE TWO NUMBER SETS — read this before concluding anything mismatches

**This file carries two different counts of the same divergence, and they disagree by design.**

- **The TOOL's numbers (108 / 0 / 107 / 1 above) pair strictly by VERSION STRING.** That is
  all `supabase migration list` can do: it globs filenames, reads `schema_migrations.version`,
  and matches them literally.
- **This file's inventory below (69 orphans + 14 unlogged files) pairs by NAME and, where the
  two disagreed, by CONTENT.** It is the *explanation* of the divergence, not the assertion
  against it.

They differ because a migration whose repo file carries a synthetic timestamp
(`…120000`) while the ledger recorded a real applied time is **one migration with two
version strings**. The tool counts it twice — once as DB-only, once as repo-only. This file
counts it once, as recoverable.

**One entry was corrected by content rather than name.** Two ledger rows share the name
`drop_update_deal_details`. The archived file matches `20260721153326
drop_update_deal_details_fixed` exactly, so `_fixed` is covered and **`20260721153207` is the
orphan** — the reverse of a name-only pairing. See the note at the end of section A.

**Practical rule: assert against the tool's numbers; use the inventory to understand what
they mean.** Anyone diffing 107 against 69 without this section will read a mismatch that
is not one.

## A · Ledger rows with no repo file — 69

Applied to production, recorded in `supabase_migrations.schema_migrations`, no file in
`supabase/migrations/`. Their full source is preserved in
`../backups/a1_0_pre_baseline_20260823/ledger_statements/`.


### A1 · OURS — 22

StructTech OS migrations. Eighteen predate this repository entirely (2026-03-31 → 2026-07-07).

| version | name |
|---|---|
| `20260331123234` | drop_obsolete_prospects_column |
| `20260627170152` | create_audit_leads_table |
| `20260702012359` | create_client_roadmaps |
| `20260702012434` | allow_anon_insert_roadmaps |
| `20260702014701` | auto_roadmap_from_scan |
| `20260702020842` | roadmap_rpc_and_lead_link |
| `20260703204620` | crm_v1_deals_pipeline |
| `20260703221155` | client_portal_v1 |
| `20260706231127` | engagement_schedule_v1 |
| `20260706232704` | engagement_schedule_rpc_and_triggers |
| `20260706232725` | fix_create_engagement_from_roadmap_idempotency_check |
| `20260707011556` | enable_rls_structtech_state |
| `20260707011611` | staff_auth_infrastructure |
| `20260707012035` | fix_staff_users_recursive_rls |
| `20260707012143` | staff_scoped_access_policies |
| `20260707013828` | drop_anon_admin_access |
| `20260707014514` | staff_management_settings |
| `20260707021116` | pipeline_schema_v1 |
| `20260721153207` | drop_update_deal_details |
| `20260721203903` | fix_present_estimate_presented_total_includes_tax |
| `20260730010405` | work_order_agreements_chunk1_data_model |
| `20260816161039` | archive_wh_color_normalization_backups |

### A2 · MATERIAL MATRIX — 34

Applied by the Material Matrix build on the shared backend (D6/D7). `wh_*` plus five `cp3_*` checkpoint backups attributed by content, not prefix.

| version | name |
|---|---|
| `20260801175433` | wh_supplier_catalog_landing_zone |
| `20260804195617` | wh_orders_schema |
| `20260804195721` | wh_orders_rls_and_rpcs |
| `20260804195923` | wh_catalog_public_read |
| `20260804200930` | wh_storage_buckets_pdf_spec |
| `20260804200933` | wh_orders_anon_grant_hardening |
| `20260805200915` | wh_orders_webhook_error |
| `20260805212744` | wh_retire_length_tables |
| `20260805215137` | wh_product_photos_bucket |
| `20260805215854` | wh_catalog_id_defaults |
| `20260805222115` | wh_category_products_seed |
| `20260806215433` | wh_orders_payment |
| `20260812123012` | wh_team_members_roles |
| `20260812124921` | wh_role_owner_bootstrap |
| `20260814205122` | wh_colors_normalization |
| `20260815020245` | wh_order_number_sequence_authoritative |
| `20260817145037` | cp3_step0_backups_20260817 |
| `20260817145525` | wh_product_families_variations |
| `20260817150037` | wh_product_photos_bucket_role_gating |
| `20260817150240` | wh_product_photos_preserve_spec_upload |
| `20260818231723` | cp3_tuesday_step0_backups_20260818 |
| `20260818231832` | wh_price_history |
| `20260818232038` | wh_product_types |
| `20260818232146` | wh_product_roles |
| `20260818232222` | wh_variation_colors |
| `20260819232606` | cp3_wednesday_step0_backups_20260819 |
| `20260819232811` | wh_catalog_editor_dual_write_rpc |
| `20260820134145` | cp3_thursday_backup_categories_20260820 |
| `20260820134214` | wh_categories_image_url_backfill |
| `20260820134701` | cp3_thursday_backup_systems_20260820 |
| `20260820134724` | wh_systems_hero_image_rehost |
| `20260820142421` | wh_systems_stages_anon_read_p0_fix |
| `20260821004838` | wh_category_products_colors_narrow_all_policies |
| `20260822215146` | wh_team_members_narrow_forall_and_scope_read |

### A3 · NEITHER — 13

No repo file and no owner this build can reach. All thirteen landed inside a 48-hour window, 2026-08-20 → 2026-08-21. **These are the rows to watch.**

| version | name |
|---|---|
| `20260820003958` | tg_agenda_bot_schema |
| `20260820004929` | tg_agenda_bot_assets_bucket |
| `20260820010229` | tmp_enable_http_for_verification |
| `20260820010953` | tg_agenda_cleanup_unused_assets |
| `20260820012550` | tg_agenda_per_user_sessions_and_group_optin |
| `20260820013518` | tmp_enable_http_verify_v3 |
| `20260820013529` | tmp_drop_http_after_verify |
| `20260820020138` | tmp_http_for_bot_diagnosis |
| `20260820021626` | bmr_field_ticket_schema |
| `20260820033312` | bmr_tickets_schema_standalone |
| `20260821140030` | bmr_tickets_standalone_jobs_and_scope |
| `20260821141857` | bmr_tickets_migrate_off_public_and_drop_legacy |
| `20260821180323` | drop_bmr_tickets_schema |

### Note on `drop_update_deal_details`

Two ledger rows share this name: `20260721153207 drop_update_deal_details` and
`20260721153326 drop_update_deal_details_fixed`. The repo file
`20260724130000_drop_update_deal_details.sql` matches the **`_fixed`** row's SQL exactly
(verified 2026-08-23), not the earlier one. So `_fixed` is covered and **`…153207` is the
orphan** — and losing it costs nothing: it is the failed first attempt that hand-typed 23
argument types instead of 24, so `drop function if exists` matched nothing and silently
no-op'd. It is CLAUDE.md migration rule 2's original evidence, preserved.

## B · Repo files with no ledger row — 14

**The divergence runs both ways.** These were applied to production — every object they
create was verified present in `pg_catalog` on 2026-08-23 — but
`supabase_migrations.schema_migrations` has no row for them, under their version or their
name. `migration repair --status applied` *can* record them (measured: it creates the row
and populates `statements` from the file), but doing so would write today's file content
in as history, which §7.1 Rule 1 forbids.

| version | name |
|---|---|
| `20260711120000` | foundation_multitenancy |
| `20260711120100` | backfill_org_id_crm |
| `20260712120000` | org_scoped_rls_crm |
| `20260712130000` | crm_stage_config_and_rpcs |
| `20260712140000` | estimating_schema_and_rpcs |
| `20260713120000` | coordination_schema_and_rpcs |
| `20260713150000` | field_schema_and_rpcs |
| `20260713180000` | management_controls_retrofit |
| `20260714120000` | crm_depth_stage1_contact_address |
| `20260714150000` | crm_depth_stage2_lead_data_model |
| `20260714180000` | crm_depth_stage3_command_center_engine |
| `20260715120000` | crm_depth_stage4_notes_author |
| `20260719120000` | stage5_track_b2_seed_isaac |
| `20260725150000` | fix_present_estimate_tax_snapshot |

## Scale

| | count |
|---|---|
| Ledger rows total | 107 |
| — matched to a repo file at the same version | 7 |
| — matched to a repo file by name at a different version | 30 |
| — **no repo file at all (section A)** | **69** |
| Repo migration files total (pre-A1.0) | 52 — all now in `migrations/_archive_pre_baseline/` |
| — **no ledger row at all (section B)** | **14** |

Section A was 70 until A1.0b filed
`20260801175520_organizations_add_supplier_tenant_type.sql`, which is the shape of how
this list should shrink: one deliberate, reviewed file at a time, never a bulk repair.

## Maintaining this file

- **Adding a row here is not routine.** A new entry means a migration reached production
  outside the repo, which D7 forbids. Record it *and* raise it.
- Remove an entry only when a real file is written at that row's **DB-recorded version**,
  with its body taken from `statements` (§7.1 Rule 1 — a reconciled file records what
  ran, not what the schema should say today).
- Regenerate the comparison from
  `../backups/a1_0_pre_baseline_20260823/ledger_statements_index.tsv` and
  `supabase/migrations/`.

*Generated 2026-08-23 (A1.0c). Authority: `docs/STRUCTTECH_OS_DIRECTIVE.md` §4.7, §4.7.1–§4.7.4, §7.1.*
