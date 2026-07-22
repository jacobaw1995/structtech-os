# Migration exports — where files go

Drop the old-BMR export JSON here. **Plan:** `docs/reference/BMR_DATA_MIGRATION_PLAN.md`.
Everything in this folder except this README and `.gitignore` is **git-ignored** (customer PII).

```
docs/migration/bmr-export/
├── migrate/     ← the transform CONSUMES these 4
│   ├── leads.json                       (188 rows)
│   ├── lead_notes.json                  (171 rows)
│   ├── lead_activity.json               (587 rows — chunk the export if truncated)
│   └── profiles.json                    (2 rows — identity map only, not migrated as records)
└── archive/     ← exported for safekeeping, NOT migrated
    ├── products.json                    (11 — seed for the future pricing matrix, §12F)
    ├── pricing_config.json              (2  — how BMR actually prices)
    ├── estimate_document_templates.json (1  — seed for tenant doc templates, §12E)
    └── lead_appointments.json           (5  — parked until Stage 6 scheduling)
```

## Rules

- **`migrate/` is the contract.** CC's transform reads only these four files. If a file isn't here,
  it doesn't get migrated. Nothing in `archive/` is ever read by the transform.
- **Not migrated at all:** `estimates`, `estimate_line_items`, `estimate_activity`,
  `rep_estimate_settings` (effectively test data — one estimate), `lead_import_batches` (metadata),
  and the three empty tables.
- **Filenames matter** — match them exactly; the transform keys off them.

## ⚠️ Git-ignored means NOT backed up

These files are excluded from git on purpose (PII), which also means **git will not protect them**.
The `archive/` files in particular are irreplaceable-ish seed data for the pricing matrix — keep a
second copy somewhere durable (Drive/backup), not only in this folder.
