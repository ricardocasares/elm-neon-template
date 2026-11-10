# AGENTS.md

A Vite app, run by Bun: an Elm browser app and an Elm HTTP server sharing one API contract,
on Postgres (Neon), deployed to Vercel.

## Layout

| Path               | What                                                                       |
| ------------------ | -------------------------------------------------------------------------- |
| `client/`          | Browser app (root `elm.json`). `client/UI/`: elmcn components              |
| `shared/`          | Elm both sides compile: `Api` (routes, endpoints, codecs)                  |
| `api/src/`         | Server Elm (`api/elm.json`): `Main`, `Db`, `Neon` driver                   |
| `api/_ts/`         | Server TypeScript: `app.ts` (starts Elm), `xhr.ts`, `dev.ts` (Vite plugin) |
| `api/index.ts`     | The only Vercel Function                                                   |
| `migrations/`      | Graphile Migrate (`.gmrc`)                                                 |
| `.scripts/neon.sh` | Starts the local Neon proxy                                                |
| `.agents/`         | Agent skills, tracked by `skills-lock.json`; `.claude` links here          |

## Commands

```sh
bun dev                 # types + dev:proxy + dev:vite (:5173, Elm server on /api)
bun run dev:proxy       # local Neon proxy in Docker, then SELECT 1 with DATABASE_URL
bun run build           # types:api, types:app, check, then vite build (server, then client)
bun run preview         # the build on :4173
bun run types           # regenerate *.elm.d.ts after changing an InteropDefinitions.elm
bun check               # type-check both TypeScript projects
bun fmt                 # format (--check to only report)
bun db <command>        # graphile-migrate: migrate, watch, commit, uncommit, status, reset --erase
```

CI (`.github/workflows/ci.yml`) runs `bun fmt --check` and `bun run build`; it needs no
database.

## Rules

- **Bun, not npm**: `bun add -d <pkg>`.
- **No comments** in code or config. Exceptions: tool directives
  (`// @ts-expect-error`, `/// <reference ... />`) and generated or signed files (`.gmrc`,
  `*.elm.d.ts`, committed migrations).
- **`.env.example` mirrors `.env`**: same variables, same order, changed in the same
  commit, with values that work on a fresh checkout and never a secret. Vercel-only
  variables (`DATABASE_URL_UNPOOLED`) stay out of both.
- **SQL values are parameters**: never `++` a request value into SQL; pass `$n` with
  `Neon.text`, `Neon.int`... Only constants may be joined in. An identifier that depends
  on a request is picked from a fixed list.

  ```elm
  Neon.execute ("UPDATE users SET name = '" ++ name ++ "'") []   -- injectable
  Neon.execute "UPDATE users SET name = $1" [ Neon.text name ]    -- safe
  ```

- **Migrations**: edit `migrations/current.sql` under `bun db watch`, idempotent
  (`IF NOT EXISTS`) since it reruns on save, then `bun db commit`. Never edit
  `migrations/committed/`: they are hash-signed.
- **Keep the Elm projects apart**: the root `elm.json` never lists `api/` folders, so the
  database password can't reach the browser bundle. A package `shared/` imports goes in
  both `elm.json`s; server packages: `elm install` inside `api/`.
- **Every route is handled**: `Api.Route` is matched without a wildcard, so a new route
  doesn't compile until the server handles it. Keep `Api.parse` in step with
  `Api.method` and `Api.path`.
- **Every `FromElm` is handled**: the port handlers in `app.ts` and `client/main.ts` take
  `msg` and end `switch (msg.tag)` with a `default` that is `never`:
  `return msg satisfies never;` when `FromElm` has several variants, but
  `return msg.tag satisfies never;` when it has one, as in `client/`: elm-ts-interop then
  emits a plain object, not a union, and TypeScript narrows only `msg.tag`. Switch forms
  when the count crosses one.
- **UI**: use the elmcn registry component instead of writing one; Phosphor
  (`phosphor-icons/phosphor-elm`, `Regular`) instead of hand-written SVG; `sr-only` text
  on icon-only controls.
- **Vercel functions**: every `.ts` under `api/` becomes one unless its name or folder
  starts with `_`. Server TypeScript lives in `api/_ts`; `app.ts` uses Web APIs only.

## Environment

| Variable              | Used by                                                  |
| --------------------- | -------------------------------------------------------- |
| `DATABASE_URL`        | Server, migrations, `dev:proxy`'s check                  |
| `NEON_ENDPOINT`       | Server (local proxy instead of Neon), `dev:proxy`'s port |
| `SHADOW_DATABASE_URL` | `bun db watch` and `commit`                              |
| `ROOT_DATABASE_URL`   | `bun db reset`, the proxy's own connection               |

- Bun loads `.env`, then `.env.local`, then the shell wins, but only when it runs a file
  itself (`bun <file>`): that's why `dev:vite`, `preview` and `db` call
  `bun node_modules/...`. Plain `vite`, `bunx` or `bun --bun <bin>` run as `node` without
  `.env`, and every database route answers 503. `bun run` doesn't pass `.env` to scripts,
  so `neon.sh` reads the files itself, in the same order.
- `vercel env pull` writes `.env.local`, pointing local runs at Neon's `vercel-dev` branch.

## Local database

Needs a running Postgres on `localhost:5432` with a `postgres` superuser, and its client
tools (`psql`, `pg_dump`) on `PATH`. The app uses the `app` database, reached through
Neon's HTTP proxy in Docker at `NEON_ENDPOINT`, as production reaches Neon. One-time
setup:

```sh
cp .env.example .env
bun run dev:proxy
psql postgres://postgres@localhost:5432/postgres \
  -c "SET scram_iterations = 1" \
  -c "CREATE ROLE app LOGIN PASSWORD 'app'" \
  -c "CREATE DATABASE app OWNER app"
bun db migrate
```

- The proxy checks passwords, so the role needs one; one SCRAM iteration makes that ~9 ms
  instead of ~100 ms. Local only.
- `neon.sh` reuses any proxy container already on the port, or starts/creates
  `neon-http-proxy` (`--restart unless-stopped`). The proxy's own connection must be a
  superuser (`ROOT_DATABASE_URL`, `localhost` → `host.docker.internal`); with the app role
  every query fails with "Control plane request failed". It fails only without Docker or
  on a port clash, which stops `bun dev`; a failed `SELECT 1` only warns.
- One proxy serves every database on that Postgres. It holds connections open, so
  `bun db reset --erase` needs `docker stop neon-http-proxy` first. ~50 ms per query.
- The template has no migrations: `/api/health` needs no tables.

## Browser app

- `client/Main.elm`, started by `client/main.ts`. `client/main.css` is the only
  stylesheet, linked from `index.html`: don't import CSS from TypeScript.
- Calls the server only through `ApiClient.request` with an `Api.Endpoint`. On an error
  status it decodes `Api.errorDecoder`, then the endpoint's response (the health report
  comes with a 503).
- The page: the Server card (one row per `Api.checks`, release and region in the
  footer) and a theme toggle (`UI.Tabs` without panels, saved to `localStorage` via the
  `WriteToLocalStorage` port, read back from the flags).
- No layout shift while loading: rows come from `Api.checkNames` with `UI.Skeleton`s,
  refreshes keep the last report, an empty footer keeps its height. Name checks only in
  `Api.namedChecks`.

### elmcn components

shadcn/ui for Elm, copied into `client/UI/` and ours to change. Read a module for its API.

```sh
npx shadcn@latest search ricardocasares/elmcn -q dialog
npx shadcn@latest view ricardocasares/elmcn/dialog
npx shadcn@latest add ricardocasares/elmcn/dialog
mv -n src/UI/*.elm client/UI/ && ls src/UI
```

- The registry installs into `src/UI/`. `mv -n` keeps existing (maybe edited) components;
  whatever `ls` still lists, merge by hand, then delete `src/`. `--diff` can't see
  `client/UI/`.
- Follow the CLI's notes: some items need an Elm package (`elm install` at the root) or
  a script import in `client/main.ts`. Strip their comments.
- Builders: `X.new`, content, variants and sizes, `toHtml`; one `|>` per line.

  ```elm
  Button.new
      |> Button.text "Save"
      |> Button.outline
      |> Button.toHtml [ onClick Save ]
  ```

## Server

- `api/src/Main.elm` is a `Platform.worker`. `app.ts` exports `handle(request)`: each
  request carries its Promise's `resolve` into Elm, which sends it back with the
  response. The Vercel Function and the `app:api` plugin (`dev.ts`) serve `handle`.
- `dev.ts` reloads the server on any `.elm`/`.ts` change in `api/` or `shared/`
  (restarting from `init`); `preview` runs `dist/server/app.js`.
- Routes are real URLs under `/api`: entry points pass requests through unchanged.
- Errors are `{ "error": "..." }` (`Api.encodeError`). JSON is `cache-control: no-store`.
  Without `DATABASE_URL` the server starts anyway and the health check fails.
- Logging: `log Interop.Info|Warn|Error message`; `app.ts` calls `console[level]` with the
  message unchanged, which Vercel reads as the level. Database errors log at `error`.
- `GET /api/health` (IETF health check draft, `application/health+json`) runs `SELECT 1`
  with a 5 s `Neon.withTimeout`. It answers `pass` with 200, `warn` with 200 when slower
  than `slowAfter` (1 s), and `fail` with 503. `output` is a short public reason; the full
  error is only logged, since Postgres messages can name roles and tables. Latency
  includes the hop to Neon and any cold start.
- The report's `releaseId` (`VERCEL_GIT_COMMIT_SHA`, else `VERCEL_DEPLOYMENT_ID`),
  `region` (`VERCEL_REGION`, our own field) and `links.release` (GitHub commit URL from
  `VERCEL_GIT_*`) come from `app.ts`. Off Vercel they are `local`.

## Neon driver

- `Neon.elm` is `neon()` from `@neondatabase/serverless` in Elm: one HTTPS request per
  query or transaction; `Neon.run` and `Neon.commit` return `Task`s. It uses `elm/http`,
  so `app.ts` imports `xhr.ts` first: Bun, Node and Vercel have no `XMLHttpRequest`.
- Rows are JSON objects by column name. `boolean`, `smallint`, `integer`, `real`,
  `double precision`, `json`, `jsonb` and arrays arrive as JSON; `NULL` as `null`;
  everything else (`bigint`, `numeric`, `timestamptz`...) as Postgres's text. Duplicate
  column names keep the last: use `AS`. Decode with the same decoders as the `Api` codecs.
- Parameters travel as text and Postgres converts them; `Neon.json` for `json`/`jsonb`.
- The endpoint comes from the host (`ep-x.eu-central-1.aws.neon.tech` →
  `api.eu-central-1.aws.neon.tech`); `Neon.withEndpoint` overrides it (`NEON_ENDPOINT`).
- The connection string holds the password: server only.

## Vercel

The Vercel project `elm-neon-template` deploys from GitHub: a push to `main` deploys
production, a push to any other branch a preview. `vercel.json` configures it. The Neon
project `elm-neon` is attached through Neon's Vercel integration (installed from the Neon
console, not `vercel integration add neon`, which would provision a new database), which
manages the variables. `.vercel` and `.neon` are local links, not committed. Keep
`regions` next to Neon's region.

| Vercel            | Neon branch                 | Variables                                  |
| ----------------- | --------------------------- | ------------------------------------------ |
| Production        | `main`                      | `DATABASE_URL`, `DATABASE_URL_UNPOOLED`    |
| Preview (`<git>`) | `preview/<git>`, off `main` | same, scoped to the git branch             |
| Development       | `vercel-dev`                | same, for `vercel env pull` (avoid, below) |

- Each preview gets its own Neon branch: the integration cancels the first build, creates
  the branch and its variables, then builds again. Pushing a commit that's already on
  another branch triggers nothing.
- Build: `DATABASE_URL="$DATABASE_URL_UNPOOLED" bun db migrate && bun run build`. Each
  deployment migrates its own branch, so a preview's migrations never reach `main`; a
  missing variable fails the build.
- `build` runs the Elm steps one at a time: on a fresh machine, two processes filling
  `~/.elm` at once corrupt it ("PROBLEM BUILDING DEPENDENCIES"), and elm-ts-interop still
  exits 0. `types:api` must `cd api`, as elm-ts-interop uses the nearest `elm.json`.
- `dist/client` is served; `dist/server` is bundled into `api/index.ts`, which every
  `/api/*` rewrites to (Vercel keeps the original URL in `request.url`). Bun runtime
  (`"bunVersion": "1.x"`, beta).
- Don't `vercel env pull`: it writes the `vercel-dev` connection into `.env.local`, which
  overrides `.env` and points local runs at Neon instead of the local database.
- `neon` CLI: `bunx neon@latest`. Use `--no-env-pull` with `neon link` or
  `neon checkout`, or they write Neon's `DATABASE_URL` into `.env`.
