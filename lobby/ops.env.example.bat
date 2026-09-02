@echo off
REM Copy to ops.env.bat (gitignored) and fill in. Do not commit secrets.
set OPS_TOKEN=change-me
set LOBBY_PUBLIC_HOST=20.194.13.132
set META_DATABASE_URL=postgres://revealz_meta:PASSWORD@127.0.0.1:5432/revealz_meta
set META_LOBBY_URL=http://127.0.0.1:8080
REM Optional. Empty = `pg_dump` on PATH.
set PG_DUMP=
