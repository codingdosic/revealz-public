# revealz-online

Godot 4 턴제 카드 게임과, 그 게임을 실제로 굴리기 위한 로비·메타·운영 스택을 1인이 함께 만든 프로젝트입니다.

| 항목 | 내용 |
|------|------|
| 기간 | 2025 ~ 진행 중 |
| 인원 | 1인 개발 (클라이언트 · 서버 · 인프라 · 운영) |
| 상태 | **MVP** — 수집 → 덱 편성 → 온라인 대전으로 이어지는 핵심 루프가 실제 서버에서 동작 |
| 공개 범위 | 게임·서버·인프라 소스 및 자체 제작 에셋 / 시크릿·실서버 주소·Dedicated 바이너리 제외 |

> 이 레포는 원본 비공개 레포에서 **공개 가능한 범위만 추려 내보낸 사본**이라 커밋 이력이 하나로 정리되어 있습니다.

---

## 이 레포에서 볼 수 있는 것

게임 하나를 만드는 데서 끝내지 않고, **서비스로 굴러가게 만드는 부분까지** 직접 붙인 것이 이 프로젝트의 핵심입니다. 크게 두 축으로 보시면 됩니다.

**게임 축 — 클라이언트**
- 라인별 파워를 겨루어 **2개 이상의 라인에서 승리**하면 이기는 턴제 카드 게임
- 카드 수집 · 팩 오픈 연출 · 덱 편성 · 싱글 플레이 · 온라인 대전
- 서버 권위(server-authoritative) 매치 세션, 매칭 로딩·대전 연출 UI

**서버 · 운영 축**
- Node.js 로비: 매칭 큐, 전용 서버(Dedicated) 프로세스 spawn, warm 풀, 덱 검증
- PostgreSQL 메타 DB: 계정 · 골드 · 보유 카드 · 상점 카탈로그 · 선물함
- Docker Compose 기반 스택 구성, GitHub Actions CI, health poller
- 토큰으로 보호되는 운영 화면: 모니터링, 점검(maintenance), 계정 조치, DB 백업/복구, 패치노트

---

## 플레이 · 기능

### 인게임

3개 라인에 카드를 배치하고 파워를 겨룹니다. 카드 효과가 라인 파워와 서로의 배치에 개입하기 때문에, 어느 라인을 버리고 어느 라인을 가져갈지 고르는 것이 핵심입니다.

<img src="docs/media/play.png" alt="인게임 보드" width="720"/>

<img src="docs/media/play.gif" alt="플레이" width="720"/>

### 덱 편집

보유 카드 기준으로 덱을 구성합니다. 포맷별 규칙 검증은 클라이언트뿐 아니라 **로비 서버에서도 다시 검사**해서, 조작된 덱으로 매치에 들어오지 못하게 막습니다.

<img src="docs/media/edit.png" alt="덱 편집" width="720"/>

### 상점 · 팩 오픈

가격·확률·카드 풀은 클라이언트가 아니라 **DB의 상점 카탈로그**에 있습니다. 클라이언트는 "어떤 상품을 몇 개 산다"만 보내고, 실제 차감과 뽑기는 서버 트랜잭션 안에서 처리됩니다.

<img src="docs/media/shop.png" alt="상점" width="720"/>

<img src="docs/media/pack_open.gif" alt="팩 오픈" width="720"/>

### 온라인 매치

<img src="docs/media/match.gif" alt="온라인 매치" width="720"/>

---

## 아키텍처

```text
       ┌──────────────── HTTP (로비 · 메타 · 운영) ────────────────┐
       │                                                          │
클라이언트 (Godot) ──── 매칭 요청 ────▶ 로비 서버 (Node.js) ──spawn──▶ 전용 서버 (Godot headless)
       │                                     │                            ▲
       └───────────── UDP / ENet ────────────┼────────────────────────────┘
                                             │
                                    PostgreSQL (메타 DB)

health poller ──주기적 /v1/health──▶ health.jsonl ──▶ /ops 모니터 화면
```

- **HTTP와 UDP를 분리**했습니다. 로비·계정·상점 같은 메타 요청은 HTTP로, 실제 대전 중의 잦은 상태 교환은 지연에 민감하므로 UDP(ENet)로 처리합니다.
- **매칭**: 큐에 들어온 두 명이 짝지어지면 로비가 전용 서버 프로세스를 띄웁니다. 이때 프로세스가 살아 있는 것만으로 접속 가능하다고 보지 않고, 서버가 실제로 포트를 열었다는 로그를 확인한 뒤에야 클라이언트에 접속 정보를 내려줍니다. 빈번한 대기 시간을 줄이기 위해 미리 띄워두는 warm 풀도 함께 씁니다.
- **배포 경계**: GitHub Actions는 검사(CI)와 VM에서의 `git pull`까지만 담당하고, 컨테이너 재기동은 수동 단계로 남겨 두었습니다. 대전이 진행 중인 상태에서 자동 재시작이 끼어드는 상황을 피하기 위한 의도적인 선택입니다.

---

## 운영

혼자 만든 게임이라도 서버에 올라가는 순간 "지금 정상인가", "문제가 생기면 무엇을 할 수 있는가"에 답할 수단이 필요합니다. 그래서 관측 → 점검 → 조치 → 복구까지의 도구를 함께 만들었습니다.

### 모니터링

poller가 주기적으로 `/v1/health`를 찔러 결과를 JSON Lines로 쌓고, 운영 화면이 이를 시계열로 보여줍니다.

<img src="docs/media/ops_overview.png" alt="운영 모니터" width="720"/>

### 점검 (maintenance)

운영 화면에서 점검을 켜면 게임 클라이언트가 즉시 점검 안내로 전환됩니다. 서버 쪽 스위치 하나가 실제 게임 진입을 막는 구조라, 긴급 상황에서 배포 없이 유입을 끊을 수 있습니다.

<img src="docs/media/ops_maintenance.png" alt="점검 전환" width="860"/>

### 백업 · 복구

점검을 건 상태에서 `pg_dump`로 스냅샷을 남기고, 필요하면 목록에서 골라 복구합니다.

<img src="docs/media/maintenance_panel.png" alt="점검 · 백업" width="600"/>

### 계정 조치 · 지급 · 패치노트

계정 조회·삭제, 카드/재화 지급(선물함 경유), 패치노트 게시를 운영 화면에서 처리합니다.

<img src="docs/media/accountmanage_panel.png" alt="계정 관리" width="600"/>

관련 코드: [`lobby/ops_db.html`](lobby/ops_db.html), [`lobby/ops_http.js`](lobby/ops_http.js), [`lobby/meta/ops.js`](lobby/meta/ops.js), [`tools/ops.py`](tools/ops.py)

---

## 담당 역할

1인 개발이라 아래 전 범위를 직접 설계·구현했습니다.

| 영역 | 주요 내용 |
|------|-----------|
| 게임 클라이언트 (Godot) | 턴·카드 효과·덱·팩 오픈·매치 UI 및 연출, 서버 권위 세션 |
| 멀티플레이 연동 | 로비 HTTP 매칭 → ENet(UDP) 접속, 방 코드 및 랜덤 매칭 |
| 로비 · 메타 서버 (Node.js) | 매칭 큐, 전용 서버 spawn·warm 풀, 덱 검증, 구매 트랜잭션, revision 충돌 처리 |
| 데이터 (PostgreSQL) | 스키마 설계, 상점 카탈로그, 선물함, 백업/복구 |
| 인프라 · 운영 | Docker Compose, GitHub Actions, health poller, 운영 화면 |

---

## 기술 스택

| 영역 | 스택 |
|------|------|
| Client | Godot 4.5, GDScript |
| Lobby / Meta | Node.js (내장 `http` 모듈), JavaScript, PostgreSQL 16 |
| Ops | Python (health poller, ops CLI), HTML 운영 UI |
| Infra | Docker Compose, GitHub Actions |
| Network | HTTP (로비 · 메타 · 운영) + UDP / ENet (전용 서버) |

---

## 코드 리뷰 가이드

처음 보시는 분이 짧게 훑을 수 있도록, 성격별 진입점을 정리했습니다.

### 서버 · 운영

| 보고 싶은 것 | 경로 |
|--------------|------|
| 매칭 큐 · 전용 서버 spawn · warm 풀 · 준비 판정 | [`lobby/server.js`](lobby/server.js) |
| 메타 API · revision 충돌 · 계정 상태 | [`lobby/meta/routes.js`](lobby/meta/routes.js) |
| 구매 트랜잭션 · 확률 뽑기 (서버 권위) | [`lobby/meta/purchase.js`](lobby/meta/purchase.js) |
| 상점 카탈로그 · 선물함 | [`lobby/meta/shop_catalog.js`](lobby/meta/shop_catalog.js), [`lobby/meta/mailbox.js`](lobby/meta/mailbox.js) |
| 서버 측 덱 검증 | [`lobby/meta/validate_deck.js`](lobby/meta/validate_deck.js) |
| 운영 라우팅 · 모니터 · 점검/백업 | [`lobby/ops_http.js`](lobby/ops_http.js), [`lobby/meta/ops.js`](lobby/meta/ops.js) |
| DB 스키마 | [`lobby/meta/schema.sql`](lobby/meta/schema.sql) |
| health poller | [`tools/ops_health_poll.py`](tools/ops_health_poll.py) |
| CI / VM 배포 | [`.github/workflows/`](.github/workflows/) |
| 스택 구성 | [`docker-compose.yml`](docker-compose.yml) |

### 클라이언트

| 보고 싶은 것 | 경로 |
|--------------|------|
| 전용 서버 진입점 (headless) | [`scripts/server_main.gd`](scripts/server_main.gd) |
| ENet 접속 · 호스트 | [`scripts/network_manager.gd`](scripts/network_manager.gd) |
| 서버 권위 매치 세션 | [`scripts/server_authority_session.gd`](scripts/server_authority_session.gd) |
| 메타 동기화 · 점검 게이트 | [`scripts/meta/meta_sync.gd`](scripts/meta/meta_sync.gd) |
| 카드 카탈로그 로딩 | [`scripts/card_registry.gd`](scripts/card_registry.gd) |
| 온라인 준비 · 매칭 UI | [`scenes/screen/online_prepare_screen.gd`](scenes/screen/online_prepare_screen.gd) |
| 덱 편집 · 상점 · 선물함 | [`scenes/screen/deck_editor_screen.gd`](scenes/screen/deck_editor_screen.gd), [`scenes/screen/shop_screen.gd`](scenes/screen/shop_screen.gd), [`scenes/screen/mailbox_screen.gd`](scenes/screen/mailbox_screen.gd) |

### 기술적 문제 해결 (포트폴리오 항목 ↔ 코드)

별도 포트폴리오에 서술한 문제 해결 과정이 어느 코드에 해당하는지 대응표입니다.

| 문제 | 관련 코드 |
|------|-----------|
| 매칭은 성사되는데 접속은 실패하던 전용 서버 준비 판정 | [`lobby/server.js`](lobby/server.js), [`scripts/server_main.gd`](scripts/server_main.gd) |
| 매치 워커 콜드스타트 — 카드 로딩을 부팅 임계 경로에서 제거 | [`scripts/card_registry.gd`](scripts/card_registry.gd), [`scripts/server_main.gd`](scripts/server_main.gd) |
| 클라이언트를 믿던 경제 로직의 서버 권위 전환 | [`lobby/meta/purchase.js`](lobby/meta/purchase.js), [`lobby/meta/routes.js`](lobby/meta/routes.js), [`scripts/meta/meta_sync.gd`](scripts/meta/meta_sync.gd) |
| 라이브 서비스 운영 체계 — 배포 경계 · 관측 · 점검 | [`.github/workflows/`](.github/workflows/), [`tools/ops_health_poll.py`](tools/ops_health_poll.py), [`lobby/ops_http.js`](lobby/ops_http.js), [`lobby/meta/ops.js`](lobby/meta/ops.js) |

설계 배경과 트레이드오프 기록: [`docs/server_authority_decisions.md`](docs/server_authority_decisions.md)

---

## 로컬 실행

### 게임 클라이언트

1. [Godot 4.x](https://godotengine.org/) 설치
2. 레포를 clone 한 뒤 `project.godot` 열기
3. F5 실행 — 싱글 플레이, 덱 편집, UI 흐름은 로비 없이도 확인 가능

온라인 매칭은 로비 서버와 전용 서버 바이너리가 필요합니다. 바이너리는 이 레포에 **포함하지 않습니다**.

### 로비 서버

```bash
cd lobby
cp .env.example .env
npm ci
npm start
```

- 기본 주소는 `http://127.0.0.1:8080`
- `GET /v1/health` 로 상태 확인
- 메타 DB를 쓰려면 PostgreSQL과 `META_DATABASE_URL` 설정이 필요합니다 (Compose 참고)

### Docker Compose (로비 + DB + poller)

```bash
cp lobby/.env.example lobby/.env
docker compose up -d
```

자세한 내용: [`lobby/README.md`](lobby/README.md)

---

## 공개 범위 · 저작권

- 게임 코드, 로비·메타 서버, 인프라 설정: **전부 본인 작성**
- 카드 일러스트: **AI 생성(NovelAI) 후 자체 편집**하여 사용
- 전 직장·타사 소스코드 및 무단 에셋 **미포함**
- 실서버 IP, 운영 토큰, 전용 서버 바이너리 **미포함**
- 스크린샷의 보유 골드는 상점·구매 API 테스트를 위해 임의로 부여한 값입니다. 골드 수급 구조(퀘스트·보상 등)는 아직 확정 전입니다.

---

## 앞으로

핵심 루프가 도는 MVP 단계이고, 다음 두 방향으로 계속 다듬고 있습니다.

- **내부**: 선물함·프로필 등 메타 기능 확장, 운영 화면에서의 상점 카탈로그 편집(현재는 DB 직접 수정), 매칭·워커 운용 개선
- **외부**: 카드 밸런스와 룰 조정 — 카드 데이터와 상점 카탈로그가 코드가 아닌 데이터에 있어 클라이언트 재배포 없이 조정 가능

내용은 개발 진행에 따라 언제든지 변경될 수 있습니다.
