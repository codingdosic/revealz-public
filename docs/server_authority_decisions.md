# 서버 권위 전환 — 의사결정 기록

> **목적:** revealz에서 “클라이언트를 믿을 수 있는 정보”와 “서버만 알아야 하는 정보”의 경계를 정하고, 변조·불일치를 막기 위한 방향을 문서로 남긴다.  
> **상태:** 1차 합의 완료 (구현 전)  
> **기준 커밋:** `e3ef0e3` — 서버 권위 작업 시작 전 백업  
> **구현 계획:** 대화에서 정리한 0~5단계 로드맵 (별도 진행)

---

## 1. 배경 — 왜 이 작업이 필요했는가

### 1.1 당시 구조

- **Godot 클라이언트** — UI, 입력, 로컬 파일(`wallet.json`, `collection/owned.json`, 상점 `.tres` 등)
- **Meta (Postgres + HTTP)** — 계정, 골드, 보유, 구매, ops grant, 덱 검증 API
- **Lobby (HTTP)** — 방 코드, 매칭, Dedicated 워커 할당
- **Match (Dedicated / Host, ENet)** — 턴, 보드, 승패 등 **인게임 규칙**

Acc0 단계에서는 **게스트 계정**만 있고, Meta가 없거나 실패하면 **로컬 파일로 폴백**하는 경로가 여러 곳에 남아 있었다.

### 1.2 발견된 문제

| 문제 | 쉬운 설명 | 위험 |
|---|---|---|
| **로컬이 “정답”처럼 동작** | Meta OFF여도 wallet·보유를 클라가 읽고 쓸 수 있음 | 돈·카드 조작, 온라인과 불일치 |
| **구매는 서버 TX지만 가격은 클라가 정함** | `purchase` API에 `price_gold`, `pool`, `weight`를 클라가 body로 보냄 | 0원 구매, 풀 조작 |
| **악세서리 구매는 로컬만** | 치장품은 Meta TX 없이 `WalletStore` + 로컬 grant | 골드·보유 우회 |
| **덱 검증이 Dedicated만, 실패 시 skip** | Host는 validate 없음; Meta down이면 검증 생략 가능 | 없는 카드 덱, 계정 key 주장 |
| **프로필·표시명** | INTENT_DECK에 실은 displayName을 UI가 그대로 쓸 수 있음 | 이름·아이콘 스푸핑 |
| **클라 스냅샷 PUT** | Store 저장 시 로컬 → Meta PUT | 서버 경제 데이터를 클라가 덮어쓸 여지 |
| **상품 카탈로그가 `.tres`** | 가격·풀이 빌드/리소스에 묶임 | ops에서 가격 변경 불가, 클라·서버 이중 관리 |

인게임 **배치·효과·승패**는 이미 Dedicated/Host 권위(intent 패턴)로 잘 분리되어 있었고, **경제·보유·입장·카탈로그** 쪽이 약했다.

### 1.3 이번 작업의 목표 (범위)

- **한 번에 전부 이전하지 않음** — “누가 정답인지” 구조와 1차 전환만
- **제외:** Acc1 로그인 전체, 선물함, AI, 소셜, 매치 보상 DB, 대규모 코드 리팩 한 번에

---

## 2. 최상위 전제 — 무엇을 먼저 확정했는가

### 문제

로컬 폴백과 서버 권위를 동시에 유지하면, Store·상점·온라인마다 “지금은 누가 맞나?” 분기가 늘어나고 테스트·버그가 반복된다.

### 선택지

| 선택 | 설명 |
|---|---|
| **A. 하이브리드 유지** | Meta OFF면 싱글·로컬 상점 계속 (현행 확장) |
| **B. 서버 권위 우선 + 오프라인 모드 비활성** | Meta 연결·동기화 실패 시 주요 기능 진입 불가 |
| **C. 완전 always-online** | 싱글까지 서버 필수 (연습장 로컬 sim 없음) |

### 채택

**B + C** (실질적으로 동일): **서버 권위 우선, 오프라인 모드 비활성.**

- Meta health + GET 스냅샷 **성공 필수** — 실패 시 메뉴·상점·온라인·**싱글 포함** 진입 차단
- 로컬 파일(`wallet.json` 등)은 **캐시만** — 서버와 다르면 **항상 서버가 이김**
- guest 404 → 1회 migrate PUT은 **유지** (기존 유저 이관), 이후 서버 only

### 이유

- live ops 게임과 같이 **“온라인일 때 클라 origin 쓰기 금지”**를 코드 한 벌로 통일할 수 있음
- 0원 구매·로컬 골드 같은 구멍을 **fallback 제거**로 같이 닫기 쉬움
- Acc0 guest → Acc1 Auth 전환 시에도 **“서버가 정답”** 원칙은 그대로 유지

---

## 3. 권위를 세 덩어리로 나눔

### 문제

계정·돈·매칭·보드·승패를 한곳에서 처리하면 역할이 섞이고, 나중에 Tunnel·Blue-Green·Dedicated 스케일 시 같이 흔들린다.

### 선택지

| 선택 | 설명 |
|---|---|
| **한 서버에 전부** | Meta + Lobby + 게임 로직 한 프로세스 |
| **三 권위 분리** | Meta / Lobby / Match 각각 SoT |
| **외부 BaaS (PlayFab 등)** | 상품화된 백엔드 |

### 채택

**三 권위 분리** (기존 아키텍처 유지·명확화)

| 권위 | 맞는 것 (SoT) | 클라 역할 |
|---|---|---|
| **Meta** | 계정, 골드, 보유, 구매 TX, 프로필, ops grant | 스냅샷 수신·표시; 변경은 **요청**만 |
| **Lobby** | 매칭 ticket, room, worker, host:port | 입장·매칭 **요청** |
| **Match** | 턴, 보드, RNG(매치 내), 승패 | intent 전송; 이벤트로 UI 동기화 |

### 이유

- 이미 `OnlineAuthoritySessionBase`, `MetaSync`, `lobby/server.js`로 **나뉘어 구현**되어 있음
- Cloudflare Tunnel 등은 **Meta/Lobby HTTP**와 **Match UDP**를 **다르게** 다루는 게 일반적 → 분리가 인프라 대응에 유리
- 일반 멀티플레이 운영 게임의 **축소·실용판**과 같은 형태

---

## 4. 데이터별 “누가 믿을 수 있는가” (신뢰 경계)

각 항목마다 **CLIENT_OK** / **SERVER_VERIFY** / **SERVER_ONLY** 중 하나로 분류했다.

- **CLIENT_OK** — 순수 UI·오프라인 전용 입력 (이번 전제에서는 경제·온라인에 영향 없음)
- **SERVER_VERIFY** — 클라가 **의도(intent)** 를 보내면 서버가 규칙·보유와 대조
- **SERVER_ONLY** — 확정값; 클라가 origin으로 만들거나 덮어쓰면 안 됨

### 4.1 프로필

| 항목 | 분류 | 문제 | 채택 |
|---|---|---|---|
| accountKey | SERVER_ONLY | 클라가 임의 key 주장 | 서버/게스트 생성만 |
| displayName | SERVER_VERIFY | INTENT에 다른 이름 실음 | Meta 저장 + sanitize; UI는 스냅샷 |
| profileIconId | SERVER_VERIFY | 없는 아이콘 표시 | 보유 악세만 허용 |

### 4.2 지갑·재화

| 항목 | 분류 | 문제 | 채택 |
|---|---|---|---|
| gold 잔액 | SERVER_ONLY | wallet.json 조작 | Meta 스냅샷; 로컬은 캐시 |
| 차감·지급 | SERVER_ONLY | 로컬 try_spend | purchase / ops / grant TX만 |
| SEED_GOLD 로컬 시드 | (폐지) | 오프라인 infinite money | **오프라인 비활성으로 불필요** |

### 4.3 보유·인벤토리

| 항목 | 분류 | 채택 |
|---|---|---|
| owned_cards | SERVER_ONLY | Meta + ops; collection/owned.json은 캐시 |
| ownedAccessories | SERVER_ONLY | 동일 |

### 4.4 덱

| 항목 | 분류 | 문제 | 채택 |
|---|---|---|---|
| 프로필 덱 편집 | SERVER_VERIFY (제출 시) | 없는 카드로 매치 | validate-deck |
| INTENT_DECK accountKey | SERVER_VERIFY | 타 계정 owned 검증 | 1차: Meta validate; 2차: Lobby ticket bind |
| Host 덱 검증 | 없었음 | Host만 우회 | **Dedicated와 동일 validate 필수** |

**validate 실패 시**

| 선택 | 채택 |
|---|---|
| skip (Meta down) | **거부** — 1단계에서 Meta 필수이므로 skip 불필요 |
| 매치 거부 + UX | **채택** |

### 4.5 인게임

| 항목 | 분류 | 비고 |
|---|---|---|
| PLACE, EFFECT_DECISION, FORFEIT | SERVER_VERIFY | **기존 유지** |
| 보드·턴·승패 | SERVER_ONLY | **기존 유지** |

### 4.6 매치 결과·보상

| 항목 | 1차 | 이유 |
|---|---|---|
| 승패 표시 | SERVER_ONLY (Match 이벤트) | 이미 권위가 결정 |
| 매치 후 골드·카드 보상 | **1차 제외** | API·idempotency 설계 필요; 범위 통제 |

### 4.7 로비

| 항목 | 분류 |
|---|---|
| roomCode, host, port | SERVER_ONLY |
| ticket / account bind | **2차** (Lobby 스펙) |

---

## 5. 상점·카탈로그 — 별도로 확정한 결정

### 문제

“구매는 Meta TX”라도 **클라가 보낸 가격·pool**을 서버가 그대로 쓰면 (`purchase.js`의 `body.price_gold`, `body.pool`) **카탈로그 권위가 클라**에 있다. `.tres`에서 `price_gold`를 바꾸면 그대로 적용되는 상태였다.

### 선택지

| 선택 | 설명 |
|---|---|
| **A. DB catalog + purchase는 product_id만** | 가격·풀·weight는 Postgres; ops/db에서 CRUD |
| **B. 클라 body 유지 + 서버 catalog와 대조** | API 두꺼움, 이중 관리 |
| **C. Git JSON + CI 배포** | 가격 변경마다 배포 |
| **D. Remote Config SaaS** | Firebase 등 |
| **E. 2차로 미룸** | ① 악세 TX만 먼저 → pool·0원 구멍 유지 |

### 채택

**A (1차 포함)**

- `shop_products`, `app_config` 등 **Postgres config**
- **ops/db 페이지**에서 기획·운영이 수정 (audit·publish는 2차)
- `GET /v1/shop/catalog` — UI 가격 표시
- `POST purchase` — **`product_id` + `pack_count`만**; 서버가 DB lookup
- 클라 `.tres` — **이름·아이콘·설명만** (표시용)

### 다른 “정석”과의 관계

- PlayFab·Steam IAP = **저장소+UI를 제공하는 상품화된 형태**
- **DB + ops admin** = 그것의 **자체 Meta 규모 버전**으로 live ops에서 흔함
- Google Sheet → DB, Git config, Remote Config는 **팀·규모 커질 때 A 위에 얹는 변형** — 1차는 A로 충분

### 이유

- ops grant·DB 페이지 **이미 존재** — 카탈로그도 같은 패턴
- 가격 변경 **배포 없이** 가능
- 서버 권위·오프라인 비활성과 **같은 스프린트**에 넣어야 economy 구멍이 한 번에 닫힘

---

## 6. 동기화·PUT·충돌

### 문제

`MetaSync` + Store `save` → `push_snapshot`은 편하지만, Meta ON 상태에서 **클라 origin으로 wallet/owned를 PUT**하면 서버 권위와 충돌한다.

### 선택지

| PUT 정책 | 설명 |
|---|---|
| **전면 축소** | migrate·제한적 프로필만 PUT; 경제는 TX만 |
| **당분간 PUT 유지** | applying_remote + 서버 wins |
| **GET only** | 모든 변경 API화 |

### 채택

**목표: 전면 축소 / 1차: 구매·골드 경로부터 PUT 제거**

- 409 revision 충돌 → **서버 스냅샷 무조건 적용** + 토스트
- migrate(404 PUT) → **유지** (1회 이관)

### 이유

- “서버 wins” 전제와 코드 경로를 **일치**시키기 위함
- 한 번에 GET only로 가면 Store 전면 개편; **구매 TX부터** 단계적으로

---

## 7. Host vs Dedicated

### 문제

Dedicated만 `validate-deck`; Host는 우회. “온라인 = 공정” 목표와 맞지 않음.

### 선택지

| 선택 | 설명 |
|---|---|
| **A. 둘 다 동일 검증** | Host + Dedicated validate |
| **B. Dedicated만 공식** | Host는 친구대전만, 또는 제거 |
| **C. Host 단계적 폐지** | 1차 A, 장기 B |

### 채택

**1차: A** — Host/Dedicated **동일 validate, 실패 시 매치 거부**  
**장기:** 랭크·공식 매칭은 Dedicated only (**B**) 검토 — 운영 정책 이슈

### 이유

- 구현 비용 낮음 (Dedicated G3.1 재사용)
- 오프라인 Meta 없음 → validate skip 제거 가능

---

## 8. 인증·세션 (Acc0 / Acc1)

### 문제

`INTENT_DECK`의 `accountKey`를 클라가 보내면, **다른 계정의 owned**를 주장할 여지 (validate가 있어도 표시·로그 혼선).

### 선택지

| 선택 | 시기 |
|---|---|
| **A. accountKey + Meta validate** | 1차 |
| **B. Lobby ticket에 account·deck bind** | 2차 |
| **C. Acc1 JWT 전면** | Acc1 프로젝트 |

### 채택

**1차 A, 2차 B** — Acc1 전체 설계는 **범위 외**; guest `accountKey` = Meta PK **가정 유지**

---

## 9. 인프라 (Tunnel, Blue-Green)

### 문제

Meta/Lobby를 공개 IP에 두면 운영·보안 부담. 게임 UDP는 HTTP Tunnel과 다름.

### 선택지

| 레이어 | 일반적 선택 |
|---|---|
| Meta/Lobby | CF Tunnel, WAF, Blue-Green |
| Match | worker 공인 IP, Spectrum, relay |

### 채택 (1차)

- Meta/Lobby URL **env 설정화** (Tunnel hostname 대비)
- Match는 **Lobby가 준 host:port 직접 ENet** 유지
- Blue-Green drain, maintenance → **health gate 확장** (2차 Runbook)

### 이유

**三 권위 분리** 덕분에 HTTP만 edge에 올리고 Match는 별도 — **초안 수정 없이** 대응 가능

---

## 10. 일반 live ops 게임과의 차이 (의도적)

| 항목 | revealz 1차 | 대형 F2P (의도적 차이) |
|---|---|---|
| Auth | guest accountKey | JWT / 플랫폼 로그인 |
| Catalog | DB + ops | + Sheet pipeline, A/B |
| Match reward | 없음 | Result service |
| Host | 1차 유지 + validate | Ranked = Dedicated only |
| Anti-cheat | intent 검증 | + attestation |
| Offline | **없음** | often always-online anyway |

**“틀린 구조”가 아니라 “운영 게임의 축소·실용판”** — gap은 **세션 토큰, catalog DB, POST-match, Host 정책**으로 메우는 순서.

---

## 11. 1차 구현에서 하지 않기로 한 것

| 항목 | 이유 |
|---|---|
| Acc1 AuthProvider 교체 | 별 프로젝트 |
| 선물함 / AI / 소셜 / 게임 로그 DB | 범위 밖 |
| 매치 후 보상 Meta TX | idempotency·설계 필요 |
| Lobby ticket ↔ accountKey | Lobby 스펙·2차 |
| config audit / draft-publish | ops 고도화·2차 |
| Full anti-cheat | 규모·우선순위 |

---

## 12. 단계별 구현 순서 — 왜 이 순서인가

| 단계 | 내용 | 선행 이유 |
|---|---|---|
| **0** | DB schema, shop 시드, URL 설정 | catalog·구매의 바닥 |
| **1** | Meta 필수 게이트, 409, offline 제거 | “서버 wins” 전제를 진입부터 강제 |
| **2** | catalog GET, purchase lookup, ops CRUD, fallback 제거 | **0원·pool 조작** 구멍 |
| **3** | Host validate, skip 제거 | 온라인 덱 공정성 |
| **4** | 프로필 Meta 단일 | 표시 스푸핑 |
| **5** | ticket, match reward, audit… | 1차 Done 이후 |

**1 → 2 → 3** 순: Meta 없으면 상점·validate 의미가 애매해지므로 **게이트가 먼저**.

---

## 13. 1차 완료 정의 (합의)

- [ ] Meta OFF → 플레이·상점·싱글 **진입 불가**
- [ ] 상품 가격·구매 = **DB + 서버 TX only** (클라 price/pool 무시)
- [ ] ops/db에서 상품 수정 → 게임 반영
- [ ] Dedicated **+ Host** 덱 검증 실패 → **매치 불가**
- [ ] 골드·보유 UI = 서버 스냅샷
- [ ] guest migrate · ops grant **회귀 없음**

---

## 14. 관련 문서·코드 (참고)

| 대상 | 위치 |
|---|---|
| Meta 동기화 | `scripts/meta/meta_sync.gd` |
| 구매 (클라 body) | `scripts/shop/shop_service.gd` |
| 구매 (서버) | `lobby/meta/purchase.js` |
| 덱 검증 | `lobby/meta/validate_deck.js`, `scripts/server_authority_session.gd` |
| Lobby | `lobby/server.js`, `lobby/README.md` |
| 백업 커밋 | `e3ef0e3` |

---

## 15. 구현 진행 상태

| 단계 | 상태 | 내용 |
|---|---|---|
| **0** 준비 | **완료** | `shop_products` / `app_config` 스키마, `.tres` 시드, `shop_catalog.js` 읽기 헬퍼, URL은 env + ProjectSettings 유지 |
| **1** Meta 게이트 | **완료** | `can_use_online` = Meta 필수; 싱글·덱·멀티·상점 진입 게이트; `_cache_without_meta`도 전면 차단 |
| **2** 상점 TX | **핵심 완료** (ops CRUD 보류) | GET catalog, purchase DB lookup, 악세 TX, 클라 fallback 제거 |
| **3** 덱 검증 | **완료** | Host+Dedicated validate 필수, Meta fail skip 제거 |
| **4** 프로필 | **완료** | POST /profile, 매치 UI는 Meta 스냅샷 이름·아이콘 |
| **5+** | 보류 | 잔여·2차는 [`server_authority_plan.md`](./server_authority_plan.md) |

**브랜치:** `feature/server-authority`  
**잔여 SSOT:** [`server_authority_plan.md`](./server_authority_plan.md) §잔여 작업

---

## 16. 변경 이력

| 날짜 | 내용 |
|---|---|
| 2026-09-02 | 1차 합의·의사결정 문서 작성 (구현 전) |
| 2026-09-03 | 0단계 착수 — DB catalog 스키마·시드·헬퍼 |
| 2026-09-03 | 1단계 — Meta 필수 게이트 (싱글 포함) |
| 2026-09-03 | 2단계 핵심 — shop catalog/purchase 서버 SoT (ops CRUD 보류) |
| 2026-09-03 | 3단계 — Host validate + Dedicated skip 제거 |
| 2026-09-03 | 4단계 — 프로필 Meta 단일 (profile API + 매치 표시) |

---

*이 문서는 “왜 이렇게 했는가”를 남기는 것이 목적이다. API 스펙·테이블 DDL·PR 체크리스트는 구현 단계에서 `docs/` 또는 PR 설명에 보완한다.*
