# revealz

Godot 4 카드 게임 **revealz**의 공개 소개 레포입니다.  
게임플레이보다, 온라인 서비스를 돌리기 위한 **운영(ops) 스택** — Node.js 로비, Docker Compose, 모니터링/관리 UI, CI/CD — 을 중심으로 정리합니다.

> 소스 전체·배포 시크릿은 이 레포에 포함하지 않습니다. 아래 GIF는 자리만 잡아 두었고, 녹화본 경로가 정해지면 교체합니다.

---

## Play

<!-- TODO: replace with recorded GIF -->
![Gameplay overview](docs/media/play-overview.gif)

짧은 플레이 클립 (매치 / 턴 / 리빌 등).

---

## Features (game)

| | |
|---|---|
| 팩 오픈 | ![Pack open](docs/media/feature-pack-open.gif) |
| 덱 / 상점 | ![Deck & shop](docs/media/feature-deck-shop.gif) |
| 온라인 매치 | ![Online match](docs/media/feature-online-match.gif) |

- 카드 수집 · 팩 연출 · 덱 편집
- 로비 기반 방 생성 / 참가 · 랜덤 매칭
- 패치노트 · 점검 게이트 등 클라이언트–서버 연동

*(표의 GIF는 placeholder — 파일만 `docs/media/`에 넣으면 표시됩니다.)*

---

## Ops (main)

온라인 세션과 메타(계정·골드·보유 카드)를 VM에서 운영하는 쪽을 메인으로 소개합니다.

### Stack

```text
┌─────────────┐     ┌──────────────────────┐     ┌─────────────────┐
│  Godot 클라  │────▶│  Node.js lobby :8080 │────▶│ Dedicated worker│
│             │◀────│  rooms / matchmaking │◀────│  (UDP spawn)    │
└─────────────┘     │  MetaSrv HTTP        │     └─────────────────┘
                    └──────────┬───────────┘
                               │
                    ┌──────────▼───────────┐
                    │  Postgres 16 (meta)  │
                    │  loopback only       │
                    └──────────────────────┘
                               ▲
                    ┌──────────┴───────────┐
                    │  health poller       │
                    │  → health.jsonl      │
                    └──────────────────────┘
```

- **Docker Compose**: `postgres` + `lobby` + `poller`
- Lobby / poller는 **host network** (UDP 포트 풀), Postgres는 **127.0.0.1만** 바인딩
- 매치 Dedicated는 컨테이너가 아니라 lobby가 **Linux headless 바이너리를 spawn**
- Warm pool · 방 TTL · 매칭 타임아웃 · UDP 포트 범위는 env로 조정

### Lobby (Node.js)

- 방 생성 / 참가, 랜덤 매칭 큐
- UDP 포트 할당 → 워커 listening 확인 후 클라에 `host` / `port` 전달
- `GET /v1/health` — rooms, queue, warm, free ports, meta DB, worker 바이너리 메타, maintenance
- Meta API — 계정 스냅샷, 구매, 덱 검증, revision 기반 동시 수정 방지(LWW)

### Monitor — `/ops`

<!-- TODO: replace with recorded GIF -->
![Ops monitor](docs/media/ops-monitor.gif)

- `OPS_TOKEN` 게이트 (없거나 틀리면 404)
- rooms / queue / warm / freePorts 시계열 (`health.jsonl`)
- 호스트 CPU · 메모리 (poller + host PID)

### Admin — `/ops/db`

<!-- TODO: replace with recorded GIF -->
![Ops admin](docs/media/ops-db.gif)

| 영역 | 내용 |
|------|------|
| 점검 | maintenance on/off + 메시지 → 클라 온라인/상점 차단 |
| 백업 | `pg_dump` (client 버전을 Postgres 16에 맞춤) |
| 복구 | `pg_restore` (관리 UI에서 선택 복원) |
| 계정 | 목록 · 검색 · 정렬 · 페이지네이션 |
| 유저 수정 | 골드 / 표시명 |
| Grant | 단건 카드 · 전종×레어도 |
| 삭제 | hard delete + 동일 키 재이관 차단(tombstone) |
| 패치노트 | CRUD · 즉시/예약 발행 · 클라 공개 API |

CLI (`tools/ops.py`)로 health / grant / maintenance / backup / delete-account 등 동일 작업을 스크립트로도 실행합니다.

### Client ↔ server gates

- 부팅 · 메인 복귀 · 온라인/상점 진입 시 health(+meta) 재확인
- 점검 중 조작 차단
- meta revision 충돌 시 서버 스냅샷 적용 (ops grant가 클라 PUT에 덮이지 않도록)
- 삭제된 계정은 `410`으로 재이관 차단

### CI / CD (GitHub Actions)

| 워크플로 | 하는 일 | 하지 않는 일 |
|----------|---------|--------------|
| **Lobby CI** | `npm ci` → `node --check` → `/v1/health` smoke | Godot 빌드, Dedicated spawn |
| **Pull VM** | SSH로 VM `git pull --ff-only` | `docker compose build` / 재시작 |

이미지 재빌드·로비 재시작은 **수동**으로 둡니다. 운영 실 실수를 줄이기 위한 경계입니다.

---

## Docs media (GIF placeholders)

녹화 후 아래 경로에 파일을 넣으면 README에 바로 보입니다.

```text
docs/media/
  play-overview.gif          # 플레이 전체 한 컷
  feature-pack-open.gif      # 팩 오픈
  feature-deck-shop.gif      # 덱 / 상점
  feature-online-match.gif   # 온라인 매치
  ops-monitor.gif            # /ops 모니터
  ops-db.gif                 # /ops/db 관리
```

경로·파일명을 바꾸면 README의 이미지 링크만 맞춰 주면 됩니다.

---

## Status

개인/학습용 온라인 카드 게임 + 소규모 VM ops 실험입니다.  
이 공개 레포는 **소개용**이며, 프로덕션 SLA나 완전 자동 배포를 약속하지 않습니다.
