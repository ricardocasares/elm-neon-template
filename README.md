# elm-neon-template

Full-stack Elm: an Elm browser app, an Elm HTTP server and an Elm Postgres driver, deployed to
Vercel on Neon.

[![Deploy with Vercel](https://vercel.com/button)](https://vercel.com/new/clone?repository-url=https%3A%2F%2Fgithub.com%2Fricardocasares%2Felm-neon-template&project-name=elm-neon-template&repository-name=elm-neon-template&stores=%5B%7B%22type%22%3A%22integration%22%2C%22integrationSlug%22%3A%22neon%22%2C%22productSlug%22%3A%22neon%22%2C%22protocol%22%3A%22storage%22%7D%5D)

| Part     | Where      | Built with                                                            |
| -------- | ---------- | --------------------------------------------------------------------- |
| Browser  | `client/`  | Elm, Vite, Tailwind, [elmcn](https://github.com/ricardocasares/elmcn) |
| Server   | `api/`     | Elm `Platform.worker` in one Vercel Function (Bun runtime)            |
| Shared   | `shared/`  | Routes, endpoints and JSON codecs both sides compile against          |
| Database | `api/src/` | `Neon.elm`, Postgres over HTTP; schema with Graphile Migrate          |

## Quick start

Needs [Bun](https://bun.com), [Docker](https://www.docker.com) and a running Postgres on
`localhost:5432`, with `psql` and `pg_dump` on `PATH`.

```sh
gh repo create my-app --template ricardocasares/elm-neon-template --private --clone
cd my-app
bun install
cp .env.example .env
bun db migrate
bun dev
```

Open http://localhost:5173. Then rename `name` in `package.json` and `<title>` in `index.html`.

## Scripts

| Script              | Does                                                                      |
| ------------------- | ------------------------------------------------------------------------- |
| `bun dev`           | Runs `types`, `dev:proxy` and `dev:vite` together                         |
| `bun run dev:proxy` | Starts the local Neon proxy in Docker, checks `DATABASE_URL` through it   |
| `bun run dev:vite`  | Vite on :5173, with the Elm server on `/api`                              |
| `bun run build`     | Types, type-check, then builds into `dist/client` and `dist/server`       |
| `bun run preview`   | Serves the build on :4173                                                 |
| `bun run types`     | Regenerates the TypeScript types of both Elm programs                     |
| `bun check`         | Type-checks the browser app and the server                                |
| `bun fmt`           | Formats everything; `--check` only reports                                |
| `bun db <command>`  | Graphile Migrate: `migrate`, `watch`, `commit`, `status`, `reset --erase` |

## Environment

`.env.example` lists every variable. Copy it to `.env`.

| Variable              | For                                                         |
| --------------------- | ----------------------------------------------------------- |
| `DATABASE_URL`        | The app's database                                          |
| `NEON_ENDPOINT`       | The local proxy, `http://localhost:4445/sql`; not on Vercel |
| `SHADOW_DATABASE_URL` | A scratch database for `bun db watch` and `commit`          |
| `ROOT_DATABASE_URL`   | A superuser, for `bun db reset` and the proxy               |

## Health check

`GET /api/health` runs `SELECT 1` and answers in the
[health check format](https://datatracker.ietf.org/doc/html/draft-inadarei-api-health-check):
`pass` (200), `warn` when slower than 1 s (200), or `fail` (503).

```json
{
  "status": "pass",
  "releaseId": "7990ba2…",
  "region": "arn1",
  "links": { "release": "https://github.com/…/commit/7990ba2…" },
  "checks": { "database": { "status": "pass", "latencyMs": 25 } }
}
```

## Schema changes

```sh
bun db watch                              # applies migrations/current.sql on every save
bun db commit --message "Create users"    # turns it into a committed migration
```

## More

[AGENTS.md](AGENTS.md) has the conventions and the reasons behind them. License: [MIT](LICENSE).
