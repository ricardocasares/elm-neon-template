# elm-neon-template

A starter for full-stack Elm apps: the browser app, the HTTP server, and the database driver
are all Elm. It deploys to Vercel, with Postgres on Neon.

- **Browser app** (`client/`): Elm, built with Vite and styled with Tailwind and
  [elmcn](https://github.com/ricardocasares/elmcn), shadcn/ui components for Elm.
- **Server** (`api/`): an Elm `Platform.worker` that answers HTTP requests, deployed as one
  Vercel Function on the Bun runtime.
- **Database**: Postgres on [Neon](https://neon.com), queried over HTTP by `Neon.elm`, a small
  Elm driver in `api/src/`. The schema is managed with
  [Graphile Migrate](https://github.com/graphile/migrate).
- **Shared contract** (`shared/`): the routes, endpoints and JSON codecs both sides compile
  against, so the client can't call a route the server doesn't have.

It ships with one route, `GET /api/health`, which asks the database for the time and answers
`{ "databaseTime": "..." }`. The browser app calls it and shows the result.

## Use this template

Click **Use this template** on GitHub, or:

```sh
gh repo create my-app --template ricardocasares/elm-neon-template --clone
```

Then rename it: `name` in `package.json`, `<title>` in `index.html`, and the heading in
`client/Main.elm`.

## Requirements

- [Bun](https://bun.com) 1.4 or later
- [Postgres.app](https://postgresapp.com) for the local database
- [Docker](https://www.docker.com), to run Neon's HTTP proxy in front of it
- For deploying: the [Vercel CLI](https://vercel.com/docs/cli), and the `neon` CLI through
  `bunx neon@latest`

## Getting started

```sh
bun install
cp .env.example .env
```

Set up the local database once. The server talks to Postgres through Neon's own HTTP proxy, as
it does in production, so it needs a role with a password:

```sh
# Neon's HTTP proxy on http://localhost:4445/sql, in front of Postgres.app.
# One proxy serves every database on Postgres.app, so skip this if you already run one.
docker run -d --name neon-http-proxy --restart unless-stopped -p 127.0.0.1:4445:4444 \
  -e PGPASSWORD=trust \
  -e PG_CONNECTION_STRING=postgres://postgres@host.docker.internal:5432/postgres \
  ghcr.io/timowilhelm/local-neon-http-proxy:main

# The app role and database (psql is in Postgres.app's bin folder).
psql postgres://postgres@localhost:5432/postgres \
  -c "SET scram_iterations = 1" \
  -c "CREATE ROLE app LOGIN PASSWORD 'app'" \
  -c "CREATE DATABASE app OWNER app"

# The schema.
bun db migrate
```

Then start the app on http://localhost:5173:

```sh
bun dev
curl localhost:5173/api/health
```

## Commands

| Command            | What it does                                                         |
| ------------------ | -------------------------------------------------------------------- |
| `bun dev`          | The app with the Elm server on `/api`, reloading on every change     |
| `bun run build`    | Type-check, then build into `dist/client` and `dist/server`          |
| `bun run preview`  | Serve the build, with the built server on `/api`                     |
| `bun check`        | Type-check the browser app and the server                            |
| `bun fmt`          | Format everything except generated files (`--check` only reports)    |
| `bun db <command>` | Run [Graphile Migrate](https://github.com/graphile/migrate) commands |

## Adding a route

1. Add a constructor to `Api.Route` in `shared/Api.elm`, and handle it in `method`, `segments`
   and `routesAt`.
2. For a JSON route, add an `Endpoint` with the codecs for its body and response.
3. Handle the route in `handle` in `api/src/Main.elm`: the server won't compile until you do.
   Put its queries in `api/src/Db.elm`.
4. Call it from the browser with `ApiClient.request`.

## Changing the schema

Write the change in `migrations/current.sql` while `bun db watch` applies it on every save,
then commit it as a migration:

```sh
bun db watch
bun db commit --message "Create users"
```

Keep `current.sql` idempotent (`IF NOT EXISTS`), because `watch` runs it again on each save.
Never edit a file in `migrations/committed/`: add a new migration instead. `bun db status` lists
what hasn't run yet, and `bun db reset --erase` rebuilds the local database from scratch (stop
the proxy first with `docker stop neon-http-proxy`).

## Deploying

1. Create a Neon project, with a `preview` branch off `main`:

   ```sh
   bunx neon@latest projects create --name my-app
   bunx neon@latest branches create --name preview --project-id <project-id>
   ```

2. Create the Vercel project with `vercel link`, and set `regions` in `vercel.json` to the
   Vercel region closest to your Neon region.
3. Add the connection strings as environment variables. Use each branch's pooled connection
   string (host with `-pooler`) for `DATABASE_URL`, and its direct one for
   `DATABASE_URL_UNPOOLED`, which the build uses to migrate:

   | Vercel environment | Neon branch | `DATABASE_URL` | `DATABASE_URL_UNPOOLED` |
   | ------------------ | ----------- | -------------- | ----------------------- |
   | Production         | `main`      | pooled         | direct                  |
   | Preview            | `preview`   | pooled         | direct                  |

   ```sh
   vercel env add DATABASE_URL production --sensitive
   vercel env add DATABASE_URL_UNPOOLED production --sensitive
   vercel env add DATABASE_URL preview --sensitive
   vercel env add DATABASE_URL_UNPOOLED preview --sensitive
   ```

4. Deploy:

   ```sh
   vercel deploy          # a preview, on Neon's `preview` branch
   vercel deploy --prod   # production, on Neon's `main` branch
   ```

Each build applies pending migrations first, to its own branch: previews never migrate the
production database.

## Project layout

```
client/       the Elm browser app; client/UI/ holds the elmcn components
api/          the Elm server: src/ (Elm), _ts/ (startup and dev glue), index.ts (Vercel Function)
shared/       Elm modules both sides share
migrations/   the database schema, as Graphile Migrate migrations
```

[AGENTS.md](AGENTS.md) has the full details: conventions, how the pieces connect, and the
reasons behind them.

## License

[MIT](LICENSE)
