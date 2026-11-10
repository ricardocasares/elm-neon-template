---
name: postgres-rls-multi-tenancy
description: Implement and audit PostgreSQL Row Level Security (RLS) for multi-tenant apps, focused on security and query performance. Use for CREATE POLICY, ENABLE/FORCE ROW LEVEL SECURITY, tenant context via set_config or SET LOCAL behind a pool or PgBouncer, the app database role, SECURITY DEFINER functions or views that leak across tenants, slow queries or empty results under RLS, or any mention of tenant isolation, organization_id policies, BYPASSRLS or cross-tenant leaks.
license: MIT. Adapted from https://github.com/wenceslauAndre/postgres-rls-multi-tenancy, extended with PostgreSQL doc checks and query-plan measurements.
metadata:
  source: https://github.com/wenceslauAndre/postgres-rls-multi-tenancy
  postgres-versions: "15-18 (security_invoker views need 15+)"
---

# Postgres RLS multi-tenancy

RLS moves tenant isolation from a convention (`WHERE organization_id = $1` everywhere) into the database, so a forgotten filter returns zero rows instead of another tenant's data. It is a second line of defense: keep writing the `WHERE`. RLS fails silently (a policy that does nothing looks like one that works), so each rule below closes a specific way policies go inert or leak.

## Read what the task needs

| Task | Read |
| --- | --- |
| New setup | this file, then `references/templates.md` |
| Security review | `references/security.md` |
| Slow queries, indexes, policy design | `references/performance.md` |

## Rules

1. **App role owns nothing.** Superusers, `BYPASSRLS` roles and (without `FORCE`) table owners skip policies. Migrations run as the owner; the app connects as a `NOSUPERUSER NOBYPASSRLS` role with DML grants only.
2. **`ENABLE` and `FORCE` RLS on every tenant table.** `FORCE` subjects the owner to policies. It does not contain superusers or `BYPASSRLS` roles, or an owner who runs `DISABLE ROW LEVEL SECURITY`.
3. **Set tenant context with `set_config(name, value, true)` inside a transaction**, with bind parameters. Session-level values leak to the next request on a pooled connection; outside `BEGIN` the value lasts one statement; `SET LOCAL` takes no bind parameters.
4. **Wrap in `NULLIF(…, '')`.** After the transaction ends the setting is `''`, not `NULL`, so a bare `''::uuid` raises `22P02` on a reused connection. `NULLIF` gives `NULL`, which matches nothing: fail closed. The `''` reset is undocumented; never rely on it.
5. **Write `USING` and `WITH CHECK`.** `WITH CHECK` stops writes into another tenant.
6. **Authorize before setting context.** The policy trusts whatever the session holds, and `app_user` can call `set_config` itself. Verify the user belongs to the org in code first; any SQL injection can switch tenant.
7. **Put the tenant in constraints.** Unique and FK checks bypass RLS and act as oracles: use `UNIQUE (organization_id, x)` and composite FKs `(organization_id, parent_id) REFERENCES parent (organization_id, id)`.
8. **Assert invariants at startup and in CI:** refuse to boot if the runtime role is exempt; fail CI if a tenant table lacks `ENABLE` and `FORCE`.

## Canonical shape

```sql
CREATE TABLE documents (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  title           text NOT NULL
);
CREATE INDEX ON documents (organization_id);

ALTER TABLE documents ENABLE ROW LEVEL SECURITY;
ALTER TABLE documents FORCE  ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON documents
  USING      (organization_id = (SELECT NULLIF(current_setting('app.current_org_id', true), '')::uuid))
  WITH CHECK (organization_id = (SELECT NULLIF(current_setting('app.current_org_id', true), '')::uuid));
```

`(SELECT …)` makes Postgres evaluate the setting once per query (`InitPlan`) instead of per row: 3.4x faster on a 1M-row seq scan, neutral with an index.

```rust
// after authorizing the user for org_id (templates.md: begin_tenant does this)
let mut tx = pool.begin().await?;
sqlx::query("SELECT set_config('app.current_org_id', $1, true)")
    .bind(org_id.to_string()).execute(&mut *tx).await?;
// ... queries on &mut *tx ...
tx.commit().await?; // dropping tx rolls back
```

## Workflow

1. **Classify tables.** Global tables (`organizations`, `users`) lack a tenant column but still need narrow grants or their own policy; blanket DML lets tenants read all users. Everything else gets `organization_id NOT NULL`, a leading-tenant index and a policy.
2. **Create roles**, revoke what the app role must not have (`references/security.md`).
3. **Add policies.** Use `AS RESTRICTIVE` for extra mandatory guards: permissive policies are OR'd, so one stray one widens access.
4. **Route all tenant queries through one context helper**, then add the startup guard and CI table check.
5. **Test on a live database as `app_user`** (mocks pass while real databases leak): no context gives 0 rows; A cannot read B; cross-tenant `INSERT` fails `42501`; a reused connection returns 0 rows without error; A then B on one connection shows only B; commit, rollback and abort clear context.
6. **Check plans as `app_user`** with context set (`EXPLAIN (ANALYZE, BUFFERS)`). Superuser or owner plans contain no RLS.

## Limits

- RLS filters; it does not authorize org entry.
- Pre-tenant lookups (session or invite by token) use a narrow dedicated role or locked-down function, not the general owner connection.
- Jobs running as an exempt role must filter by `organization_id` explicitly.
- Error messages and planner statistics can reveal that other tenants' data exists; return generic errors.
