# `database.types.ts` DESCRIBES WHAT EXISTS, NEVER WHAT A CLIENT CAN CALL

**Standing fact. Recorded by Track S, `Sat Oct 10 03:4x EDT 2026`.** Established with controls on
2026-10-08, not inferred.

---

## THE HAZARD, as a developer meets it

Someone opens `src/lib/supabase/database.types.ts`, sees `work_order_version` in `Functions`, writes:

```ts
const { data } = await supabase.rpc('work_order_version', { p_work_order_id: id })
```

**`tsc` passes cleanly.** The call then fails **at runtime** with:

```
42501  permission denied for function work_order_version
```

**The type file told the truth about the database and nothing at all about the API.**

## WHY — the generator reads `pg_proc`, not the exposed surface

`supabase gen types` is generated **from the catalog.** It enumerates functions in `public` and emits
every one, **without consulting whether `authenticated` holds EXECUTE.**

**Established with controls rather than by inference** (2026-10-08). After
`20261008180116` revoked three functions from `authenticated`, a fresh generation still contained
them — **and so did two functions revoked long before**, which is the control that rules out
"the generator is merely stale":

| function | `proacl` | in freshly generated types |
|---|---|---|
| `create_engagement_from_roadmap` | `postgres=X \| service_role=X` | **yes** — 1 occurrence |
| `work_order_version` | `postgres=X \| service_role=X` | **yes** — 4 occurrences |
| `qc_photo_on_work_order` | `postgres=X \| service_role=X` | **yes** — 1 occurrence |
| `default_permissions_for_role` *(control, revoked long ago)* | `postgres=X \| service_role=X` | **yes** |
| `derive_catalog_price` *(control, revoked long ago)* | `postgres=X \| service_role=X` | **yes** |

**Those five are the current examples.** Anyone reading the type file will find all five and can call
none of them.

**Corollary: the file cannot be used to audit reachability.** Its presence of a function is not
evidence the client can invoke it, and its absence would not be evidence the client cannot.

**And regenerating does NOT close this.** A controller directive said *"the clean close is to
regenerate, not to carry the note"* — **it is not**, and the measurement above is why. The close is
this document.

*(Regeneration was still worth doing, for an unrelated reason: it surfaced ~2200 lines of missing
relationship metadata in the hand-maintained file — 6922 lines against 4722 — while `tsc` had passed
throughout. That is migration rule 6 at scale, and it shipped in `d955058`.)*

---

## COULD A CHECK CATCH THE TRAP? MEASURED: TODAY, ZERO CALL SITES ARE AFFECTED

**The question asked:** does any call site in `src/` invoke a function `authenticated` cannot execute?

**AXIS:** the literal first argument of every `.rpc("…")` in `src/`, extracted by
`grep -rhoE "\.rpc\(\s*[\"'][a-z_]+[\"']" src/`, deduplicated, then each name tested with
`has_function_privilege('authenticated', p.oid, 'execute')` over `pg_proc` in `public`.

**CALIBRATION, before trusting the zero (rule 20):**
- `create_check_in` — a function I know is called — **is in the extracted set.** The axis is live.
- `work_order_version` — revoked Thursday — **is NOT in the set.** Which is also the negative control:
  the three functions closed on 2026-10-08 have no call site, so the revoke broke nothing.

**RESULT, with the size beside it (rule 26):**

```
118 call-site names examined · 118 executable by authenticated · 0 NOT executable · 0 not found in pg_proc
```

**ZERO. There is no live bug.** The `0 not found` matters as much as the `0 not executable`: every
name a call site passes resolves to a real function, so the set contains no typos either.

### Recommendation: YES, this belongs as a readiness check — and it is X's to build, not mine

**Why it is worth a check rather than a document.** The document warns whoever reads it; the hazard
reaches whoever does not. The failing shape is **silent at compile time and only visible at runtime
on the one path that calls it**, which on this build means a roofer's phone. And the trap gets more
likely, not less, every time Track S revokes something — the three closed on 2026-10-08 were the
first instance and there will be others, because the rule-7 test keeps returning "nothing outside the
database calls this."

**Shape, offered as a specification and not as code:**

- **axis:** every literal `.rpc("name")` in `src/`, as above.
- **test:** `has_function_privilege('authenticated', …)` per name.
- **verdict:** FAIL on any name that is not executable, naming the name and its file; FAIL also on any
  name absent from `pg_proc`, which catches typos as a free side effect.
- **calibration it must carry:** a positive control (one known-called function present in the
  extracted set) and the stated limit below, or it reports UNCALIBRATED.
- **the limit it must state:** the axis sees only **literal** first arguments. A computed or
  variable-held function name is invisible to it. Measured today: all 118 are literals, so the axis
  covers the whole surface **as the code is written now** — not as a matter of guarantee.

**Checks are Track X's lane. This is a recommendation, not a build.**
