# StructTech OS

Clean-slate home for the unified, multi-tenant StructTech OS build.

**One build, licensed per tenant.** StructTech runs as tenant #1; clients (e.g. Brothers Metal Roofing) are tenants granted a subset of modules. This folder is the new build — the legacy projects under `../structtech/` (admin, audit, pipeline, portal, website) and `../Brothers Metal Roofing/` are reference/inputs, not the base until the codebase-anchor call is made.

## Docs
- [`docs/SCOPE.md`](docs/SCOPE.md) — master scope: tenant/module/role model, confirmed architecture decisions, data-model direction, non-goals.
- [`docs/BUILD_PLAN_3WEEK.md`](docs/BUILD_PLAN_3WEEK.md) — week-by-week plan (foundation → pipeline + estimating → coordination + field + portal).
- `docs/wireframes/` — locked design source of truth (frames 1a–1e, 2a–2i, 3a).

## Status
IA locked. Codebase anchor provisional (pending BMR fixes). Foundation (auth + org + entitlements) is Week 1.
