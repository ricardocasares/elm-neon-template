#!/bin/sh
set -eu

name=neon-http-proxy
image=ghcr.io/timowilhelm/local-neon-http-proxy:main

setting() {
  eval "value=\${$1-}"
  if [ -z "$value" ]; then
    for file in .env.local .env; do
      [ -f "$file" ] || continue
      value=$(sed -n "s/^$1=//p" "$file" | tail -n 1 | sed -e 's/^["'\'']//' -e 's/["'\'']$//')
      [ -z "$value" ] || break
    done
  fi
  if [ -z "$value" ]; then
    echo "neon: $1 is not set. Copy .env.example to .env." >&2
    exit 1
  fi
  printf '%s' "$value"
}

database_url=$(setting DATABASE_URL)
root_database_url=$(setting ROOT_DATABASE_URL)
endpoint=$(setting NEON_ENDPOINT)

port=$(printf '%s' "$endpoint" | sed -En 's#^https?://[^/:]+:([0-9]+).*#\1#p')
if [ -z "$port" ]; then
  echo "neon: NEON_ENDPOINT ($endpoint) has no port, like http://localhost:4445/sql." >&2
  exit 1
fi

control_plane=$(printf '%s' "$root_database_url" | sed -E 's#@(localhost|127\.0\.0\.1)([:/])#@host.docker.internal\2#')

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
  echo "neon: proxy running in $serving on $endpoint"
elif docker inspect "$name" >/dev/null 2>&1; then
  docker start "$name" >/dev/null
  echo "neon: started $name on $endpoint"
else
  docker run -d --name "$name" --restart unless-stopped -p "127.0.0.1:$port:4444" \
    -e PGPASSWORD=trust \
    -e PG_CONNECTION_STRING="$control_plane" \
    "$image" >/dev/null
  echo "neon: created $name on $endpoint"
fi

attempt=0
until answer=$(curl -s --max-time 5 -X POST "$endpoint" \
  -H "Neon-Connection-String: $database_url" \
  -H "Content-Type: application/json" \
  -d '{"query":"SELECT 1","params":[]}'); do
  attempt=$((attempt + 1))
  if [ "$attempt" -ge 10 ]; then
    echo "neon: the proxy does not answer on $endpoint" >&2
    exit 0
  fi
  sleep 1
done

case "$answer" in
  *'"rows"'*)
    echo "neon: DATABASE_URL answers through the proxy"
    ;;
  *)
    echo "neon: DATABASE_URL fails through the proxy: $(printf '%s' "$answer" | sed -n 's/.*"message":"\([^"]*\)".*/\1/p')" >&2
    echo "neon: is Postgres.app running, with the role and database from DATABASE_URL?" >&2
    ;;
esac
