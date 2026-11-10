# Performance reference

Contents: policy expression · indexes · leakproof · membership policies · pooling · inspecting · anti-patterns

Measured on PostgreSQL 18, 200 orgs × 5,000 rows (1M rows/table), `NOBYPASSRLS` role. **(unverified)** marks commonly repeated but unmeasured claims. Re-measure at your largest tenant size.

## Policy expression

`current_setting()` is `STABLE`, not leakproof. Bare, it is inlined: evaluated once per scan as an index condition, per row in a seq-scan or index `Filter`. Wrap it so it becomes an `InitPlan`, in `USING` and `WITH CHECK`:

```sql
organization_id = (SELECT NULLIF(current_setting('app.current_org_id', true), '')::uuid)
```

Forced seq scan, 1M rows: bare 244 ms vs wrapped 72 ms (3.4x). With an index scan the difference is negligible. `FORCE` adds no per-row cost.

## Indexes

Without an index on `organization_id` the policy is a seq scan with the qual in `Filter`.

- Make `organization_id` the **leading** column of every index tenant queries use; `UNIQUE (organization_id, x)` counts. A PK on `id` alone does not help.
- Index `memberships(user_id)`: the `own_memberships_read` policy filters on it.

## Leakproof functions

Policy quals run before user quals unless the user's function is leakproof, so a non-leakproof user qual cannot be an index condition; it becomes a post-index `Filter`.

| Leakproof (index-usable) | Not leakproof (`Filter`) |
| --- | --- |
| `=` on `uuid`, `int4`, `int8`, `text`, `date`, `timestamptz`, `bool` | `=` on `numeric`, `jsonb`; `LIKE`, `ILIKE`, `~` |

Verified: with `(organization_id, amount numeric)`, `WHERE amount = 42` used only `organization_id` as the index condition; with `(organization_id, q bigint)`, `WHERE q = 42` used both. So prefer leakproof types on hot lookups, expect the others to scan the tenant's slice (fine for small tenants, costly for large), and never mark your own function `LEAKPROOF`.

## Membership policies

Avoid joins, `IN (SELECT …)` and `EXISTS` in policies on large tables: `organization_id IN (SELECT organization_id FROM mem WHERE user_id = …)` gave a parallel seq scan over 1M rows despite an org index. Resolve membership once into an array:

```sql
CREATE FUNCTION my_orgs() RETURNS uuid[]
  LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp
AS $$ SELECT coalesce(array_agg(organization_id), '{}') FROM memberships
      WHERE user_id = NULLIF(current_setting('app.current_user_id', true), '')::uuid $$;
REVOKE EXECUTE ON FUNCTION my_orgs() FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION my_orgs() TO app_user;
-- policy: organization_id = ANY (my_orgs())     (bitmap index scan; the (SELECT my_orgs()) form is untested)
```

A `DEFINER` helper is exempt from RLS only if its owner is a superuser or `BYPASSRLS`; otherwise `FORCE` still applies. Simpler when possible: authorize membership in code and use the single-org policy. Never use `VOLATILE` functions in policies (blocks index use).

## Pooling and round trips

- Set both settings in one call: `SELECT set_config('app.current_org_id', $1, true), set_config('app.current_user_id', $2, true)`.
- Batching `BEGIN` + `set_config` into one round trip is **(unverified)** and risky (extended-protocol drivers such as sqlx reject multi-statement text with bind parameters; escaping invites injection). Measure before trying.
- Generic plans are fine (`force_generic_plan` still produced an index condition), but one plan cannot adapt to very large and very small tenants **(unverified)**.
- `count(*)` and aggregates scale with tenant size, same as an explicit `WHERE`. Constraint and FK checks carry no policy cost.
- Tenant partitioning aids maintenance (`DETACH`); don't adopt it for RLS speed **(unverified)**.
- Bulk jobs and reports: a dedicated role with explicit `WHERE organization_id`, not a loop of tenant contexts.

## Inspecting

```sql
SET ROLE app_user;                                           -- never superuser or owner
SELECT set_config('app.current_org_id', '<uuid>', false);    -- session-level OK in a throwaway psql session
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM documents WHERE title = 'x';
```

Look for `Index Cond: organization_id = (InitPlan …)`, not a `Filter`, on large tables. Compare with the owner role plus explicit `WHERE organization_id` to get true RLS overhead. In `pg_stat_statements` the tenant is not in the query text, so statements normalize across tenants.

## Anti-patterns

Bare `current_setting` on large tables · join/`IN`/`EXISTS` membership policies · `VOLATILE` policy functions · no org-leading index · benchmarking as superuser or owner · `LEAKPROOF` for speed · expecting index conditions from `numeric`, `jsonb`, `LIKE`, `ILIKE` filters.
