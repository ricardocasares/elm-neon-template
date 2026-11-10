# Templates

Contents: roles · schema and policies · context helper · startup guard · tests

Adjust names (`app_user`, `app.current_org_id`) to the project.

## Roles (as the owner, once)

```sql
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'app_user') THEN
    CREATE ROLE app_user LOGIN PASSWORD '<from secret store>'
      NOSUPERUSER NOBYPASSRLS NOCREATEDB NOCREATEROLE;
  END IF;
END $$;

REVOKE CREATE ON SCHEMA public FROM PUBLIC;
GRANT  USAGE  ON SCHEMA public TO app_user;
ALTER ROLE app_user SET search_path = public, pg_temp;
GRANT SELECT, INSERT, UPDATE, DELETE ON documents, memberships TO app_user;  -- per tenant table
GRANT SELECT (id, name) ON organizations TO app_user;                        -- global tables: narrow
```

## Schema and policies

```sql
CREATE TABLE memberships (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  user_id         uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  UNIQUE (organization_id, user_id)
);
CREATE INDEX ON memberships (user_id);

-- per tenant table (documents, memberships, ...): ENABLE + FORCE + tenant_isolation as in SKILL.md

-- Pre-context org switcher: read-only, scoped to the user's own rows.
CREATE POLICY own_memberships_read ON memberships FOR SELECT
  USING (user_id = (SELECT NULLIF(current_setting('app.current_user_id', true), '')::uuid));
```

## Context helper (Rust, sqlx)

Needs `sqlx` (features `postgres`, `uuid`, `runtime-tokio`), `uuid`, `thiserror`, `anyhow`.

```rust
use sqlx::{PgPool, Postgres, Transaction};
use uuid::Uuid;

#[derive(Debug, thiserror::Error)]
pub enum TenantError {
    #[error("forbidden")] // same error for "not a member" and "no such org"
    Forbidden,
    #[error(transparent)]
    Db(#[from] sqlx::Error),
}

/// Starts a transaction scoped to one tenant. Run every tenant query on it, then `commit()`.
/// Dropping it without commit rolls back, and the transaction-local settings go with it.
pub async fn begin_tenant(
    pool: &PgPool,
    user_id: Uuid,
    org_id: Uuid, // from the URL: untrusted until the membership check below
) -> Result<Transaction<'static, Postgres>, TenantError> {
    let mut tx = pool.begin().await?;

    sqlx::query("SELECT set_config('app.current_user_id', $1, true)")
        .bind(user_id.to_string())
        .execute(&mut *tx)
        .await?;

    // own_memberships_read exposes only this user's rows while no org is set.
    let member: bool = sqlx::query_scalar(
        "SELECT EXISTS (SELECT 1 FROM memberships WHERE organization_id = $1)",
    )
    .bind(org_id)
    .fetch_one(&mut *tx)
    .await?;

    if !member {
        return Err(TenantError::Forbidden);
    }

    sqlx::query("SELECT set_config('app.current_org_id', $1, true)")
        .bind(org_id.to_string())
        .execute(&mut *tx)
        .await?;

    Ok(tx)
}

// let mut tx = begin_tenant(&pool, user_id, org_id).await?;
// let docs = sqlx::query_as::<_, Document>("SELECT id, title FROM documents").fetch_all(&mut *tx).await?;
// tx.commit().await?;
```

A `begin_user` variant sets only `app.current_user_id` (post-login org list). Always pass values with `.bind()`; never `format!` them into SQL.

## Pool setup

```rust
use sqlx::postgres::{PgConnectOptions, PgPoolOptions};

let opts: PgConnectOptions = std::env::var("APP_DATABASE_URL")?.parse()?; // app_user, never the owner
let pool = PgPoolOptions::new()
    .max_connections(10)
    // PgBouncer transaction mode without prepared-statement support (before 1.21): disable sqlx's per-connection statement cache.
    .connect_with(opts.statement_cache_capacity(0))
    .await?;
```

Run `sqlx migrate` with a separate owner `DATABASE_URL`, never the app's.

## Startup guard

```rust
#[derive(sqlx::FromRow)]
struct RoleEvidence {
    user: String,
    session_user: String,
    is_superuser: bool,
    can_bypass_rls: bool,
    row_security: String,
    owned_tables: i64,
}

pub async fn assert_rls_contained(pool: &PgPool) -> anyhow::Result<()> {
    let e: RoleEvidence = sqlx::query_as(
        r#"SELECT current_user AS "user", session_user AS "session_user",
                  rolsuper AS is_superuser, rolbypassrls AS can_bypass_rls,
                  current_setting('row_security') AS row_security,
                  (SELECT count(*) FROM pg_tables WHERE schemaname = 'public'
                     AND pg_has_role(current_user, tableowner, 'USAGE')) AS owned_tables
             FROM pg_roles WHERE rolname = current_user"#,
    )
    .fetch_one(pool)
    .await?;

    let mut problems = vec![];
    if e.is_superuser { problems.push("superuser".to_string()); }
    if e.can_bypass_rls { problems.push("BYPASSRLS".to_string()); }
    if e.owned_tables > 0 { problems.push(format!("owns/inherits {} table(s)", e.owned_tables)); }
    if e.user != e.session_user { problems.push("SET ROLE active".to_string()); }
    if !problems.is_empty() {
        anyhow::bail!("Refusing to start: role \"{}\" is exempt from RLS ({})", e.user, problems.join(", "));
    }
    tracing::info!(
        "[rls] contained: user={} superuser={} bypassrls={} owned_tables={} row_security={}",
        e.user, e.is_superuser, e.can_bypass_rls, e.owned_tables, e.row_security
    );
    Ok(())
}
```

Call it in `main` before serving. Run the CI table check from `security.md` alongside it.

## Tests (live database, as `app_user`, pool of 1 connection)

1. Role: not superuser, not `BYPASSRLS`, owns 0 tables.
2. No context → 0 rows.
3. Tenant A sees only A.
4. A inserting a row for B fails with `42501`.
5. Reused connection after a tenant transaction → 0 rows, no `22P02`.
6. A then B on one connection → B sees only B.
7. Commit, rollback and abort each leave 0 visible rows.
8. `own_memberships_read` lists the user's orgs with no org context.
9. Cross-tenant FK and duplicate-unique probes return the same error for "exists in B" and "exists nowhere".
