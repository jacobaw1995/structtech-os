# Synthetic field tenant: a disposable org and one crew login

**Created:** 2026-09-17 (America/New_York) by Track S, under the controller's ruling of that day.
**Why it exists:** there was no `field` member in any tenant. That stalled three pieces of work:
- Track U reported the field view as *derived, not measured*, twice.
- Track X could not run §4 checks 1–2 of `supabase/proposals/20260915_x_w1_15_org_files_policies.md`.

**It is not Brothers Metal Roofing and not any client.** The standing rule is unchanged: never write test data to a real BMR customer record.

## What exists (created 2026-09-17)

The seed is `supabase/seeds/20260917_synthetic_field_tenant.sql`. Every id is a literal.

| Object | id | Notes |
|---|---|---|
| Organization | `e0851ad8-35d6-4e17-b267-6cd35cb6f713` | Named "ZZ SYNTHETIC Field Test (not a client, disposable)", type `contractor`. Modules: estimating, coordination, field (config `{}`) |
| Deal | `a570f24c-63b7-4fb0-b0f1-97b80763c858` | "SYNTHETIC Test Homeowner". No real person, phone or email |
| Estimate | `29e62f5f-d0bc-4d6b-8328-5e52cff67008` | `SYN-1`, **presented** (not signed), total 1000, one line |
| Job | `821cea1c-14d2-4aec-a719-685f6696573a` | Address "1 Synthetic Way, Testville, ZZ 00000" |
| Master work order | `029e4346-d30a-4da8-ad1d-1eee27d094ff` | |
| Trade work order | `6af911f6-5c60-4041-9a4f-582f5f08434e` | Trade "SYNTHETIC Roofing" |
| Material item | `e315e4d1-c108-45b3-9cd5-ace0e3ce47c8` | On the trade |
| Schedule block | `a2a0cf7e-c0b1-4186-8975-1a180cb9d7fa` | On the trade, 2026-09-17 → 2026-09-19 |
| Owner | Jacob's existing account | Lets the office side (upload, schedule, assign) be driven through the product |

**Proved on 2026-09-17** (rolled back, a `field` member as the caller):
- The field member sees the trade work order and not the master.
- They see 0 estimates, 1 job, 1 material item and 1 schedule block.
- `fetch_field_jobs` returns the trade job.

## The crew login: instructions, not values

Track S does not create accounts or handle passwords. **The credential never passes through a transcript.** Jacob does two steps:

1. **Create the user.** In the Supabase dashboard for project `ejlhrykcdfcyeooooodx`, go to **Authentication → Users → Add user → Create new user**.
   - Use an email address you control, for example a `+crew` alias.
   - Generate the password in your password manager.
   - Tick **Auto Confirm User**.
2. **Attach it as crew.** Run this in the **SQL editor**, putting the email from step 1 in the `where` clause:

   ```sql
   insert into public.org_members (org_id, user_id, role, full_name, permissions)
   select 'e0851ad8-35d6-4e17-b267-6cd35cb6f713', u.id, 'field', 'SYNTHETIC Crew',
          public.default_permissions_for_role('field')
   from auth.users u
   where u.email = 'THE-EMAIL-YOU-CHOSE';
   ```

   The result must say **1 row**. If it says 0, the email didn't match.

   An email address is not a secret. If you'd rather, give Track S the email and it will run the statement. The password stays with you.

## What each track needs, and how it gets it

**Track U: the field view, measured instead of derived.**
- Sign in as the synthetic crew at https://os.structtek.com, or on a local dev server.
- Open `/w/e0851ad8-35d6-4e17-b267-6cd35cb6f713/field` and the trade work order `6af911f6-…`.
- Measure: the job list, no master, no money, the packet, and check-in create / edit / delete / clear hours.
- To exercise the refusals, use a check-in created by *another* person. As the owner, create one from the office side.
- For scripted runs, Jacob puts `FIELD_TEST_EMAIL` and `FIELD_TEST_PASSWORD` in the Track U worktree's `.env.local`. That file is gitignored. Scripts read the values and never print them.

**Track X: §4 checks 1–2 of the org-files proposal.**
- **Check 1** (the crew's `createSignedUploadUrl` is refused) uses the crew credential, reached the same way through `.env.local`.
- **Check 2** (the signed token is bound to its path) needs an **office** signer. Only Jacob's own account holds office rights in this org. Either Jacob runs check 2 signed in as himself, or the controller approves a second synthetic member with the `office` role.
- Run it against a local or preview deployment with `ORG_FILES_ENABLED=true`. Production stays off until both checks pass.
- Files go under the `e0851ad8-35d6-4e17-b267-6cd35cb6f713/` prefix in `org-files`.

## Removing it

**One statement:** `supabase/seeds/20260917_synthetic_field_tenant_teardown.sql`. It is a single `DELETE … FROM organizations` with data-modifying CTEs over every table the seed and the field path write to.

How it behaves:
- Foreign keys are checked at the end of the statement, so the delete is all or nothing. It was proved on 2026-09-17 in a rolled-back transaction: after it ran, 0 rows remained.
- If someone has written to a table it doesn't cover (a signature, a sign link, a purchase order…), the statement **fails on that table's foreign key and removes nothing**.

It does not remove two things:
- **Storage objects** under the org's prefix. Storage refuses direct deletes, so remove them through the Storage API first.
- **The auth user.** Delete it in the dashboard.
