# FairRail ERD v5 — 팀 검토 반영 기록

팀 검토 의견 12건(P0 4 · P1 4 · P2 4)을 스키마 v5로 반영한 기록입니다. 최신 전체 명세는 `docs/FairRail_ERD.md`를 보세요.

## 반영 결과

| # | 검토 의견 | 판단 | 반영 내용 |
|---|---|---|---|
| 1 | seat_inventory 열차 불일치 | 그대로 | `seat_inventory.train_id` 추가. 복합 FK `(train_id, seat_id) → seat`, `(run_id, train_id) → train_run`. 참조 대상 `seat UNIQUE(train_id, seat_id)`, `train_run UNIQUE(run_id, train_id)`. 같은 대상을 가리키던 단일 FK 2개는 DDL에서 생략 |
| 2 | HOLD 만료 | 보완 | `hold_expires_at` + 행 CHECK(HOLD면 필수, SOLD면 null) + 부분 인덱스. 재선점 조건부 UPDATE에 두 가지를 더함: 여러 구간은 전부 갱신될 때만 성공(아니면 롤백), 같은 트랜잭션에서 이전 예약 EXPIRED. 늦게 결제한 이전 예약자는 `seat_inventory.reservation_id` 불일치로 거부 |
| 3 | outbox 정리·인덱스 | 개선 | `(status, created_at)` 대신 PENDING만 담는 부분 인덱스. 릴레이 `FOR UPDATE SKIP LOCKED`, 보관 시간 후 정리 배치 (`outbox.retention_hours`, `outbox.relay_batch`) |
| 4 | 매수 제한 보정 | 보완 | DB 집계만으로는 같은 CI 동시 요청을 못 막으므로 `purchase_counter` 테이블 추가. `seat_count + n ≤ max` 조건부 UPDATE가 최종 판정. Redis `limit:*`는 Lua INCRBY/DECRBY 1차 판정, 키가 없으면 이 테이블에서 복원 |
| 5 | reservation 인덱스 | 그대로 | 만료 스캐너용 부분 인덱스 `ix_resv_deadline`. `(ci_hash, run_id)`는 재집계·복원 배치용으로 명시 |
| 6 | waitlist 중복 제안 | 그대로 | `(run_id, status, requested_at)` 인덱스, `FOR UPDATE SKIP LOCKED` + `WAITING→OFFERED` 조건부 UPDATE. 이 인덱스가 run_id FK 인덱스를 대신함 |
| 7 | updated_at 제외 | 범위 축소 | INSERT만 하는 `processed_event`, `reservation_history`(+ 새 `app_policy_history`)만 생략. `seat_inventory`·`outbox_event`는 실제로 수정되는 테이블이라 유지 |
| 8 | 로그 쓰기 경로 | 그대로 | behavior_log·replay_event 모두 Kafka → insertMany 배치. 녹화 상한 3개와 적재 묶음 크기를 `app_policy`에. 샤드 키는 부하 테스트 후 판단 |
| 9 | app_policy 변경 추적 | 정정 | `version` + `app_policy_history`. updated_at은 DDL이 이미 자동으로 넣고 있어 추가하지 않음 |
| 10 | ci_hash 불변 | 그대로 | member 비고에 명시 |
| 11 | DDL 생성기 | 그대로 | 비고의 `FK(a, b) → 표(c, d)` 복합 FK, `CREATE INDEX …;` 일반 인덱스 반영. 검사 스크립트에 코드 컬럼 CHECK 누락 경고 추가 |
| 12 | risk_subject 마스터 | 최소안 | 마스터는 보류. `risk_score_history`, `admin_action`의 subject_type을 `CI / PAYMENT / DEVICE`로 맞춰 CHECK 적용 (`risk_score`는 PK로 이미 유일) |

## 반영하면서 추가로 찾은 것

| 문제 | 수정 |
|---|---|
| v4 `model_run` 예시 행에 NOT NULL인 `trained_at`이 없어 DDL INSERT가 실패함 | 예시 행에 값 추가. 검사 스크립트에 "예시 행의 NOT NULL 누락" FAIL 규칙 추가 |
| `reservation_history.from_status`, `to_status`에 CHECK 없음 (새 경고 규칙으로 발견) | to_status는 상태 코드 CHECK. from_status는 첫 기록에서 null이라 비고 CHECK로 허용값만 지정 |
| v4 `nn-auto`가 나중 버전 테이블에도 다시 적용될 수 있음 (멱등성 깨짐) | 그 패치 시점까지 있던 테이블에만 적용하도록 엔진 수정 (v4 결과는 변화 없음) |

## 규모

| 항목 | v4 | v5 |
|---|---|---|
| 테이블 | 58 | 60 (+ purchase_counter, app_policy_history) |
| 컬럼 | 480 | 494 |
| DDL CHECK | 54 | 61 |
| DDL 인덱스 | 47 | 54 |
| 예시 INSERT | 24 | 30 |
