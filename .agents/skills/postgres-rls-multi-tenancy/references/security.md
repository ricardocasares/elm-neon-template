# Security reference

Contents: exemptions · context · functions · views · policy semantics · constraints · privileges · guards · checklist

**(test)** marks behavior not re-run live; confirm on your server version.

## Exemptions

Superuser and `BYPASSRLS` always skip policies; the owner skips them unless `FORCE`. `TRUNCATE` and `REFERENCES` privileges are not subject to RLS (never grant them), and referential checks and cascades bypass RLS. `FORCE` does not stop a compromised owner from `DISABLE ROW LEVEL SECURITY` or `DROP POLICY`; only a separate low-privilege runtime role does.

## Tenant context

- Use `set_config(…, true)` only. Under PgBouncer transaction mode only transaction-local settings are safe; `DISCARD ALL` / `server_reset_query` helps only in session pooling.
- Outside `BEGIN`, `set_config(…, true)` expires after one statement: the next statement sees `''` and returns 0 rows. Fails closed, but baffling.
- The setting is client-settable: any path that can run `set_config('app.current_org_id', …)` switches tenant. Use parameterized queries, never expose raw SQL, authorize first. Stronger: one `SECURITY DEFINER` setter that verifies membership. `app.current_user_id` has the same trust level.
- The `''` reset holds only if no `ALTER ROLE/DATABASE … SET`, config file or startup option defined the setting. Keep `NULLIF`.
- Jobs and migrations get their own role, not the app pool.

After a transaction ends the setting is `NULL` if the connection never set it, `''` after commit, rollback or abort.

## Functions

`SECURITY DEFINER` runs with the owner's privileges. If the owner is a superuser or `BYPASSRLS`, RLS is off inside; an ordinary owner on a `FORCE`d table is still subject to policies.

```sql
CREATE FUNCTION log_access(doc_id uuid) RETURNS void
  LANGUAGE plpgsql SECURITY DEFINER
  SET search_path = public, pg_temp   -- pg_temp LAST; exclude schemas untrusted users can write
AS $$ ... $$;
REVOKE EXECUTE ON FUNCTION log_access(uuid) FROM PUBLIC;   -- PUBLIC can execute by default
GRANT  EXECUTE ON FUNCTION log_access(uuid) TO app_user;
```

Create and grant in one transaction. Prefer `SECURITY INVOKER`; if `DEFINER`, filter by tenant inside. Never mark functions `LEAKPROOF` (superuser only; may run before the policy qual and leak rows via errors). Find them: `SELECT oid::regprocedure FROM pg_proc WHERE prosecdef;`

## Views

Views run as the **view owner** by default, so a superuser- or owner-owned view bypasses RLS. Use `CREATE VIEW v WITH (security_invoker = true) AS …` (PG 15+). Materialized views have no RLS and cache all tenants; don't expose them to the app role.

## Policy semantics

- No policy on an RLS table means deny all.
- Permissive policies OR; `AS RESTRICTIVE` policies AND.
- `FOR ALL USING (…)` reuses `USING` as `WITH CHECK`; an explicit `FOR UPDATE` needs both.
- `UPDATE`/`DELETE` with `WHERE` or `RETURNING` need `SELECT` visibility. `INSERT … RETURNING` errors if the new row fails the `SELECT` policy. `ON CONFLICT DO UPDATE` checks existing and proposed rows and errors on failure.
- A `FOR SELECT` permissive policy (e.g. `own_memberships_read`) widens reads only.
- Partitions/inheritance: querying a child directly uses the child's policies **(test)**; grant on the parent only.
- `COPY TO` applies `SELECT` policies; `COPY FROM` is unsupported on RLS tables **(test)**. `pg_dump` sets `row_security=off`: dump as the owner.

## Constraints and foreign keys

Unique, PK and FK checks bypass RLS:

- Global `UNIQUE (email)` tells tenant A that B holds the value. Use `UNIQUE (organization_id, email)` when per-tenant uniqueness suffices; where global uniqueness is required the oracle can only be narrowed by not returning the raw error.
- An FK to an unreadable row resolves, so success reveals existence. Close it:

```sql
UNIQUE (organization_id, id)                                            -- parent
FOREIGN KEY (organization_id, project_id) REFERENCES projects (organization_id, id)  -- child
```

  This requires FK columns `NOT NULL` (or `MATCH FULL`; `MATCH SIMPLE` skips the check on any null) and `WITH CHECK` pinning the child's `organization_id`.
- Never return raw Postgres errors, `DETAIL` or constraint names to clients.

## Privileges

```sql
CREATE ROLE app_user LOGIN PASSWORD '…' NOSUPERUSER NOBYPASSRLS NOCREATEDB NOCREATEROLE;
REVOKE CREATE ON SCHEMA public FROM PUBLIC;   -- PG ≤14 grants it
REVOKE TEMP ON DATABASE mydb FROM PUBLIC;
GRANT USAGE ON SCHEMA public TO app_user;
ALTER ROLE app_user SET search_path = public, pg_temp;
```

Grant DML per tenant table. `ALTER DEFAULT PRIVILEGES` exposes every new table with no RLS until enabled (and applies only to objects created by the role that ran it). Global tables get column-limited grants or a policy. Never grant `TRUNCATE`, `REFERENCES`, `CREATE`, ownership or `BYPASSRLS`.

## Guards

**Startup:** refuse to boot and log one greppable evidence line. Reject superuser, `BYPASSRLS`, owning or inheriting tenant tables (`pg_has_role(current_user, tableowner, 'USAGE')` **(test)**), and `session_user <> current_user` (`SET ROLE`).

**CI/startup table check** (a table without `relrowsecurity` ignores its policies; allow-list intentional global tables; optionally enforce via an `ddl_command_end` event trigger):

```sql
SELECT c.oid::regclass FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public' AND c.relkind IN ('r','p')
  AND NOT (c.relrowsecurity AND c.relforcerowsecurity);
```

## Checklist

- [ ] App role: non-superuser, `NOBYPASSRLS`, owns nothing, no `TRUNCATE`/`REFERENCES`/`CREATE`
- [ ] Tenant tables: `ENABLE` + `FORCE`, `organization_id NOT NULL`, `USING` + `WITH CHECK`, `NULLIF`
- [ ] Context via `set_config(…, true)` in a transaction, after authorization; no string-built SQL
- [ ] Every `SECURITY DEFINER`: non-exempt owner or tenant filter, pinned `search_path` (`pg_temp` last), `EXECUTE` revoked from `PUBLIC`
- [ ] Views `security_invoker = true`; no materialized views exposed
- [ ] Unique constraints and FKs include `organization_id`
- [ ] Global tables narrowly granted; jobs and bootstrap use separate roles
- [ ] Startup guard and CI table check run; clients never see raw DB errors
