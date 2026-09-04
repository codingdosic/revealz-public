# 서버 권위 전환 — 단계별 구현 계획

의사결정 배경: [`server_authority_decisions.md`](./server_authority_decisions.md)

**브랜치:** `feature/server-authority`  
**전제:** 서버가 정답 · 오프라인 모드 없음 · 로컬 파일은 캐시만

---

## 단계 요약

| 단계 | 목표 | Done 기준 |
|---|---|---|
| **0** | DB 상품/설정 테이블 + 시드 + URL 설정 확인 | ✅ |
| **1** | Meta 없으면 진입 불가 | ✅ |
| **2** | 상점·돈 = DB + 서버 TX | ✅ 핵심 (ops CRUD 보류) |
| **3** | 온라인 덱 검증 | ✅ 소스 완료 · Dedicated 바이너리 배포는 잔여 |
| **4** | 프로필 서버 단일 | ✅ |
| **5+** | 티켓·보상·audit 등 | 2차 (아래) |

---

## 잔여 작업 (1차 마무리 + 2차)

### A. 1차 마무리 (코드/배포)

| # | 항목 | 설명 | 우선 |
|---|---|---|---|
| A1 | **Dedicated Linux export → VM scp → lobby restart** | 3·4단계(덱 validate, Meta 프로필)가 **프로덕션 Dedicated**에 반영됨. Host/에디터는 소스만으로 동작. 절차: [`SERVER_OPS.md`](../SERVER_OPS.md) §4 | 높음 |
| A2 | **ops/db 상품 CRUD UI** | `shop_products`를 ops 페이지에서 수정. 지금은 SQL/시드만. 가격·풀 운영 변경용 | 중 |
| A3 | **PR → main 머지** | `feature/server-authority` 리뷰 후 merge. VM은 pull + `docker compose build lobby && up` | 중 |
| A4 | (선택) PUT 스냅샷 추가 축소 | wallet/owned 클라 PUT 경로 더 줄이기. 구매·프로필은 이미 전용 API | 낮 |

### B. 2차 (합의에서 보류)

| # | 항목 | 설명 | 의존 |
|---|---|---|---|
| B1 | **Lobby ticket ↔ accountKey** | 매칭 티켓에 계정·덱 묶기. INTENT `accountKey` 스푸핑 완화 | Lobby 스펙 |
| B2 | **매치 후 보상 Meta TX** | 승패 → Meta 지급, idempotency key | Match→Meta |
| B3 | **config audit / draft·publish** | ops 변경 이력, staging→publish | A2 |
| B4 | **Acc1 AuthProvider** | 게스트 외 로그인. accountKey 불변 가정 유지 | 별 프로젝트 |
| B5 | **Blue-Green / Tunnel Runbook** | Meta/Lobby drain, Match는 worker 공인 IP 유지 | 인프라 |
| B6 | (선택) Host vs Dedicated 정책 | 랭크=Dedicated only 등 운영 분리 | 정책 |

### C. 명시적 비범위 (당분간)

- 선물함 / AI / 소셜 / 게임 로그 DB  
- 전면 anti-cheat / Spectrum·relay  
- Acc1 전체 설계 문서화 이상의 구현  

---

## 0~4 구현 요약 (참고)

| 단계 | 산출 |
|---|---|
| 0 | `shop_products` / `app_config`, `seed_shop.sql`, `shop_catalog.js` |
| 1 | Meta 필수 게이트 (싱글·덱·멀티·상점) |
| 2 | `GET /v1/shop/catalog`, purchase DB lookup, 악세 TX, 클라 fallback 제거 |
| 3 | `validate_deck_owned_async` 공유, Host+Dedicated 필수, skip 제거 |
| 4 | `POST .../profile`, 매치 표시명·아이콘 = Meta 스냅샷 |

상세 의사결정: [`server_authority_decisions.md`](./server_authority_decisions.md)
