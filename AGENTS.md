# AGENTS.md

One Vite app with an Elm browser app and an Elm HTTP server, run by Bun:

| Path          | What it is                                                                                                                                                                                                              |
| ------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `client/`     | The Elm browser app, styled with elmcn. `elm.json` at the root.                                                                                                                                                         |
| `api/`        | An HTTP server written in Elm, and its Vercel Function `api/index.ts`. Its own `api/elm.json`.                                                                                                                          |
| `api/src/`    | The server's Elm: `Main.elm`, `Db.elm`, and `Neon.elm`, a driver for Neon Postgres over HTTP.                                                                                                                           |
| `api/_ts/`    | The server's TypeScript: `app.ts`, `xhr.ts`, and `dev.ts` for `bun dev` and `bun run preview`.                                                                                                                          |
| `shared/`     | Elm modules both share: routes, endpoints, JSON codecs.                                                                                                                                                                 |
| `migrations/` | The database schema, as Graphile Migrate migrations. Config in `.gmrc`.                                                                                                                                                 |
| `.agents/`    | Agent skills: `neon`, `neon-postgres` (`bunx neon@latest skills`); `elm-patterns`, `postgres-rls-multi-tenancy` (`npx skills add ricardocasares/skills`). `skills-lock.json` tracks them. `.claude` is a symlink to it. |

Vercel turns every `.js` and `.ts` file under `api/` into a function, except in folders
and files whose names start with `_`. Keep the server's TypeScript in `api/_ts`, so
`api/index.ts` stays the only function. `api/src` holds only Elm and the generated
`Main.elm.d.ts`, which Vercel skips.

The browser app is styled with [elmcn](https://github.com/ricardocasares/elmcn): shadcn/ui
components for Elm. Like shadcn/ui, elmcn is not a package. The CLI copies a component's
source into `client/UI/<Name>.elm`, and from then on the code is ours to read and change.

## Commands

```sh
bun install         # install
bun dev             # the app on :5173, with the Elm server answering /api
bun run build       # browser app into dist/client/, server into dist/server/
bun run preview     # the built app on :4173: dist/client/, with dist/server/app.js on /api
bun check           # type check the browser app and the server
bun fmt             # format everything but generated files (--check only reports)
bun db <command>    # graphile-migrate, see Database
```

`dev` runs `bun run types` alongside Vite. `build` runs `types:api` and `types:app` one
after the other, then `check`, then `vite build`: on a fresh Vercel machine `~/.elm` is
empty, and the two generators filling it at once corrupted `elm/json` ("PROBLEM BUILDING
DEPENDENCIES"). elm-ts-interop still exits 0 then, so the build would carry on silently. `types` regenerates the TypeScript types for both Elm programs at once: `types:app` and `types:api`, through
`bun run --parallel types:*`. Run one on its own with `bun run types:api`. elm-ts-interop
compiles with the `elm.json` of the folder it runs in, so `types:api` must `cd api`:
from the root it would compile the browser's `InteropDefinitions` into
`api/src/Main.elm.d.ts`.

Use `bun`, not npm: `bun add -d <pkg>`.

CI (`.github/workflows/ci.yml`) runs `bun fmt --check` and `bun run build` on every push
to `main` and every pull request. The build needs no database: only Vercel's build
command migrates.

`bun check` and `bun fmt` are Bun's own type checker and formatter. `bun check` runs
the `check` script, which covers both projects (`tsconfig.json` and
`api/tsconfig.json`). `bun fmt` formats TypeScript, JSON, CSS, HTML and Markdown,
Prettier-style at `printWidth = 100` (`bunfig.toml`). It skips what `.gitignore` lists
(`dist/`, `elm-stuff/`) and the generated `*.elm.d.ts` (`.prettierignore`), and
can't parse SQL, `.gmrc` or `bun.lock`, so it never touches the signed migrations. Bun
has no linter.

### Database

`bun db` is graphile-migrate:

```sh
bun db migrate      # apply committed migrations that haven't run yet
bun db watch        # apply migrations/current.sql to the local database on every save
bun db commit --message "Add due dates"   # turn current.sql into a committed migration
bun db uncommit     # move the last committed migration back into current.sql
bun db status       # which migrations are pending
bun db reset --erase   # drop the local database and rebuild it from the migrations
```

To change the schema, edit `migrations/current.sql` while `bun db watch` runs, keeping
it idempotent (`IF NOT EXISTS`, `DROP ... IF EXISTS`), since `watch` runs it again on
every save. Then `bun db commit`.

The local database is the `app` database on Postgres.app (`localhost:5432`), behind
Neon's own HTTP proxy in Docker on `http://localhost:4445/sql`. Set it up once:

```sh
# The proxy. It reaches Postgres.app at host.docker.internal and restarts with Docker.
# It wants a password for its own connection; Postgres.app trusts local ones.
docker run -d --name neon-http-proxy --restart unless-stopped -p 127.0.0.1:4445:4444 \
  -e PGPASSWORD=trust \
  -e PG_CONNECTION_STRING=postgres://postgres@host.docker.internal:5432/postgres \
  ghcr.io/timowilhelm/local-neon-http-proxy:main

# The role and database. The proxy checks the password, so the role needs one. One
# SCRAM iteration keeps that check at ~9 ms instead of ~100 ms per query: fine for
# this local password, never for a real one.
psql postgres://postgres@localhost:5432/postgres \
  -c "SET scram_iterations = 1" \
  -c "CREATE ROLE app LOGIN PASSWORD 'app'" \
  -c "CREATE DATABASE app OWNER app"

cp .env.example .env
bun db migrate
```

`psql` is Postgres.app's, in `/Applications/Postgres.app/Contents/Versions/latest/bin`.
The proxy serves every database on Postgres.app, since each request carries its own
connection string, so one container is enough for several projects. It keeps connections
to `app` open, so `bun db reset --erase` fails with "being accessed by other users" while
it runs: `docker stop neon-http-proxy` first, `docker start neon-http-proxy` after. Queries through the proxy take ~50 ms, the hop
from Docker to the Mac. Committed files in `migrations/committed/` are signed with a
hash: never edit them, add a new migration instead. The template ships with no
migrations: `/api/health` needs no tables.

### Environment

`.env` holds the local settings: `DATABASE_URL`, `NEON_ENDPOINT`, `SHADOW_DATABASE_URL`
and `ROOT_DATABASE_URL`. It is not committed: copy it from `.env.example`, which is, and
keep the two in step when you add a variable. Bun loads it, then `.env.local` over it, whenever it runs a
file itself: `bun <file>`, which is how `dev:vite`, `preview` and `db` run Vite and
graphile-migrate. A bin started as plain `vite`, `bun --bun <bin>` or `bunx` runs as
`node` and does not get `.env`: in `bun dev`, every database route would answer 503. Keep
that form to scripts that need no `.env`, like `build:vite`. Variables set in the shell
win over both files. `.env.example` holds only local values; put anything private in
`.env` or `.env.local`. `vercel env pull` writes `.env.local`, so it
would point local runs at the Vercel database.

## Find components

Search the registry with the shadcn CLI. No `components.json` is needed.

```sh
npx shadcn@latest search ricardocasares/elmcn
npx shadcn@latest search ricardocasares/elmcn -q dialog
```

Each result is an item name such as `button` or `alert-dialog`. To see what an item
installs and which Elm packages it needs, view it:

```sh
npx shadcn@latest view ricardocasares/elmcn/dialog
```

The installed components are the modules in `client/UI/`. Read one to learn its API before
using it.

## Install components

Run the CLI from the repo root. The registry's install path is fixed to `src/UI/`, but
the app's components live in `client/UI/`, so move the new files over afterwards:

```sh
npx shadcn@latest add ricardocasares/elmcn/card ricardocasares/elmcn/input
mv -n src/UI/*.elm client/UI/ && ls src/UI
```

- Each item is written to `src/UI/<Name>.elm`, together with the components it uses.
  `alert-dialog` becomes `UI.AlertDialog`.
- `mv -n` doesn't replace a component `client/UI/` already has, which may have local
  changes. Whatever `ls src/UI` still lists is such a component: compare it with the
  copy in `client/UI/`, keep what's needed, then delete `src/`.
- `--diff` compares with `src/UI/`, so it doesn't see the components in `client/UI/`.
  Compare by hand instead, as above.
- Read the notes the CLI prints after the install. Some items need an Elm package, for
  example `elm install elm/json` (run at the root, for the browser app), or a script that
  `client/main.ts` must import.
- Do not write a component by hand if the registry has it.

## Use components

Components are builders: `X.new`, then content setters, then variant and size setters,
then `toHtml`. Break the line after `X.new` and put each `|>` on its own line.

```elm
import UI.Button as Button

Button.new
    |> Button.text "Save"
    |> Button.outline
    |> Button.small
    |> Button.toHtml [ onClick Save ]
```

Required content is enforced by the type, so an incomplete builder does not compile.

## Code comments

No comments in code: not in Elm (including `{-| -}` doc comments), TypeScript, CSS, SQL,
shell, or config files such as `.env`, `bunfig.toml` and `.prettierignore`. Make the code
say it through names and types; anything it still can't say, such as a constraint, a
workaround or a reason, goes here in AGENTS.md. When you touch a file that has comments,
remove them.

The only exceptions are directives the tools need, which aren't explanations:
`// @ts-expect-error`, `/// <reference types="..." />`, and the like. Leave files that
tools generate or sign alone: `.gmrc` (graphile-migrate's template), `*.elm.d.ts`, and
committed migrations, whose hash covers their comments.

## Project

### Two Elm projects

- `elm.json` (root) compiles the browser app: `client` and `shared`.
  `api/elm.json` compiles the server: `api/src` and `shared`.
  vite-plugin-elm compiles each program with the closest `elm.json` above it.
- Keep them apart: the browser's `elm.json` must not list `api/` folders, so code
  that holds the database password cannot end up in the browser bundle.
- Install an Elm package for the server with `elm install <pkg>` inside `api/`. A
  package a `shared/` module imports must be in both `elm.json` files.
- Each project has its own `InteropDefinitions` and `InteropPorts`, typed with
  elm-ts-interop. After changing either `InteropDefinitions.elm`, run `bun run types`.
- `app.ts` and `client/main.ts` receive each `FromElm` value as `msg` and handle it in a
  `switch (msg.tag)` that ends in `default: return msg satisfies never;`, so a new
  `FromElm` variant doesn't type check until the TypeScript side handles it. Keep that `default` in every such `switch`.

### Shared Elm code

- `Api.Route` lists every server route, all under `/api`. The template has one,
  `GetHealth` (`GET /api/health`): `Api.path` starts with
  `"api"`, and `Api.parse` expects it. Every entry point (`api/index.ts` and the dev
  plugin) passes the request to Elm as it came, so the routes are the real URLs.
  The server handles `Api.Route` in a `case` without a wildcard, so a new route won't
  compile until it is handled. Keep `Api.parse` in step with `Api.method` and
  `Api.path`.
- `Api.Endpoint body response` ties a JSON route to its request and response types. The
  browser app calls the server only through `ApiClient.request` with an endpoint.
- Every route can fail with `{ "error": "..." }`, so the error body is part of `Api` too:
  the server writes it with `Api.encodeError` and the browser reads it with
  `Api.errorDecoder`.

### Browser app

- `client/Main.elm` is the app, started by `client/main.ts`.
- `client/main.css` is the one stylesheet: Tailwind and the theme. `index.html` links it,
  so do not import CSS from TypeScript.
- The page is the Server card, which lists each check from `Api.checks` by name with a
  green (`pass`), yellow (`warn`) or red (`fail`) dot, and below it the theme toggle:
  `UI.Tabs` with tabs that have no panel, one per `Theme`. The choice is saved in
  `localStorage` through the `WriteToLocalStorage` port, and the flags read it back on
  the next load. A new check in `Api.Health` shows up on the card once `Api.checks` names
  it.
- Icons come from the `phosphor-icons/phosphor-elm` package, at the `Regular` weight:
  `Phosphor.sun Regular |> Phosphor.toHtml []`. elmcn has no icon set, so use Phosphor
  rather than writing SVG by hand. Elm's dead code elimination keeps only the icons the
  app uses. An icon-only control needs its label as `sr-only` text.

### Server

- `api/src/Main.elm` is a `Platform.worker`. `api/_ts/app.ts` starts it and
  exports `handle(request)`: each request carries its Promise's `resolve` function into
  Elm, and Elm sends it back with the response. The Vercel Function and the dev plugin
  serve `handle`; there is no standalone server.
- The `app:api` plugin in `api/_ts/dev.ts` serves `/api/*` with `handle` in both of
  Vite's servers. In `bun dev` it runs the source: when an `.elm` or `.ts` file in
  `api/` or `shared/` changes, it loads the server again and the Elm program starts
  from `init`. In `bun run preview` it runs the build, `dist/server/app.js`, so run
  `bun run build` first. Vite restarts by itself when `vite.config.ts` or `dev.ts`
  changes.
- `bun run build` builds the server (Vite's `ssr` environment) into
  `dist/server/app.js`, then the browser app (`client` environment) into
  `dist/client/`, one after the other: Elm processes that fill an empty `~/.elm` at once
  corrupt it.
- The server logs with `log level message` in `api/src/Main.elm`, where the level is
  `Interop.Info`, `Interop.Warn` or `Interop.Error`. `app.ts` passes the message as it is
  to `console.info`, `console.warn` or `console.error`, which Vercel shows as the log's
  level: write the whole message in Elm, as `app.ts` adds nothing. At startup the server
  logs at `info` where it sends queries, at `warn` when it has no database, and at
  `error` when its flags don't decode. A slow health check logs at `warn`; a failed one,
  and every database error, at `error`.
- The server reaches Postgres through the Neon driver; the queries are in
  `api/src/Db.elm`. The server reads `DATABASE_URL`, and `NEON_ENDPOINT` to send queries
  to a local proxy instead of Neon. Routes that query through `withDb` answer 503 without
  `DATABASE_URL`, and 500 on a database error, logged as `Database error: ...`.
  JSON responses carry `cache-control: no-store`.
- `GET /api/health` follows the IETF health check draft
  (`application/health+json`): `status` is `pass`, `warn` or `fail`, and `checks.database` has
  the database's `status`, `latencyMs` and, when it fails, an `output`. It runs
  `SELECT 1`, which needs no tables, with a 5 second `Neon.withTimeout`, so a hung
  database fails the check instead of holding the request until the function times out.
  It answers `warn` when the query took longer than `slowAfter` (1 second), which is
  still a 200, as the draft says: the database works, slowly. It answers 200 on pass and
  warn and 503 on fail, which is what load balancers and uptime monitors look for. The
  browser app shows the status as a green, yellow or red dot. `output` is a short public
  reason (timed out, unreachable, the query failed); the full error is logged as `Health check failed: ...`, since Postgres
  messages can name roles and tables. The latency is measured with `Time.now` around the
  query, so it includes the HTTP hop to Neon, and a first request after scale to zero
  includes the compute starting.
- The health report also carries `releaseId` and `region`, so a report says which
  deploy and which region answered. `app.ts` reads them at startup: `releaseId` from
  `VERCEL_GIT_COMMIT_SHA`, or `VERCEL_DEPLOYMENT_ID` for a CLI deploy without git
  metadata, and `region` from `VERCEL_REGION`. Off Vercel (`VERCEL` unset) both are
  `local`; on Vercel a variable that is missing leaves its field out. `releaseId` is the draft's own field; `region` is ours. The card shows
  them in its footer, with a commit shortened to 7 characters.
- `ApiClient` reads an error status's body with `Api.errorDecoder` first, then with the
  endpoint's own response decoder, so the browser app gets the health report on a 503
  too.
- Local database: see Database above. The same `DATABASE_URL` works for the proxy and
  for a direct connection, as a Neon connection string does, so the server and Graphile
  Migrate share it.

### Neon driver

- `Neon` queries a Neon database over HTTP, one request per query or per transaction,
  like `neon()` in `@neondatabase/serverless`. `Neon.run` and `Neon.commit` return
  `Task`s. Rows arrive as JSON objects keyed by column name, with booleans, numbers and
  `jsonb` as JSON, so `Neon.select` takes a `Json.Decode.Decoder`. Decode rows with the
  same decoders the shared `Api` codecs use, so the database and the API agree.
- Neon turns `boolean` into a JSON boolean; `smallint`, `integer`, `real` and
  `double precision` into numbers; `json`, `jsonb` and arrays into JSON; and `NULL` into
  `null` (`Decode.nullable`). Everything else is a string as Postgres prints it,
  including `bigint`, `numeric` and `timestamptz`, so they stay exact. If two columns
  share a name, the row keeps the last one, so rename them with `AS`.
- Parameters are sent as Postgres text, as in the official driver, and Postgres converts
  them to the column types. `Neon.json` is for `json` and `jsonb` columns.
- `Neon.connect` derives the HTTP endpoint from the connection string's host, as the
  official driver does: `ep-cool-lake-123456.eu-central-1.aws.neon.tech` sends queries to
  `api.eu-central-1.aws.neon.tech`. `Neon.withEndpoint` overrides it, as `NEON_ENDPOINT`
  does for the local proxy.
- It uses `elm/http`, so `app.ts` imports `api/_ts/xhr.ts` before starting Elm: Bun,
  Node and Vercel Functions have no `XMLHttpRequest`.
- The connection string holds the database password, so only use it on the server.
- Never build SQL with `++` from a value that came from a request: pass it as a `$n`
  parameter (`Neon.text`, `Neon.int`, ...), which Postgres treats as data. The driver
  takes SQL as a plain `String`, so nothing else stops an injection. Only constants in
  the code, like a list of column names, may be joined into the SQL text. Identifiers
  (table and column names) can't be parameters: if one must depend on a request, pick it
  from a fixed list.

  ```elm
  -- Vulnerable: the name becomes part of the SQL
  Neon.execute ("UPDATE users SET name = '" ++ name ++ "'") []

  -- Safe: the name is a value
  Neon.execute "UPDATE users SET name = $1" [ Neon.text name ]
  ```

### Vercel

The repo deploys as one Vercel project, configured by `vercel.json`, on one Neon project
with two branches, `main` and `preview`. `.vercel` and `.neon` link them locally and are
not committed. Set `regions` in `vercel.json` to the Vercel region closest to the Neon
project's region.

- `bun install`, then the migrations, then `bun run build`. The browser app is served
  from `dist/client`; `dist/server` stays private, bundled into the function.
- `api/index.ts` is the only function. It imports `handle` from `dist/server/app`, which
  the build produces, and serves every `/api/*` path through a rewrite. It relies on
  Vercel keeping the original URL in `request.url` after the rewrite, for Elm to route on.
- Functions run on Vercel's Bun runtime (`"bunVersion": "1.x"`, in beta). Keep
  `api/_ts/app.ts` to Web APIs (`Request`, `Response`, `crypto`) anyway, so it runs on
  any runtime.
- Environment variables, stored as secrets on Vercel:

  | Vercel environment | Neon branch | `DATABASE_URL` (the app) | `DATABASE_URL_UNPOOLED` (migrations) |
  | ------------------ | ----------- | ------------------------ | ------------------------------------ |
  | Production         | `main`      | pooled (`-pooler`)       | direct                               |
  | Preview            | `preview`   | pooled (`-pooler`)       | direct                               |

  Without `DATABASE_URL`, database routes answer 503. `.env` is not uploaded
  (`.vercelignore`), and `NEON_ENDPOINT` is unset on Vercel, so the driver talks to Neon.

- The build command migrates first, over the direct connection, as migrations need:
  `DATABASE_URL="$DATABASE_URL_UNPOOLED" bun db migrate`. A missing
  `DATABASE_URL_UNPOOLED` fails the build before anything deploys. Preview builds
  migrate the `preview` branch, never `main`, so a migration reaches production only
  when it is deployed there. Reset the preview branch to production with
  `bunx neon@latest branches reset preview --parent`.
- The variables are secrets, so `vercel pull` brings back empty values and a local
  `vercel build` fails at the migration step. To try the build command locally, set
  `DATABASE_URL_UNPOOLED` yourself, to a branch you can afford to migrate.
- The `neon` CLI runs through `bunx neon@latest` (it isn't installed globally). Don't
  run `neon link` or `neon checkout` without `--no-env-pull`: they would write the Neon
  `DATABASE_URL` into `.env`, which is for the local database.
