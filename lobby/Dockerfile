FROM node:20-bookworm-slim

# Match compose postgres:16 — default bookworm postgresql-client is 15.x and
# pg_dump aborts on major version mismatch.
RUN apt-get update \
  && apt-get install -y --no-install-recommends ca-certificates curl gnupg \
  && curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc \
    | gpg --dearmor -o /usr/share/keyrings/postgresql.gpg \
  && echo "deb [signed-by=/usr/share/keyrings/postgresql.gpg] http://apt.postgresql.org/pub/repos/apt bookworm-pgdg main" \
    > /etc/apt/sources.list.d/pgdg.list \
  && apt-get update \
  && apt-get install -y --no-install-recommends postgresql-client-16 \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /app/lobby

COPY lobby/package.json lobby/package-lock.json ./
RUN npm ci --omit=dev

COPY lobby/ ./
# Ops grant-all scans Godot card .tres ids (CARDS_ROOT = /app/resources/cards).
COPY resources/cards /app/resources/cards

CMD ["node", "server.js"]
