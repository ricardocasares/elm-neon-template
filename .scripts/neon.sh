#!/bin/sh
set -eu

name=neon-http-proxy
image=ghcr.io/timowilhelm/local-neon-http-proxy:main
port=4445

if ! command -v docker >/dev/null 2>&1; then
  echo "neon: Docker is not installed. Install it from https://www.docker.com" >&2
  exit 1
fi

if ! docker info >/dev/null 2>&1; then
  echo "neon: Docker is not running. Start Docker, then try again." >&2
  exit 1
fi

serving=$(docker ps --filter "publish=$port" --format '{{.Names}}' | head -n 1)

if [ -n "$serving" ]; then
  if [ "$(docker inspect -f '{{.Config.Image}}' "$serving")" != "$image" ]; then
    echo "neon: port $port is taken by the container $serving, which is not the Neon proxy." >&2
    exit 1
  fi
  echo "neon: proxy running in $serving on http://localhost:$port/sql"
elif docker inspect "$name" >/dev/null 2>&1; then
  docker start "$name" >/dev/null
  echo "neon: started $name on http://localhost:$port/sql"
else
  docker run -d --name "$name" --restart unless-stopped -p "127.0.0.1:$port:4444" \
    -e PGPASSWORD=trust \
    -e PG_CONNECTION_STRING=postgres://postgres@host.docker.internal:5432/postgres \
    "$image" >/dev/null
  echo "neon: created $name on http://localhost:$port/sql"
fi

if ! nc -z localhost 5432 >/dev/null 2>&1; then
  echo "neon: nothing answers on localhost:5432. Start Postgres.app, or database routes will fail." >&2
fi
