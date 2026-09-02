# revealz lobby

Node.js HTTP lobby — rooms, matchmaking, meta API, ops UI.

## Local run

```bash
cd lobby
cp .env.example .env   # fill OPS_TOKEN, POSTGRES_PASSWORD if using meta DB
npm ci
npm start
```

Default: `http://127.0.0.1:8080`

## Docker Compose (from repo root)

```bash
cp lobby/.env.example lobby/.env
docker compose up -d
```

Postgres binds to `127.0.0.1:5432` only. Lobby and poller use host network for UDP worker ports.

## Ops

- Monitor: `GET /ops?token=<OPS_TOKEN>`
- Admin: `GET /ops/db?token=<OPS_TOKEN>`
- Without `OPS_TOKEN`, ops routes return 404.

Dedicated server binary (`export/revealz_server`) is not included in this public repo.
