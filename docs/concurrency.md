# FairRail 동시성 절차

예매·결제·취소·취소표·이벤트 발행에서 **트랜잭션 경계, 실행 순서, SQL·Redis 명령**의 원천 문서입니다. 스키마(테이블·컬럼·제약)의 원천은 ERD 편집기(`docs/erd/fairrail-erd.html`)이고, 테이블 비고에는 이 문서의 절 번호만 적습니다. 구현과 테스트는 이 문서를 그대로 따릅니다.

- 기준 스키마: v7
- 표기: `:이름`은 바인드 변수, `app_policy`의 값은 `policy(키)`로 적습니다.
- 마지막 절(§16)에 테스트로 옮길 시나리오 목록이 있습니다.

---

## §0 공통 원칙

### 0.1 판정 계층

| 계층 | 역할 | 실패 시 |
|---|---|---|
| Redis | 빠른 1차 판정 (좌석 경쟁, 매수 한도, 멱등) | DB에 쓰지 않고 바로 거절 |
| Oracle | 최종 판정 (PK·UNIQUE·조건부 UPDATE·CHECK) | 트랜잭션 롤백 후 Redis 보상 (§14.3) |

Redis가 통과시켜도 DB가 거절하면 거절입니다. 반대로 DB가 허용하는 것을 Redis가 막는 경우는 없어야 합니다 (Redis 값은 DB에서 복원 가능해야 함).

### 0.2 마감 시각의 원천

`reservation.pay_deadline_at`이 원천입니다. 아래 네 곳은 같은 트랜잭션에서 같은 값으로 복사하고, 바꿀 때도 함께 바꿉니다.

| 복사본 | 갱신 시점 |
|---|---|
| `seat_inventory.hold_expires_at` | 선점(§2), 결제 시작(§4) |
| Redis `seat:hold:*` 만료 시각 | 선점(§2), 결제 시작 커밋 후(§4) |
| `saga_instance.timeout_at` | 선점(§2), 결제 시작(§4) |
| `waitlist.offer_deadline_at` | 취소표 제안(§9) |

### 0.3 네이티브 UPDATE 규칙

JPA Auditing을 거치지 않는 모든 네이티브 UPDATE는 다음을 지킵니다.

- `updated_at = SYSTIMESTAMP`를 넣습니다 (`noUpdatedAt` 테이블 제외).
- `version` 컬럼이 있는 테이블(`reservation`, `app_policy`)은 `version = version + 1`을 넣습니다. 그래야 JPA 낙관적 락이 충돌을 감지합니다.
- 상태를 바꾸는 UPDATE는 **현재 상태를 WHERE에 넣고 영향 행 수를 확인**합니다. 기대한 행 수가 아니면 다른 트랜잭션이 먼저 처리한 것이므로, 그 뒤의 부수 작업(카운터 감소, 이벤트 발행)을 하지 않습니다.

### 0.4 한 트랜잭션 안의 락 순서

데드락을 막기 위해 한 트랜잭션에서 여러 행을 잠글 때는 항상 이 순서와 정렬을 따릅니다.

1. `reservation`: `reservation_id` 오름차순
2. `seat_inventory`: `(run_id, seat_id, segment_no)` 오름차순
3. `payment`
4. `purchase_counter`: `(scope, scope_ref_id, ci_hash)` 오름차순 (여러 CI가 섞여도 같은 정렬)
5. `waitlist`
6. INSERT만 하는 테이블 (`reservation_history`, `outbox_event`, `notification`, `cancellation`)은 맨 끝

새로 INSERT하는 `reservation` 행은 다른 트랜잭션이 아직 모르므로 순서 제약에서 빠집니다.

### 0.5 이벤트 기록

상태를 바꾸는 트랜잭션은 같은 트랜잭션 안에서, **reservation 행을 INSERT·UPDATE한 뒤에** `outbox_event`를 INSERT합니다 (§11.1). reservation 행 락이 같은 예약의 트랜잭션을 줄 세우므로, `seq`가 커밋 순서와 같아집니다.

### 0.6 외부 호출

PG 호출, Kafka 발행 같은 네트워크 호출은 **DB 트랜잭션 밖**에서 합니다. 락을 쥔 채 외부 응답을 기다리지 않습니다.

---

## §1 멱등 처리

클라이언트는 버튼을 누를 때마다 UUID `idempotency_key`를 만들고, 재시도에는 같은 키를 씁니다.

1. `SET idem:{memberId}:{key} :newReservationId NX PX policy(idem.ttl_sec)*1000`
   - 성공: 새 예약으로 §2를 진행합니다.
   - 실패(이미 있음): `GET`으로 기존 `reservation_id`를 읽고 그 예약의 현재 상태를 돌려줍니다. DB에 행이 아직 없으면 "처리 중"(202)을 돌려줍니다.
2. DB 최종 방어: `UNIQUE(member_id, idempotency_key)`. INSERT가 ORA-00001이면 기존 예약을 조회해 돌려줍니다.
3. §2가 거절로 끝나면 `idem` 키를 compare-and-delete(§14.3)로 지웁니다. 거절된 요청을 같은 키로 다시 보내면 같은 판정을 다시 받습니다.

결제 요청도 같은 방식입니다. 키는 `idem:pay:{reservationId}:{key}`, DB 방어는 `UNIQUE(reservation_id, idempotency_key)`와 예약당 승인 1건 인덱스(`ux_payment_approved`)입니다.

---

## §2 좌석 선점 (신규 예약)

**전제**: 유효한 `queue:pass:{runId}:{memberId}`가 있어야 합니다. 없으면 거절합니다.

### 2.1 Redis 단계

1. §1로 `reservation_id` R을 받습니다 (시퀀스 또는 Snowflake).
2. 매수 한도 1차: `limit_incr.lua`(§14.2)로 `limit:{runId}:{ciHash}`, `limit:event:{saleEventId}:{ciHash}`를 n만큼 올립니다. 한도를 넘으면 스크립트가 되돌리고 거절합니다. 키가 없으면 스크립트가 `purchase_counter` 값으로 먼저 채웁니다 (§10.4).
3. 좌석 경쟁: `hold.lua`로 예약할 모든 구간 키 `seat:hold:{runId}:{seatId}:{segNo}`를 R 값으로 `SET NX`합니다. 하나라도 다른 값이 있으면 전부 실패합니다.
   - **패배자**: 2번의 한도를 되돌리고(`limit_decr.lua`), `idem` 키를 지우고 "이미 선점된 좌석"으로 거절합니다. **DB 쓰기는 0건**입니다.
   - 만료 시각은 `pay_deadline_at`과 같은 값(지금 + `policy(reservation.pay_deadline_min)`)을 `PEXPIREAT`으로 겁니다.

### 2.2 DB 트랜잭션 (승자만)

1. 이전 점유자 확인 (락 없음): `SELECT reservation_id, status, hold_expires_at FROM seat_inventory WHERE (run_id, seat_id, segment_no) IN (…)`.
   - 행이 없으면 4로 갑니다.
   - `status = 'SOLD'`이거나 `hold_expires_at >= SYSTIMESTAMP`인 행이 있으면 거절합니다. Redis 키가 사라졌는데 DB 점유가 유효한 경우로, 정상이면 일어나지 않지만 DB가 최종입니다.
   - 만료된 HOLD만 있으면 3의 재선점으로 갑니다.
2. (재선점일 때만) §3을 같은 트랜잭션에서 실행합니다.
3. `INSERT INTO reservation (… status = 'HOLD', pay_deadline_at = :d, idempotency_key, version = 0 …)`
4. `INSERT INTO seat_inventory` 구간마다 한 행 (`status = 'HOLD'`, `hold_expires_at = :d`, `reservation_id = R`, `train_id = 운행 열차`). 정렬 순서로 INSERT합니다.
5. `INSERT INTO reservation_seat` 좌석마다 (승차권 번호 `ticket_no`는 이때 발급하지만, 확정 전에는 효력이 없음).
6. `purchase_counter` 증가: §10.1 (재선점이면 이전 예약의 감소와 함께 정렬 순서로).
7. `INSERT INTO reservation_history (from_status = NULL, to_status = 'HOLD', actor_type = 'USER')`
8. `INSERT INTO saga_instance (current_step = 'SEAT_HELD', status = 'RUNNING', timeout_at = :d)`
9. `INSERT INTO outbox_event (event_type = 'SEAT_HELD', partition_key = R, …)` (§11.1)
10. COMMIT

### 2.3 실패 처리

트랜잭션이 롤백되면 다음을 합니다. 원인은 한도 초과, PK 충돌, 제약 위반, DB 오류 등입니다.

- `release.lua`로 R 값인 `seat:hold` 키만 지웁니다 (compare-and-delete).
- `limit_decr.lua`로 한도를 되돌립니다.
- `idem` 키를 지웁니다.

---

## §3 재선점 (만료된 HOLD 이어받기)

§2.2 트랜잭션 안에서, 만료된 HOLD 행의 이전 예약 R1, R2, … 를 처리합니다.

1. 이전 예약 잠금: `SELECT reservation_id, status, seat_count, ci_hash, run_id FROM reservation WHERE reservation_id IN (:R1, …) ORDER BY reservation_id FOR UPDATE`
2. 이전 예약마다:
   - `status = 'HOLD'`이면:
     ```sql
     UPDATE reservation SET status = 'EXPIRED', updated_at = SYSTIMESTAMP, version = version + 1
      WHERE reservation_id = :R1 AND status = 'HOLD' AND pay_deadline_at < SYSTIMESTAMP
     ```
     1행이면 만료 처리를 계속합니다.
   - `status = 'EXPIRED'`이면: 다른 트랜잭션이 이미 처리한 것입니다 (예: R1의 5A와 5B를 두 사람이 동시에 재선점). 감소 없이 넘어갑니다.
   - `status = 'PAYMENT_PENDING'`이거나 `'CONFIRMED'`이면: **재선점 불가**입니다. 결제 중인 예약은 §6 스캐너만 정리합니다. 트랜잭션을 롤백합니다.
3. 만료 처리한 R1의 **모든 HOLD 행**을 지웁니다. 지금 가져올 좌석만이 아니라 R1이 잡았던 다른 좌석도 포함입니다 (고아 행 방지).
   ```sql
   DELETE FROM seat_inventory WHERE reservation_id = :R1 AND status = 'HOLD'
   ```
4. R1의 `purchase_counter`를 R1의 `seat_count` 전체만큼 감소합니다. 새 예약의 증가와 합쳐 정렬 순서로 갱신합니다 (§10.3).
5. R1의 `reservation_history`(HOLD → EXPIRED, `actor_type = 'SYSTEM'`), `saga_instance.status = 'COMPENSATED'`, outbox `RESERVATION_EXPIRED`(`partition_key = R1`)를 기록합니다.
6. 이어서 §2.2의 3~10을 진행합니다.
7. 커밋 후: R1의 다른 좌석 `seat:hold` 키를 R1 값일 때만 지웁니다(`release.lua`). R1의 `limit:*`를 감소하고, 취소표 재배정 이벤트를 발행합니다.

---

## §4 결제 시작 (마감 연장)

### 4.1 DB 트랜잭션

1. 예약 전이 + 연장. 늘리기만 하고 줄이지 않습니다.
   ```sql
   UPDATE reservation
      SET status = 'PAYMENT_PENDING',
          pay_deadline_at = GREATEST(pay_deadline_at,
                                     SYSTIMESTAMP + NUMTODSINTERVAL(:pgTimeout + :grace, 'SECOND')),
          updated_at = SYSTIMESTAMP, version = version + 1
    WHERE reservation_id = :R AND member_id = :me AND status = 'HOLD' AND pay_deadline_at > SYSTIMESTAMP
   ```
   - `:pgTimeout = policy(payment.pg_timeout_sec)`, `:grace = policy(payment.extend_grace_sec)`
   - 0행이면 이미 결제 중, 만료됨, 또는 남의 예약이므로 거절합니다. HOLD에서 PAYMENT_PENDING으로는 한 번만 바뀌므로 연장도 한 번만 일어납니다.
2. 새 마감 `:d`를 읽습니다 (`RETURNING pay_deadline_at INTO :d`).
3. 좌석 소유·만료 재확인 겸 복사:
   ```sql
   UPDATE seat_inventory SET hold_expires_at = :d, updated_at = SYSTIMESTAMP
    WHERE reservation_id = :R AND status = 'HOLD'
   ```
   영향 행 수가 이 예약의 구간 행 수와 다르면 좌석을 이미 잃은 것이므로 롤백하고 거절합니다.
4. `UPDATE saga_instance SET current_step = 'PAYING', timeout_at = :d, updated_at = SYSTIMESTAMP WHERE reservation_id = :R AND status = 'RUNNING'`
5. `INSERT INTO payment (status = 'REQUESTED', idempotency_key, …)` (§1)
6. `reservation_history`(HOLD → PAYMENT_PENDING), outbox `PAYMENT_STARTED`
7. COMMIT

### 4.2 커밋 후

1. `extend.lua`로 R의 모든 `seat:hold` 키를 값이 R일 때만 `PEXPIREAT :d`로 연장합니다.
2. PG 승인 요청을 보냅니다 (트랜잭션 밖).

---

## §5 결제 확정

PG 승인 응답이나 콜백을 받았을 때 실행합니다. 같은 결과가 두 번 와도 안전해야 합니다.

1. `SELECT … FROM reservation WHERE reservation_id = :R FOR UPDATE`
2. 결제 승인 기록:
   ```sql
   UPDATE payment SET status = 'APPROVED', pg_tx_id = :tx, approved_at = SYSTIMESTAMP, updated_at = SYSTIMESTAMP
    WHERE payment_id = :P AND status = 'REQUESTED'
   ```
   0행이고 이미 APPROVED면 이미 확정된 것이므로 그대로 성공을 돌려줍니다 (멱등).
3. 좌석 확정. 구간 행 수만큼 갱신돼야 성공입니다.
   ```sql
   UPDATE seat_inventory SET status = 'SOLD', hold_expires_at = NULL, updated_at = SYSTIMESTAMP
    WHERE reservation_id = :R AND status = 'HOLD'
   ```
4. 예약 확정:
   ```sql
   UPDATE reservation SET status = 'CONFIRMED', confirmed_at = SYSTIMESTAMP, updated_at = SYSTIMESTAMP, version = version + 1
    WHERE reservation_id = :R AND status = 'PAYMENT_PENDING'
   ```
5. `saga_instance.status = 'DONE'`, `reservation_history`(PAYMENT_PENDING → CONFIRMED), outbox `RESERVATION_CONFIRMED`
6. `reservation.source = 'WAITLIST'`면 `UPDATE waitlist SET status = 'ACCEPTED', updated_at = SYSTIMESTAMP WHERE offered_reservation_id = :R AND status = 'OFFERED'`
7. COMMIT
8. 커밋 후 `sold.lua`로 각 `seat:hold` 키를 `SOLD:R` 값으로 바꾸고, 만료 시각을 운행 출발 시각으로 겁니다. 팔린 좌석은 Redis 단계에서 바로 막힙니다.

**3 또는 4가 기대 행 수가 아니면** (좌석을 잃었거나 예약이 이미 만료됨): 전체를 롤백합니다. 별도 트랜잭션에서 결제만 `APPROVED`로 기록하고 늦은 승인 환불(§7.3)을 시작합니다. 이 경로는 §4의 연장과 §6의 PG 조회가 있으므로 마지막 안전망입니다.

---

## §6 만료 스캐너

주기적으로 마감이 지난 예약을 정리합니다.

1. 후보 조회 (락 없음, 인덱스 `ix_resv_deadline`과 같은 식):
   ```sql
   SELECT reservation_id, status FROM reservation
    WHERE (CASE WHEN status IN ('HOLD', 'PAYMENT_PENDING') THEN pay_deadline_at END) < SYSTIMESTAMP
   ```
   최대 N건을 커서로 읽습니다.
2. **HOLD**: §7.1 해제(`to = 'EXPIRED'`)를 실행합니다.
3. **PAYMENT_PENDING**: 바로 만료시키지 않습니다. 그 예약의 `payment` 중 `status = 'REQUESTED'`인 건을 PG에 조회합니다 (트랜잭션 밖).
   - 승인됨: §5 결제 확정을 실행합니다. 결제 중인 좌석은 §3 재선점 대상이 아니므로 아직 이 예약 소유입니다.
   - 실패·없음: `payment.status = 'FAILED'`로 기록하고 §7.1 해제(`from = 'PAYMENT_PENDING'`, `to = 'EXPIRED'`)를 실행합니다.
   - 응답 없음·PG 장애: 이번 회차는 건너뜁니다. `policy(payment.pg_unknown_max_min)`이 지나도 모르면 관리자 확인 대상으로 알림을 보내고, 자동으로 만료시키지 않습니다.

---

## §7 해제 (만료·결제 실패·결제 전 취소)

### 7.1 DB 트랜잭션

1. 상태 전이. 1행일 때만 아래를 계속합니다 (0.3).
   ```sql
   UPDATE reservation SET status = :to, updated_at = SYSTIMESTAMP, version = version + 1
    WHERE reservation_id = :R AND status = :from
   ```
2. `DELETE FROM seat_inventory WHERE reservation_id = :R AND status = 'HOLD'`
3. `purchase_counter` 감소: §10.2
4. `saga_instance.status = 'COMPENSATED'`, `reservation_history`, outbox `RESERVATION_EXPIRED` 또는 `PAYMENT_FAILED`
5. 취소표 제안으로 만든 예약이면 `UPDATE waitlist SET status = 'EXPIRED', updated_at = SYSTIMESTAMP WHERE offered_reservation_id = :R AND status = 'OFFERED'`
6. COMMIT

### 7.2 커밋 후

`release.lua`로 R 값인 `seat:hold`를 지우고, `limit_decr.lua`로 한도를 감소합니다. 빈 좌석 이벤트는 outbox를 통해 §9가 받습니다.

### 7.3 늦은 승인 환불

결제는 승인됐는데 예약을 확정할 수 없는 경우입니다. `cancellation`(`cancel_type = 'PAY_FAILED'`, `refund_status = 'REQUESTED'`)을 INSERT하고 PG 환불을 요청합니다. 환불이 완료되면 한 트랜잭션에서 `refund_status = 'DONE'`과 `payment.status = 'REFUNDED'`를 기록합니다.

### 7.4 결제 전 사용자 취소

- HOLD 예약: §7.1을 `from = 'HOLD'`, `to = 'CANCELED'`로 실행합니다.
- PAYMENT_PENDING 예약: "결제 진행 중"으로 거절합니다. PG 결과가 나온 뒤 취소합니다.

---

## §8 확정 예약 취소

1. 취소 전이:
   ```sql
   UPDATE reservation SET status = 'CANCELED', canceled_at = SYSTIMESTAMP, updated_at = SYSTIMESTAMP, version = version + 1
    WHERE reservation_id = :R AND member_id = :me AND status = 'CONFIRMED'
   ```
   1행일 때만 아래를 계속합니다.
2. `DELETE FROM seat_inventory WHERE reservation_id = :R AND status = 'SOLD'`
3. `purchase_counter` 감소: §10.2. **확정 예약도 집계 대상이므로 감소합니다.**
4. `cancel_fee_policy`에서 출발까지 남은 분으로 수수료를 정하고 `cancellation`을 INSERT합니다 (`refund_status = 'REQUESTED'`, `minutes_after_purchase`, `minutes_before_departure` 포함).
5. `reservation_history`(CONFIRMED → CANCELED), outbox `RESERVATION_CANCELED`
6. COMMIT
7. 커밋 후: `release.lua`로 `SOLD:R` 값인 `seat:hold`를 지우고, `limit_decr.lua`로 한도를 감소합니다. PG 환불을 요청하고 완료되면 §7.3처럼 기록합니다.

---

## §9 취소표 제안

빈 좌석 이벤트(`RESERVATION_CANCELED`, `RESERVATION_EXPIRED`)를 소비할 때 실행합니다.

1. 대기자 조회 (인덱스 `ix_waitlist_next`):
   ```sql
   SELECT waitlist_id, member_id, from_station_id, to_station_id, seat_grade, seat_count FROM waitlist
    WHERE run_id = :r AND status = 'WAITING' ORDER BY requested_at
      FOR UPDATE SKIP LOCKED
   ```
   커서로 한 건씩 읽습니다. 다른 인스턴스가 잡은 대기자는 건너뜁니다.
2. 빈 구간·등급·매수가 맞는 대기자를 찾을 때까지 진행합니다.
3. 그 대기자 명의로 §2를 실행합니다. Redis 단계, 매수 한도, DB 트랜잭션 모두 포함하고 `reservation.source = 'WAITLIST'`로 둡니다. **제안 예약도 `purchase_counter`를 증가시킵니다.** §2.2 트랜잭션 안에서 다음을 함께 실행합니다.
   ```sql
   UPDATE waitlist SET status = 'OFFERED', offered_at = SYSTIMESTAMP, offer_deadline_at = :d,
          offered_reservation_id = :R, updated_at = SYSTIMESTAMP
    WHERE waitlist_id = :w AND status = 'WAITING'
   ```
   1행이어야 하며, `notification`(`WAITLIST_OFFER`)도 INSERT합니다.
4. 매수 한도에 걸린 대기자는 `status = 'SKIPPED'`로 바꾸고 다음 대기자로 넘어갑니다.
5. 수락은 결제(§4, §5)입니다. 기한이 지나면 §6 → §7이 예약을 만료시키고, `waitlist`는 `EXPIRED`가 됩니다. 그 빈 좌석 이벤트로 다음 대기자에게 다시 제안합니다.

---

## §10 매수 카운터 (`purchase_counter`)

### 10.1 증가 (§2.2 트랜잭션 안)

대상 scope는 두 개입니다. `PER_RUN`(`scope_ref_id = run_id`)과 `PER_HOLIDAY`(`scope_ref_id = sale_event_id`)입니다. `train_run.sale_event_id`가 NULL이면 PER_HOLIDAY는 적용하지 않습니다. scope마다 다음을 실행합니다.

```sql
UPDATE purchase_counter SET seat_count = seat_count + :n, updated_at = SYSTIMESTAMP
 WHERE scope = :s AND scope_ref_id = :ref AND ci_hash = :ci AND seat_count + :n <= :max
```

- 1행: 통과.
- 0행: 행이 있는지 확인합니다.
  - 있으면 한도 초과이므로 롤백합니다.
  - 없으면 `:n <= :max`를 확인하고 `INSERT (scope, scope_ref_id, ci_hash, seat_count = :n)`를 실행합니다.
  - INSERT가 ORA-00001이면 동시에 다른 요청이 행을 만든 것입니다. UPDATE부터 한 번 다시 시도합니다.
- `:max`는 `purchase_limit_policy`에서 해당 scope·행사의 `max_seats`입니다.

### 10.2 감소

**예약 상태 UPDATE가 1행일 때만, 같은 트랜잭션에서** 실행합니다 (§3, §7.1, §8). 취소와 만료가 동시에 와도 한쪽만 1행이 되므로 두 번 감소하지 않습니다.

```sql
UPDATE purchase_counter SET seat_count = seat_count - :n, updated_at = SYSTIMESTAMP
 WHERE scope = :s AND scope_ref_id = :ref AND ci_hash = :ci
```

`CHECK(seat_count >= 0)`이 마지막 방어입니다.

### 10.3 갱신 순서

한 트랜잭션에서 갱신할 카운터 행을 전부 모은 뒤 `(scope, scope_ref_id, ci_hash)` 오름차순으로 갱신합니다. 재선점처럼 새 예약의 증가와 이전 예약(다른 CI)의 감소가 섞여도 이 정렬 하나로 데드락을 막습니다 (0.4).

### 10.4 Redis 복원

`limit:*` 키가 없을 때는 `limit_incr.lua`가 `purchase_counter.seat_count`를 인자로 받아 **`SET NX`로 먼저 채운 뒤** INCRBY합니다. 동시에 여러 요청이 복원해도 한 값만 들어가고, 나머지는 그 위에 더합니다.

### 10.5 재집계

카운터가 의심되면 오프피크에 `reservation`(HOLD·PAYMENT_PENDING·CONFIRMED)을 풀스캔으로 다시 집계해 맞춥니다.

---

## §11 outbox 기록·릴레이

### 11.1 기록

```sql
INSERT INTO outbox_event (event_id, seq, aggregate_type, aggregate_id, partition_key, shard_no, event_type, payload, status, retry_count)
VALUES (:uuid, outbox_seq.NEXTVAL, :type, :aggId, :pkey, ORA_HASH(:pkey, 15), :evt, :json, 'PENDING', 0)
```

- 예약 흐름의 `partition_key`는 항상 `reservation_id`입니다.
- 상태를 바꾸는 트랜잭션 안에서, reservation 행 UPDATE·INSERT **뒤에** 실행합니다 (0.5). 같은 예약의 다음 트랜잭션은 reservation 행 락에서 기다리므로, 다음 이벤트의 `seq`가 항상 더 큽니다.

### 11.2 샤드 담당 (리스)

샤드는 16개로 고정합니다 (`policy(outbox.shard_count)`, `shard_no` CHECK와 같아야 함). 릴레이 인스턴스는 샤드마다 Redis 리스를 잡은 샤드만 처리합니다.

- 획득: `SET relay:shard:{n} :instanceId NX PX policy(relay.lease_sec)*1000`
- 갱신: 리스 시간의 1/3마다 `extend.lua`로 값이 자기 ID일 때만 연장합니다.
- 갱신에 실패하면 **그 샤드 처리를 즉시 멈춥니다.**
- 인스턴스 수가 바뀌어도 리스가 끝나기 전에는 다른 인스턴스가 그 샤드를 가져가지 못합니다.

### 11.3 조회와 발행

```sql
SELECT event_id, seq, status, partition_key, event_type, payload, retry_count FROM outbox_event
 WHERE (CASE WHEN status IN ('PENDING', 'FAILED') THEN shard_no END) = :n
 ORDER BY (CASE WHEN status IN ('PENDING', 'FAILED') THEN seq END)
   FOR UPDATE WAIT policy(relay.lock_wait_sec)
```

- 커서를 열고 최대 `policy(outbox.relay_batch)`건까지 fetch합니다. Oracle은 `FETCH FIRST`를 `FOR UPDATE`와 함께 쓸 수 없고, `ROWNUM`은 락보다 먼저 적용되므로 쓰지 않습니다.
- **`SKIP LOCKED`를 쓰지 않습니다.** 리스가 넘어가는 순간 이전 담당자가 잡은 앞 행을 건너뛰면 순서가 깨집니다. 기다리다 시간이 지나면 이번 회차를 포기합니다.
- `seq` 순서대로 하나씩 발행합니다.
  - Kafka 프로듀서: `enable.idempotence=true`, `acks=all`, 같은 키 순서를 보장하는 설정
  - 성공: `UPDATE outbox_event SET status = 'PUBLISHED', published_at = SYSTIMESTAMP, updated_at = SYSTIMESTAMP WHERE event_id = :id`
  - 실패: `retry_count = retry_count + 1`. `policy(outbox.max_retry)`에 도달하면 `status = 'FAILED'`로 바꾸고 **그 샤드 처리를 멈춥니다.**
- 배치마다 COMMIT합니다.

### 11.4 FAILED와 샤드 정지

FAILED 행은 부분 인덱스에 남습니다. 다음 회차에 그 샤드의 맨 앞 행이 FAILED면 릴레이는 그 샤드를 처리하지 않고 알림을 보냅니다. 같은 예약의 뒤 이벤트가 앞지르지 않게 하려는 것입니다. 다른 15개 샤드는 계속 처리됩니다. 관리자가 원인을 고친 뒤 `status = 'PENDING'`, `retry_count = 0`으로 되돌리면 샤드가 재개됩니다.

### 11.5 정리

`status = 'PUBLISHED'`이고 `published_at < SYSTIMESTAMP - policy(outbox.retention_hours)`인 행을 오프피크에 배치로 삭제합니다.

---

## §12 Inbox (Kafka 소비)

파티션 순서대로 소비하며, 한 트랜잭션에서 다음을 실행합니다.

1. `INSERT INTO processed_event (consumer_group, event_id, processed_at)`. ORA-00001이면 이미 처리한 이벤트이므로 건너뛰고 커밋합니다.
2. 업무 처리를 합니다.
3. COMMIT 후 오프셋을 커밋합니다.

정리는 `processed_at < SYSTIMESTAMP - policy(inbox.retention_days)`인 행을 배치로 지웁니다 (인덱스 `ix_inbox_processed`). 보관 기간은 Kafka 보관 기간보다 길어야 재전달 중복을 막습니다.

---

## §13 MongoDB 적재·보관

### 13.1 적재

`behavior_log`와 `replay_event`는 앱이 Kafka에 보내고, 적재 컨슈머가 `insertMany`로 배치 저장합니다 (`policy(behavior.batch_size)`). `replay_event`는 `{session_id, seq}` 유니크 인덱스로 재전송 중복을 막습니다 (중복 키 오류는 무시).

### 13.2 보관 (`expire_at` + TTL `expireAfterSeconds: 0`)

| 컬렉션 | `expire_at` 계산 | 보류 |
|---|---|---|
| behavior_log | `ts` + `behavior.retention_days` | 없음 |
| replay_session | `started_at` + `replay.retention_days` | `legal_hold = true`면 필드 없음 |
| replay_event | 세션의 `expire_at`과 같은 값 | 세션이 `legal_hold`면 필드 없음 |
| queue_log | `entered_at` + `queue_log.retention_days` | 없음 |
| evidence_snapshot | 케이스가 열려 있는 동안 필드 없음. 종료 시 `closed_at` + `evidence.retention_days` | 케이스 재개 시 필드 제거 |

- **컨슈머는 `replay_event`를 저장하기 전에 세션의 `legal_hold`를 확인**합니다 (짧은 캐시 허용). 보류 중이면 `expire_at` 없이 저장합니다. 이렇게 해야 보류 이후 도착한 이벤트가 삭제되지 않습니다.
- 보류를 걸 때: `replay_session.legal_hold = true` 저장 → 그 세션의 `replay_session`·`replay_event`에서 `$unset: {expire_at: ""}`
- 보류를 풀 때: `expire_at = max(원래 값, 지금 + 1일)`로 다시 설정합니다.

---

## §14 Redis 키와 Lua 스크립트

### 14.1 키

| 키 | 값 | 만료 |
|---|---|---|
| `idem:{memberId}:{key}`, `idem:pay:{reservationId}:{key}` | reservation_id / payment_id | `idem.ttl_sec` |
| `queue:{runId}`, `queue:active:{runId}`, `queue:pass:{runId}:{memberId}` | 대기열 | `queue.pass_ttl_sec` |
| `seat:hold:{runId}:{seatId}:{segNo}` | `reservation_id` (HOLD) 또는 `SOLD:reservation_id` | `pay_deadline_at` / 운행 출발 시각 |
| `limit:{runId}:{ciHash}`, `limit:event:{saleEventId}:{ciHash}` | 보유 매수 | 운행 출발·행사 종료 |
| `relay:shard:{n}` | 릴레이 인스턴스 ID | `relay.lease_sec` |
| `rate:login:{ipHash}`, `rate:api:{memberId}` | 횟수 | 짧은 창 |
| `risk:{subjectType}:{hash}`, `policy:cache`, `seatmap:{runId}` | 캐시 | |

### 14.2 스크립트

| 스크립트 | 동작 |
|---|---|
| `hold.lua` | KEYS 전부에 대해, 다른 값이 하나라도 있으면 0 반환. 아니면 전부 `SET 값 PXAT 만료` 후 1 반환 |
| `release.lua` | KEYS 중 값이 ARGV[1]인 키만 DEL (compare-and-delete) |
| `extend.lua` | KEYS 중 값이 ARGV[1]인 키만 `PEXPIREAT` (결제 연장, 리스 갱신) |
| `sold.lua` | KEYS 중 값이 R인 키를 `SOLD:R`로 바꾸고 출발 시각으로 만료 |
| `limit_incr.lua` | 키마다 없으면 `SET 복원값 NX`, 그 뒤 INCRBY n. 하나라도 한도를 넘으면 이번 증가분을 전부 DECRBY하고 0 반환 |
| `limit_decr.lua` | 키마다 DECRBY n (0 미만이면 0으로) |

### 14.3 DB 롤백 시 Redis 보상

DB 트랜잭션이 롤백되면 그 요청이 Redis에 한 일을 되돌립니다. `seat:hold`는 `release.lua`, `limit:*`는 `limit_decr.lua`, `idem`은 compare-and-delete입니다. 보상이 실패해도 TTL이 끝나면 사라지고, DB가 최종 판정이므로 정합성은 깨지지 않습니다 (가용성만 잠시 떨어짐).

### 14.4 클러스터로 바꿀 경우

지금은 단일 노드 전제입니다. 클러스터에서는 한 Lua가 쓰는 키가 같은 슬롯이어야 하므로 해시 태그를 이렇게 바꿉니다.

- 좌석: `seat:hold:{runId}:seatId:segNo`. 한 예약의 여러 좌석·구간이 같은 슬롯에 들어가도록 태그를 운행 단위로 통일합니다.
- 한도: `limit:{ciHash}:run:runId`, `limit:{ciHash}:event:saleEventId`. CI 단위 태그입니다.

`seat:hold`와 `limit`은 슬롯이 다르므로 지금처럼 다른 스크립트로 나눠 둡니다.

---

## §15 시간 값 (예시, `app_policy`)

| 키 | 예시 | 쓰는 곳 |
|---|---|---|
| `reservation.pay_deadline_min` | 10 | §2 최초 마감 |
| `payment.pg_timeout_sec` | 180 | §4 연장 (앱카드·ISP 인증 시간 포함) |
| `payment.extend_grace_sec` | 60 | §4 연장 |
| `payment.pg_unknown_max_min` | 30 | §6 결과 모름 알림 |
| `idem.ttl_sec` | 600 | §1 |
| `relay.lease_sec` | 15 | §11.2 |
| `relay.lock_wait_sec` | 5 | §11.3 |
| `outbox.max_retry` | 5 | §11.3 |
| `queue_log.retention_days` | 30 | §13.2 |
| `evidence.retention_days` | 365 | §13.2 (케이스 종료 후) |

---

## §16 테스트 시나리오

통합 테스트로 옮길 목록입니다. 각 시나리오는 동시에 실행했을 때 결과를 확인합니다.

| # | 시나리오 | 기대 결과 | 절 |
|---|---|---|---|
| T1 | 같은 좌석 동시 선점 100건 | 1건 성공, 나머지 DB 쓰기 0건 | §2.1 |
| T2 | 같은 idempotency_key로 선점 재시도 | 같은 reservation_id 반환 | §1 |
| T3 | 2석 예약 R1 만료 후 다른 사람이 1석 재선점 | R1 EXPIRED, R1의 HOLD 행 0건, 카운터 2 감소 | §3 |
| T4 | R1의 두 좌석을 두 사람이 동시에 재선점 | 둘 다 성공, 카운터 한 번만 감소 | §3 |
| T5 | 결제 중(PAYMENT_PENDING) 좌석 재선점 시도 | 거절 | §3 |
| T6 | 선점 1분 후 결제 시작 | 마감이 줄지 않음 | §4 |
| T7 | PG 승인 지연 중 스캐너 실행 | 만료되지 않고 PG 조회 후 확정 | §6 |
| T8 | PG 장애로 결과 모름 | 자동 만료 없음, 알림 | §6 |
| T9 | 좌석을 잃은 뒤 승인 도착 | 롤백 + 환불 시작 | §5, §7.3 |
| T10 | 취소와 만료가 동시에 도착 | 한쪽만 처리, 카운터 한 번 감소 | §10.2 |
| T11 | 같은 CI 첫 예약 2건이 동시에 카운터 생성 | 한도 유지 (ORA-00001 재시도) | §10.1 |
| T12 | 서로 다른 CI 재선점 2건 교차 | 데드락 없음 | §10.3 |
| T13 | DB가 한도 초과로 거절 | Redis hold·limit·idem 원복 | §2.3 |
| T14 | Redis 재시작 후 예약 | limit 복원 후 정상 판정 | §10.4 |
| T15 | 확정 예약 취소 | SOLD 행 삭제, 카운터 감소, 환불 요청 | §8 |
| T16 | 취소표 제안 시 대기자가 한도 초과 | SKIPPED 후 다음 대기자 | §9 |
| T17 | 인스턴스 2대가 같은 빈 좌석 이벤트 처리 | 대기자 한 명에게 한 번만 제안 | §9 |
| T18 | 같은 예약 이벤트 3개를 릴레이 2대가 처리 | seq 순서로 발행 | §11 |
| T19 | 이벤트 발행이 max_retry 실패 | FAILED, 그 샤드만 정지, 같은 예약 뒤 이벤트 미발행 | §11.4 |
| T20 | 릴레이 인스턴스 추가·제거 중 발행 | 리스 이동 중 순서 유지 | §11.2 |
| T21 | 같은 Kafka 메시지 2회 소비 | 업무 처리 1회 | §12 |
| T22 | legal_hold 이후 도착한 녹화 이벤트 | expire_at 없음 (삭제 안 됨) | §13.2 |
| T23 | 네이티브 UPDATE 후 JPA로 같은 예약 수정 | 낙관적 락 충돌 감지 | §0.3 |
