# FairRail ERD v6 — 팀 2차 검토 반영 기록

2차 검토 의견(P0 3 · P1 4 · P2 3)을 스키마 v6로 반영한 기록입니다. 최신 전체 명세는 `docs/FairRail_ERD.md`를 보세요.

| # | 검토 의견 | 반영 내용 |
|---|---|---|
| A | 결제 중 HOLD 만료 | `HOLD → PAYMENT_PENDING` 조건부 UPDATE가 1행일 때만 마감을 한 번 연장(PG 타임아웃 + 여유). 같은 트랜잭션에서 `reservation.pay_deadline_at`·`seat_inventory.hold_expires_at`·`saga_instance.timeout_at`, 커밋 후 Redis `seat:hold` TTL. PG 호출 전 소유·만료 재확인. 늦은 승인 환불은 마지막 안전망 |
| B | outbox 병렬 순서 | `outbox_event.shard_no` (INSERT 시 `ORA_HASH(:partition_key, 15)`, CHECK 0~15). 샤드 16개 고정, 인스턴스는 `shard_no MOD 인스턴스 수`로 담당. 부분 인덱스 2열. 커서 fetch(FETCH FIRST·ROWNUM 미사용), 멱등 프로듀서, FAILED 의미 명시 |
| C | 예매 흐름 순서 | reservation_id 발급 → Redis 전 구간 SET NX(패배자 DB 쓰기 0건) → 승자만 한 트랜잭션에서 reservation → seat_inventory → purchase_counter |
| D | FK·인덱스 과다 | seat_inventory 단일 FK는 v5에서 이미 DDL 제외(확인). 행을 지우지 않는 station·route·car_type을 `refOnly`로 지정해 이를 가리키는 FK 인덱스 생략. `ix_resv_ci_run` 제거(재집계는 오프피크 풀스캔). 인덱스 54 → 42 |
| E | purchase_counter 보강 | `CHECK(seat_count >= 0)`, 증가는 reservation INSERT와 같은 트랜잭션, 감소는 예약 상태 UPDATE 1행일 때만, PER_RUN → PER_HOLIDAY 순서 고정, 최초 INSERT의 `n ≤ max`와 ORA-00001 재시도, sale_event_id NULL이면 PER_HOLIDAY 미적용 |
| F | Mongo TTL | `replay_event`·`behavior_log`에 `expire_at` + `TTL { expire_at: 1 }, expireAfterSeconds: 0`. legal_hold면 `expire_at` 제거 |
| G | 마감 시각 중복 | `reservation.pay_deadline_at`을 원천으로, 나머지 4곳은 복사 규칙을 컬럼 설명과 공통 규칙에 명시 |
| P2 | updated_at | 진짜 문제(값이 거짓)에 맞춰 규칙화: JPA Auditing + 비고의 네이티브 조건부 UPDATE마다 `updated_at = SYSTIMESTAMP` |
| P2 | Redis 클러스터 | 단일 노드 전제를 결정 사항에, 클러스터 전환 시 해시 태그 키 규칙을 `redis_keys` 비고에 |
| P2 | 문서 불일치 | 시나리오의 스캐너 표현을 부분 인덱스로 수정, `processed_event` 정리 인덱스 + `inbox.retention_days` |

## 반영 중 바꾼 판단

| 항목 | 내용 |
|---|---|
| shard_no를 가상 컬럼 대신 일반 컬럼으로 | 가상 컬럼을 CASE 부분 인덱스 안에서 참조하는 조합은 실행 계획 확인이 추가로 필요해, INSERT 문에서 ORA_HASH로 계산해 넣는 일반 컬럼 + CHECK로 단순화 |
| 새 op `samples+` | app_policy 새 키를 추가할 때 기존 예시 행(팀원이 고친 값 포함)을 덮어쓰지 않도록, PK가 없는 행만 추가 |

## 규모

| 항목 | v5 | v6 |
|---|---|---|
| 테이블 | 60 | 60 |
| 컬럼 | 494 | 497 |
| DDL CHECK | 61 | 63 |
| DDL 인덱스 | 54 | 42 |
| 예시 INSERT | 30 | 35 |
