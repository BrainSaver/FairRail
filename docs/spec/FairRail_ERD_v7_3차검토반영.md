# FairRail ERD v7 — 팀 3차 검토 반영 기록

3차 검토(P0 4 · P1 4 · P2 6)를 반영하고, 동시성 절차를 `docs/concurrency.md`로 분리했습니다.

## 구조 변경

- 테이블 비고에 흩어져 있던 SQL 절차를 `docs/concurrency.md` 한 곳으로 모았습니다. 비고에는 제약·인덱스와 `§` 절 번호만 남깁니다.
- 검사 스크립트가 비고·문서의 `§` 번호가 concurrency.md에 실제로 있는지 확인합니다 (25개 참조 확인).

## 반영 결과

| # | 검토 의견 | 반영 (concurrency.md 절) |
|---|---|---|
| 1 | 결제 시작 시 마감 단축 | `GREATEST(기존, 지금 + 타임아웃 + 여유)`, 예시값 PG 180초 + 여유 60초 (§4) |
| 2 | 다좌석 고아 행 | 재선점 시 이전 예약 HOLD일 때만 EXPIRED, 그 예약의 HOLD 행 전부 삭제, 카운터 전체 감소. 결제 중·확정 예약은 재선점 불가. 확정은 구간 수만큼 HOLD→SOLD일 때만 (§3, §5) |
| 3 | 멱등 재시도 자기 충돌 | `idem:{memberId}:{key}` 선조회 후 기존 예약 반환, DB UNIQUE 최종 (§1) |
| 4 | outbox FAILED 순서 | FAILED도 부분 인덱스에 포함하고 샤드 맨 앞이 FAILED면 샤드 정지. 샤드 담당은 Redis 리스. **SKIP LOCKED 대신 FOR UPDATE WAIT** (리스 이동 중 앞 행 건너뛰기 방지). `created_at` NN은 DDL에 이미 있었고 편집기 표시만 맞춤 (§11) |
| 5 | DB 거절 시 Redis 해제 | compare-and-delete 보상, `limit:*` 복원은 SET NX 후 INCRBY (§2.3, §10.4, §14.3) |
| 6 | version 미증가 | 네이티브 UPDATE 규칙에 `version = version + 1` (§0.3) |
| 7 | PG 결과 미확인 만료 | 스캐너는 PAYMENT_PENDING을 PG 조회 후 확정·실패 처리, 결과 모르면 자동 만료 없이 알림 (§6) |
| 8 | 카운터 데드락 | 한 트랜잭션의 카운터 행을 `(scope, scope_ref_id, ci_hash)` 정렬 순서로 (§10.3), 전체 락 순서 규칙 (§0.4) |
| P2 | 확정 취소 카운터 | 감소 (§8) |
| P2 | 취소표 카운터 | 증가, 한도 초과면 `SKIPPED` (§9) |
| P2 | Mongo 보관 | replay_session·queue_log·evidence_snapshot에 `expire_at`, 컨슈머가 legal_hold 확인 (§13) |
| P2 | Redis 클러스터 태그 | `{runId}`·`{ciHash}`로 정정 (§14.4) |
| P2 | outbox 커밋 순서 | reservation 행 갱신 뒤 INSERT + `seq`(`outbox_seq`) 정렬 (§0.5, §11.1) |
| P2 | 흐름 누락 | saga_instance·reservation_history INSERT 시점 명시 (§2.2) |

## 반영 중 추가로 정한 것

| 항목 | 내용 |
|---|---|
| 새 op `samples=` | 예시값을 바꿀 때 PK로 찾아 적은 필드만 덮어씀 (PG 타임아웃 30 → 180) |
| 결정 사항 갱신 | 기존 사용자의 "결제 시작 시 마감 연장" 결정이 아직 "예시"면 새 값으로 바뀜 (`DECISION_REFRESH`) |
| 테스트 목록 | concurrency.md §16에 통합 테스트 23개 |
