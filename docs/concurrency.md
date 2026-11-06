# FairRail 동시성 절차

예매·결제·취소·취소표·이벤트 발행에서 **트랜잭션 경계, 실행 순서, SQL·Redis 명령**의 원천 문서입니다. 스키마(테이블·컬럼·제약)의 원천은 ERD 편집기(`docs/erd/fairrail-erd.html`)이고, 테이블 비고에는 이 문서의 절 번호만 적습니다. 구현과 테스트는 이 문서를 그대로 따릅니다.

- 기준 스키마: v8
- 표기: `:이름`은 바인드 변수, `app_policy`의 값은 `policy(키)`로 적습니다. Redis 키의 `{runId}` 같은 중괄호는 **자리표시자**이고 실제 키에는 중괄호가 없습니다 (`seat:hold:1001:57:0`). 클러스터 해시 태그와는 다릅니다 (§14.4).
- §16에 테스트로 옮길 시나리오, §17에 비교 실험과 지표 정의가 있습니다.

---

## §0 공통 원칙

### 0.1 판정 계층

| 계층 | 역할 | 실패 시 |
|---|---|---|
| Redis | 빠른 1차 판정 (좌석 경쟁, 매수 한도, 멱등) | DB에 쓰지 않고 바로 거절 |
| Oracle | 최종 판정 (PK·UNIQUE·조건부 UPDATE·CHECK) | 트랜잭션 롤백 후 Redis 보상 (§14.3) |

Redis가 통과시켜도 DB가 거절하면 거절입니다. 반대로 DB가 허용하는 것을 Redis가 막는 경우는 없어야 합니다. 이를 위해 Redis가 DB보다 엄격하게 남는 경우(보상 유실)를 되돌리는 장치를 둡니다: 커밋 뒤 보상은 outbox로 보장(§14.3), 한도는 거절할 때 DB와 대조해 자가 복구(§10.7).

### 0.2 마감 시각의 원천

`reservation.pay_deadline_at`이 원천입니다. 아래 네 곳은 같은 트랜잭션에서 같은 값으로 복사하고, 바꿀 때도 함께 바꿉니다. 마감 값은 앱 시계로 한 번 계산합니다 (§0.7).

| 복사본 | 갱신 시점 |
|---|---|
| `seat_inventory.hold_expires_at` | 선점(§2), 결제 시작(§4) |
| Redis `seat:hold:*` 만료 시각 | 선점(§2), 결제 시작 커밋 후(§4) |
| `saga_instance.timeout_at` | 선점(§2), 결제 시작(§4) |
| `waitlist.offer_deadline_at` | 취소표 제안(§9), 결제 시작(§4) |

PG 결과를 모르는 동안 Redis 키를 다시 거는 것(§6.2 `rehold.lua`)은 예외입니다. 그때는 DB 마감이 이미 지났고, 키는 다음 PG 조회 때까지 좌석을 지키는 용도입니다.

### 0.3 네이티브 UPDATE 규칙

JPA Auditing을 거치지 않는 모든 네이티브 UPDATE는 다음을 지킵니다.

- `updated_at = SYSTIMESTAMP`를 넣습니다 (`noUpdatedAt` 테이블 제외).
- `version` 컬럼이 있는 테이블(`reservation`, `app_policy`)은 `version = version + 1`을 넣습니다. 그래야 JPA 낙관적 락이 충돌을 감지합니다.
- 상태를 바꾸는 UPDATE는 **현재 상태를 WHERE에 넣고 영향 행 수를 확인**합니다. 기대한 행 수가 아니면 다른 트랜잭션이 먼저 처리한 것이므로, 그 뒤의 부수 작업(카운터 감소, 이벤트 발행)을 하지 않습니다.

### 0.4 한 트랜잭션 안의 락 순서

데드락은 두 트랜잭션이 같은 행들을 서로 다른 순서로 기다릴 때 생깁니다. 다음 규칙을 지킵니다.

1. **예약에 딸린 행은 그 예약의 reservation 행을 먼저 잠근 뒤에만 바꿉니다.** 예약에 딸린 행은 그 예약의 `seat_inventory`·`payment`·`saga_instance`·`reservation_seat`, 그 예약을 가리키는 `waitlist` 행입니다. reservation 락이 같은 예약의 트랜잭션을 줄 세우므로 이 행들 사이의 순서는 자유입니다.
2. **여러 예약을 잠글 때는 `reservation_id` 오름차순으로 한 건씩** 잠급니다 (§3-1). `WHERE reservation_id IN (…) ORDER BY … FOR UPDATE`는 Oracle이 정렬 전 접근 순서대로 잠그므로 순서를 보장하지 않습니다.
3. 새 `seat_inventory` 행은 `(run_id, seat_id, segment_no)` 오름차순으로 INSERT합니다. PK가 겹치는 다른 INSERT와 기다리는 순서를 맞춥니다.
4. `purchase_counter`는 `(scope, scope_ref_id, ci_hash)` 오름차순으로, 갱신할 행을 모아 한 번에 갱신합니다 (§10.3).
5. `waitlist`는 §9에서만 예약보다 먼저 잠그고, 항상 `SKIP LOCKED`라 기다리지 않습니다. §9가 잠그는 행은 `WAITING`이고, 1의 규칙으로 잠그는 행은 `OFFERED`라 서로 겹치지 않습니다.
6. 새 PK로 INSERT하는 행(`reservation_history`, `outbox_event`, `notification`, `cancellation`, `saga_instance` 생성)은 다른 트랜잭션과 겹치지 않으므로 순서 제약이 없습니다. 단 `outbox_event`는 §0.5대로 reservation 갱신 **뒤에** INSERT합니다.

`outbox_event`(발행 상태), `notification`(발송·확인 시각), `cancellation`(환불 상태·재판매 여부)은 나중에 UPDATE되므로 "INSERT만 하는 테이블"이 아닙니다. INSERT만 하는 테이블(`noUpdatedAt`)은 `processed_event`, `reservation_history`, `app_policy_history`뿐입니다.

### 0.5 이벤트 기록

상태를 바꾸는 트랜잭션은 같은 트랜잭션 안에서, **reservation 행을 INSERT·UPDATE한 뒤에** `outbox_event`를 INSERT합니다 (§11.1). reservation 행 락이 같은 예약의 트랜잭션을 줄 세우므로, `seq`가 커밋 순서와 같아집니다.

### 0.6 외부 호출

PG 호출, Kafka 발행 같은 네트워크 호출은 **DB 트랜잭션 밖**에서 합니다. 락을 쥔 채 외부 응답을 기다리지 않습니다.

### 0.7 시간

모든 시각은 `TIMESTAMP`(시간대 없음)에 Asia/Seoul 기준으로 저장합니다. 세 곳의 시간대를 모두 고정합니다.

| 위치 | 설정 | 안 하면 |
|---|---|---|
| Oracle 컨테이너 OS | `TZ=Asia/Seoul` | `SYSTIMESTAMP`는 DB 서버 OS 시간대 값입니다. `updated_at = SYSTIMESTAMP`처럼 TIMESTAMP 컬럼에 넣으면 그 시간대의 벽시계 값이 저장되므로, 컨테이너가 UTC면 9시간 이른 값이 들어갑니다 |
| JVM | `-Duser.timezone=Asia/Seoul`, `spring.jpa.properties.hibernate.jdbc.time_zone=Asia/Seoul` | 앱이 쓰는 `LocalDateTime`이 다른 기준이 됩니다 |
| DB 세션 | JDBC 세션 시간대 = JVM 시간대 | `pay_deadline_at < SYSTIMESTAMP` 비교 때 Oracle은 TIMESTAMP 컬럼을 세션 시간대로 해석합니다 |

- **마감 시각(`:d`)은 앱 시계 하나로 계산해 바인딩합니다** (§2, §4, §9). Redis `PXAT`에도 같은 값을 씁니다. DB의 `SYSTIMESTAMP`는 `updated_at`과 "이미 지났는가" 비교에만 씁니다. 서버 시계는 NTP로 맞춥니다.
- 기동 시 점검: `SELECT SESSIONTIMEZONE, SYSTIMESTAMP FROM dual`이 `+09:00`이어야 합니다 (T34).

---

## §1 멱등 처리

클라이언트는 버튼을 누를 때마다 UUID `idempotency_key`를 만들고, 재시도에는 같은 키를 씁니다.

1. `SET idem:{memberId}:{key} :newReservationId NX PX policy(idem.ttl_sec)*1000`
   - 성공: 새 예약으로 §2를 진행합니다.
   - 실패(이미 있음): `GET`으로 기존 `reservation_id`를 읽고 그 예약의 현재 상태를 돌려줍니다. DB에 행이 아직 없으면 "처리 중"(202)을 돌려줍니다.
2. DB 최종 방어: `UNIQUE(member_id, idempotency_key)`. `idem` TTL이 지난 뒤 같은 키로 다시 오면 1이 성공해 새 R2로 §2가 진행되고, INSERT가 ORA-00001로 실패합니다. 이때:
   - 롤백 후 **R2 기준으로 §2.3 보상**(seat:hold 해제, 한도 감소)을 합니다.
   - `idem` 키 값을 기존 예약 R1로 바꿔 둡니다 (`SET idem:… :R1 XX PX …`).
   - 기존 예약 R1을 조회해 그 상태를 돌려줍니다.
3. §2가 거절로 끝나면 `idem` 키를 compare-and-delete(§14.3)로 지웁니다. 거절된 요청을 같은 키로 다시 보내면 같은 판정을 다시 받습니다.

결제 요청도 같은 방식입니다. 키는 `idem:pay:{reservationId}:{key}`, DB 방어는 `UNIQUE(reservation_id, idempotency_key)`와 예약당 승인 1건 인덱스(`ux_payment_approved`)입니다.

취소표 제안(§9)은 시스템이 만드는 예약이라 `idem` Redis 키를 쓰지 않고, `idempotency_key = 'wl:' || waitlist_id`로 DB UNIQUE만 씁니다. 대기 신청 하나에서 제안 예약은 최대 하나입니다.

---

## §2 좌석 선점 (신규 예약)

**전제**: 유효한 `queue:pass:{runId}:{memberId}`가 있어야 합니다. 없으면 거절합니다. 예외는 취소표 제안(§9)으로, 시스템이 대기자 명의로 실행하므로 입장 토큰을 검사하지 않습니다.

### 2.1 Redis 단계

0. 1회 매수 한도: 요청 매수 n이 `PER_RESERVATION` 한도(§10.6) 이하인지 확인합니다. 카운터 없이 값 비교만 합니다.
1. §1로 `reservation_id` R을 받습니다 (시퀀스 또는 Snowflake).
2. 매수 한도 1차: `limit_incr.lua`(§14.2)로 `limit:{runId}:{ciHash}`, `limit:event:{saleEventId}:{ciHash}`를 n만큼 올립니다. 한도를 넘으면 스크립트가 되돌리고 0을 반환하며, §10.7 자가 복구를 한 번 거친 뒤에도 넘으면 거절합니다. 키가 없으면 스크립트가 `purchase_counter` 값으로 먼저 채웁니다 (§10.4).
3. 마감 `:d = 앱 시계 지금 + policy(reservation.pay_deadline_min)`을 계산합니다 (§0.7).
4. 좌석 경쟁: `hold.lua`로 예약할 모든 구간 키 `seat:hold:{runId}:{seatId}:{segNo}`를 R 값으로 `SET NX`하고 만료를 `PXAT :d`로 겁니다. 하나라도 다른 값이 있으면 전부 실패합니다.
   - **패배자**: 2번의 한도를 되돌리고(`limit_decr.lua`), `idem` 키를 지우고 "이미 선점된 좌석"으로 거절합니다. **DB 쓰기는 0건**입니다.

### 2.2 DB 트랜잭션 (승자만)

1. 이전 점유자 확인 (락 없음): `SELECT reservation_id, status, hold_expires_at FROM seat_inventory WHERE (run_id, seat_id, segment_no) IN (…)`.
   - 행이 없으면 **3으로** 갑니다.
   - `status = 'SOLD'`이거나 `hold_expires_at >= SYSTIMESTAMP`인 행이 있으면 거절합니다. Redis 키가 사라졌는데 DB 점유가 유효한 경우로, 정상이면 일어나지 않지만 DB가 최종입니다.
   - 만료된 HOLD만 있으면 **2(재선점)로** 갑니다.
2. (재선점일 때만) §3을 같은 트랜잭션에서 실행합니다.
3. `INSERT INTO reservation (… status = 'HOLD', pay_deadline_at = :d, idempotency_key, version = 0 …)`
4. `INSERT INTO seat_inventory` 구간마다 한 행 (`status = 'HOLD'`, `hold_expires_at = :d`, `reservation_id = R`, `train_id = 운행 열차`). 정렬 순서로 INSERT합니다. 행 수는 K(§2.4)입니다.
5. `INSERT INTO reservation_seat` 좌석마다 (승차권 번호 `ticket_no`는 이때 발급하지만, 확정 전에는 효력이 없음).
6. `purchase_counter` 증가: §10.1 (재선점이면 이전 예약의 감소와 함께 정렬 순서로).
7. `INSERT INTO reservation_history (from_status = NULL, to_status = 'HOLD', actor_type = 'USER')` (§9 제안이면 `'SYSTEM'`)
8. `INSERT INTO saga_instance (current_step = 'SEAT_HELD', status = 'RUNNING', timeout_at = :d)`
9. `INSERT INTO outbox_event (event_type = 'SEAT_HELD', partition_key = R, …)` (§11.1)
10. COMMIT

### 2.3 실패 처리

트랜잭션이 롤백되면 다음을 합니다. 원인은 한도 초과, PK 충돌, 제약 위반(§1-2의 ORA-00001 포함), DB 오류 등입니다.

- `release.lua`로 R 값인 `seat:hold` 키만 지웁니다 (compare-and-delete).
- `limit_decr.lua`로 R의 한도를 되돌립니다 (예약당 한 번만, §14.2).
- `idem` 키를 지웁니다 (§1-2 경우에는 지우지 않고 기존 예약 값으로 바꿈).

### 2.4 구간 행 수 K

한 예약이 가진 `seat_inventory` 행 수입니다. §4·§5가 영향 행 수를 이 값과 비교합니다.

- `K = seat_count × 구간 수`
- 구간 수 = 하차역 `train_stop.stop_order` − 승차역 `train_stop.stop_order`
- `policy(inventory.segment_mode) = 'OFF'`(지금 범위)면 구간은 하나(`segment_no = 0`)이므로 `K = seat_count`입니다.

K는 선점 때 계산해 쓰고, 이후에는 같은 식으로 다시 계산합니다 (예약의 `seat_count`·승하차역은 바뀌지 않음).

---

## §3 재선점 (만료된 HOLD 이어받기)

§2.2 트랜잭션 안에서, 만료된 HOLD 행의 이전 예약 R1, R2, … 를 처리합니다.

1. 이전 예약 잠금: ID를 앱에서 오름차순 정렬한 뒤 **한 건씩** 잠급니다 (§0.4-2).
   ```sql
   SELECT reservation_id, status, seat_count, ci_hash, run_id FROM reservation
    WHERE reservation_id = :Ri FOR UPDATE
   ```
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
5. R1의 `reservation_history`(HOLD → EXPIRED, `actor_type = 'SYSTEM'`), `saga_instance.status = 'COMPENSATED'`, outbox `RESERVATION_EXPIRED`(`partition_key = R1`, payload `reason = 'PREEMPTED'`)를 기록합니다.
6. 이어서 §2.2의 3~10을 진행합니다.
7. 커밋 후: R1의 Redis 정리(다른 좌석 키, `limit:*` 감소)는 §14.3의 커밋 후 보상으로 합니다. 5의 outbox 이벤트가 보장 경로이자 취소표 제안(§9)의 시작입니다.

---

## §4 결제 시작 (마감 연장)

### 4.1 DB 트랜잭션

1. 예약 전이 + 연장. 늘리기만 하고 줄이지 않습니다. 후보 마감 `:cand = 앱 시계 지금 + policy(payment.pg_timeout_sec) + policy(payment.extend_grace_sec)`를 앱에서 계산합니다 (§0.7).
   ```sql
   UPDATE reservation
      SET status = 'PAYMENT_PENDING',
          pay_deadline_at = GREATEST(pay_deadline_at, :cand),
          updated_at = SYSTIMESTAMP, version = version + 1
    WHERE reservation_id = :R AND member_id = :me AND status = 'HOLD' AND pay_deadline_at > SYSTIMESTAMP
   ```
   - 0행이면 이미 결제 중, 만료됨, 또는 남의 예약이므로 거절합니다. HOLD에서 PAYMENT_PENDING으로는 한 번만 바뀌므로 연장도 한 번만 일어납니다.
2. 새 마감 `:d`를 읽습니다 (`RETURNING pay_deadline_at INTO :d`).
3. 좌석 소유·만료 재확인 겸 복사:
   ```sql
   UPDATE seat_inventory SET hold_expires_at = :d, updated_at = SYSTIMESTAMP
    WHERE reservation_id = :R AND status = 'HOLD'
   ```
   영향 행 수가 K(§2.4)와 다르면 좌석을 이미 잃은 것이므로 롤백하고 거절합니다.
4. `UPDATE saga_instance SET current_step = 'PAYING', timeout_at = :d, updated_at = SYSTIMESTAMP WHERE reservation_id = :R AND status = 'RUNNING'`
5. 취소표 제안 예약(`source = 'WAITLIST'`)이면 제안 기한도 함께 늘립니다 (§0.2).
   ```sql
   UPDATE waitlist SET offer_deadline_at = :d, updated_at = SYSTIMESTAMP
    WHERE offered_reservation_id = :R AND status = 'OFFERED'
   ```
6. `INSERT INTO payment (status = 'REQUESTED', idempotency_key, next_check_at = :d, …)` (§1). `next_check_at`은 §6.2 스캐너가 PG에 결과를 물어볼 시각입니다.
7. `reservation_history`(HOLD → PAYMENT_PENDING), outbox `PAYMENT_STARTED`
8. COMMIT

### 4.2 커밋 후

1. `extend.lua`로 R의 모든 `seat:hold` 키를 값이 R일 때만 `PEXPIREAT :d`로 연장합니다.
2. PG 승인 요청을 보냅니다 (트랜잭션 밖). 즉시 실패 응답이면 §5.2, 승인 응답이면 §5.1입니다.

---

## §5 결제 결과 처리

PG 승인 응답, 콜백, §6.2의 PG 조회 결과를 받았을 때 실행합니다. 같은 결과가 여러 번 와도 안전해야 합니다. **payment 상태를 바꾸는 모든 트랜잭션은 그 예약의 reservation 행을 먼저 잠급니다** (§0.4-1). 그래야 승인·실패·스캐너가 같은 결제를 동시에 바꾸지 않습니다.

### 5.1 승인

1. `SELECT status FROM reservation WHERE reservation_id = :R FOR UPDATE`
2. `SELECT status FROM payment WHERE payment_id = :P` (락은 1의 reservation 락으로 충분)
3. payment 상태로 갈래를 나눕니다.

   | payment.status | 예약 상태 | 처리 |
   |---|---|---|
   | `REQUESTED` | `PAYMENT_PENDING` | 정상 확정: 4로 |
   | `APPROVED` | `CONFIRMED` | 이미 확정. 그대로 성공을 돌려줍니다 (멱등) |
   | `APPROVED` | 그 외 | 이미 늦은 승인 환불 중(아래 "확정 실패" 경로). "환불 진행 중"을 돌려주고 아무것도 바꾸지 않습니다 |
   | `REFUNDED` | 무관 | "환불 완료"를 돌려줍니다 |
   | `FAILED` | 무관 | **늦은 승인**입니다. §6.2나 §5.2가 실패로 정리한 뒤 승인이 온 경우로, 돈은 빠져나갔는데 예약은 이미 풀렸습니다. 같은 트랜잭션에서 `UPDATE payment SET status = 'APPROVED', pg_tx_id = :tx, approved_at = SYSTIMESTAMP, updated_at = SYSTIMESTAMP WHERE payment_id = :P AND status = 'FAILED'`를 하고 §7.3 늦은 승인 환불을 시작합니다. 예약은 되살리지 않습니다 (좌석은 이미 다른 사람에게 갔을 수 있음) |

4. 좌석 확정. K(§2.4)행이 갱신돼야 성공입니다.
   ```sql
   UPDATE seat_inventory SET status = 'SOLD', hold_expires_at = NULL, updated_at = SYSTIMESTAMP
    WHERE reservation_id = :R AND status = 'HOLD'
   ```
5. 결제 승인 기록 (1행이어야 함):
   ```sql
   UPDATE payment SET status = 'APPROVED', pg_tx_id = :tx, approved_at = SYSTIMESTAMP, updated_at = SYSTIMESTAMP
    WHERE payment_id = :P AND status = 'REQUESTED'
   ```
6. 예약 확정:
   ```sql
   UPDATE reservation SET status = 'CONFIRMED', confirmed_at = SYSTIMESTAMP, updated_at = SYSTIMESTAMP, version = version + 1
    WHERE reservation_id = :R AND status = 'PAYMENT_PENDING'
   ```
7. `saga_instance`(`current_step = 'CONFIRMED'`, `status = 'DONE'`), `reservation_history`(PAYMENT_PENDING → CONFIRMED), outbox `RESERVATION_CONFIRMED`
8. `reservation.source = 'WAITLIST'`면 `UPDATE waitlist SET status = 'ACCEPTED', updated_at = SYSTIMESTAMP WHERE offered_reservation_id = :R AND status = 'OFFERED'`
9. COMMIT
10. 커밋 후 `sold.lua`로 R의 모든 `seat:hold` 키를 `SOLD:R`로 **덮어쓰고**, 만료를 운행 출발 시각으로 겁니다. 키가 사라졌거나 다른 값이어도 DB가 확정했으므로 덮어씁니다.

**확정 실패** (4 또는 6이 기대 행 수가 아님. 좌석을 잃었거나 예약이 이미 풀림): 전체를 롤백합니다. 별도 트랜잭션에서 1처럼 reservation을 잠근 뒤 `payment`를 `REQUESTED`일 때만 `APPROVED`로 기록하고 §7.3 늦은 승인 환불을 시작합니다. 예약이 아직 `PAYMENT_PENDING`이면 같은 트랜잭션에서 §7.1(`from = 'PAYMENT_PENDING'`, `to = 'EXPIRED'`)도 실행합니다. 이 경로는 §4의 연장과 §6의 PG 조회가 있으므로 마지막 안전망입니다.

### 5.2 실패

PG가 승인을 거절했거나, §6.2가 실패·없음으로 판단했을 때입니다. **결제 실패는 예약 만료로 처리합니다.** 사용자는 다시 예매합니다. 결제 재시도를 허용하면 매번 마감이 연장돼 좌석을 오래 붙잡을 수 있기 때문입니다. 별도의 `PAYMENT_FAILED` 예약 상태는 두지 않고, 원인은 `payment.status = 'FAILED'`와 outbox payload의 `reason`으로 남깁니다.

1. `SELECT status FROM reservation WHERE reservation_id = :R FOR UPDATE`
2. 실패 기록:
   ```sql
   UPDATE payment SET status = 'FAILED', fail_reason = :reason, updated_at = SYSTIMESTAMP
    WHERE payment_id = :P AND status = 'REQUESTED'
   ```
   0행이면 다른 경로가 이미 처리한 것이므로 커밋하고 끝냅니다.
3. 1행이고 예약이 `PAYMENT_PENDING`이면 같은 트랜잭션에서 §7.1(`from = 'PAYMENT_PENDING'`, `to = 'EXPIRED'`, `reason = 'PAY_FAILED'`)을 실행합니다.
4. COMMIT

---

## §6 만료 스캐너

주기적으로 실행합니다. **HOLD 만료와 PG 결과 확인을 서로 다른 쿼리로** 나눠, PG 결과를 모르는 결제가 아무리 쌓여도 HOLD 만료가 밀리지 않게 합니다 (T27).

### 6.1 HOLD 만료

```sql
SELECT reservation_id FROM reservation
 WHERE (CASE WHEN status = 'HOLD' THEN pay_deadline_at END) < SYSTIMESTAMP
```

인덱스 `ix_resv_hold_due`와 같은 식입니다. 최대 N건을 읽고, 건마다 §7.1(`from = 'HOLD'`, `to = 'EXPIRED'`, `reason = 'TIMEOUT'`)을 실행합니다.

### 6.2 결제 결과 확인

```sql
SELECT payment_id, reservation_id, requested_at FROM payment
 WHERE (CASE WHEN status = 'REQUESTED' THEN next_check_at END) < SYSTIMESTAMP
```

인덱스 `ix_pay_recheck`와 같은 식입니다. `next_check_at`은 §4에서 마감 `:d`로 시작하므로, 마감이 지난 결제 중 예약만 나옵니다. 건마다 PG에 조회합니다 (트랜잭션 밖).

| PG 결과 | 처리 |
|---|---|
| 승인됨 | §5.1. 결제 중인 좌석은 §3 재선점 대상이 아니므로 아직 이 예약 소유입니다 |
| 실패 | §5.2 |
| 없음 (PG가 요청을 받은 적 없음) | 먼저 PG에 그 주문의 취소(승인 차단)를 요청합니다. 취소가 확인되면 §5.2. 취소 요청이 실패하면 "모름"으로 처리합니다 |
| 모름·PG 장애 | 아래 |

**모름**일 때는 자동으로 만료시키지 않습니다.

1. 다음 조회 시각을 미룹니다: `UPDATE payment SET next_check_at = :now + policy(payment.pg_recheck_sec), updated_at = SYSTIMESTAMP WHERE payment_id = :P AND status = 'REQUESTED'` (`:now`는 앱 시계). 이 행은 그때까지 후보에서 빠집니다.
2. 좌석을 계속 지킵니다: `rehold.lua`로 R의 `seat:hold` 키를 값이 R이거나 없을 때만 R로 다시 걸고, 만료를 새 `next_check_at` + `policy(payment.pg_recheck_sec)`로 겁니다. DB 마감이 지나 Redis 키가 사라지면 다른 사용자가 Redis 경쟁에서 이긴 뒤 §3에서 계속 롤백되므로, 그 헛도는 경쟁을 막습니다.
3. `requested_at`에서 `policy(payment.pg_unknown_max_min)`이 지나도 모르면 관리자 확인 대상으로 알림(로그·대시보드)을 보냅니다. 이후에도 조회는 계속합니다.

---

## §7 해제 (만료·결제 실패·결제 전 취소)

### 7.1 DB 트랜잭션

호출하는 곳과 값은 다음과 같습니다. 모든 해제는 빈 좌석 이벤트를 남겨 §9로 이어집니다.

| 호출 | :from | :to | outbox `event_type` | payload `reason` |
|---|---|---|---|---|
| §6.1 HOLD 만료 | HOLD | EXPIRED | `RESERVATION_EXPIRED` | `TIMEOUT` |
| §5.2 결제 실패 | PAYMENT_PENDING | EXPIRED | `RESERVATION_EXPIRED` | `PAY_FAILED` |
| §7.4 결제 전 사용자 취소 | HOLD | CANCELED | `RESERVATION_CANCELED` | `USER_BEFORE_PAY` |
| (§3 재선점은 §3 안에서 같은 단계를 직접 실행) | HOLD | EXPIRED | `RESERVATION_EXPIRED` | `PREEMPTED` |

1. 상태 전이. 1행일 때만 아래를 계속합니다 (0.3).
   ```sql
   UPDATE reservation SET status = :to, updated_at = SYSTIMESTAMP, version = version + 1
    WHERE reservation_id = :R AND status = :from
   ```
2. `DELETE FROM seat_inventory WHERE reservation_id = :R AND status = 'HOLD'`
3. `purchase_counter` 감소: §10.2
4. `saga_instance.status = 'COMPENSATED'`(`current_step`은 마지막 단계 그대로), `reservation_history`, outbox (위 표)
5. 취소표 제안으로 만든 예약이면 `UPDATE waitlist SET status = 'EXPIRED', updated_at = SYSTIMESTAMP WHERE offered_reservation_id = :R AND status = 'OFFERED'`
6. COMMIT

만료는 돈이 오가지 않았으므로 `cancellation`을 만들지 않습니다. 이력은 `reservation_history`에 남습니다.

### 7.2 커밋 후

§14.3의 커밋 후 보상(좌석 키를 `REOFFER:R`로, 한도 감소)을 합니다. 빈 좌석 이벤트는 outbox를 통해 §9가 받습니다.

### 7.3 늦은 승인 환불

결제는 승인됐는데 예약을 확정할 수 없는 경우입니다 (§5.1의 `FAILED` 갈래, 확정 실패 경로). payment를 `APPROVED`로 기록한 트랜잭션에서 `cancellation`을 INSERT합니다.

| 컬럼 | 값 |
|---|---|
| `cancel_type` | `'PAY_FAILED'` |
| `canceled_at` | 지금 |
| `refund_amount` | `payment.amount` (전액) |
| `cancel_fee` | 0 |
| `fee_policy_id`, `minutes_after_purchase`, `minutes_before_departure` | NULL |
| `refund_status` | `'REQUESTED'` |
| `resold_yn` | `'N'` (§8.3 배치가 갱신) |

커밋 후 PG 환불을 요청합니다. 환불이 완료되면 한 트랜잭션에서 `refund_status = 'DONE'`, `refund_pg_tx_id`, `payment.status = 'REFUNDED'`를 기록합니다. 환불 요청이 실패하면 `refund_status = 'FAILED'`로 두고, 재시도 배치가 `REQUESTED`·`FAILED` 건을 다시 요청합니다.

### 7.4 결제 전 사용자 취소

- HOLD 예약: §7.1을 `from = 'HOLD'`, `to = 'CANCELED'`로 실행합니다.
- PAYMENT_PENDING 예약: "결제 진행 중"으로 거절합니다. PG 결과가 나온 뒤 취소합니다.

---

## §8 확정 예약 취소

### 8.1 DB 트랜잭션

사용자 취소(`USER`)와 관리자 취소(`ADMIN`)가 같은 절차를 씁니다.

1. 취소 전이:
   ```sql
   UPDATE reservation SET status = 'CANCELED', canceled_at = SYSTIMESTAMP, updated_at = SYSTIMESTAMP, version = version + 1
    WHERE reservation_id = :R AND status = 'CONFIRMED'
      AND (:actor = 'ADMIN' OR member_id = :me)
   ```
   1행일 때만 아래를 계속합니다.
2. `DELETE FROM seat_inventory WHERE reservation_id = :R AND status = 'SOLD'`
3. `purchase_counter` 감소: §10.2. **확정 예약도 집계 대상이므로 감소합니다.**
4. `cancellation` INSERT (`refund_status = 'REQUESTED'`, `resold_yn = 'N'`):
   - `USER`: `cancel_fee_policy`에서 출발까지 남은 분으로 수수료를 정합니다. `refund_amount = 결제 금액 − cancel_fee`, `fee_policy_id`, `minutes_after_purchase`, `minutes_before_departure`를 채웁니다.
   - `ADMIN`: 운영 사유 취소라 `cancel_fee = 0`, `refund_amount = 결제 금액`. 관리자와 사유는 `admin_action`에 남깁니다.
5. `reservation_history`(CONFIRMED → CANCELED, `actor_type = :actor`), outbox `RESERVATION_CANCELED`
6. COMMIT

### 8.2 커밋 후

§14.3의 커밋 후 보상을 합니다. 좌석 키는 지우지 않고 `REOFFER:R`로 바꿔 **대기자에게 먼저** 제안합니다 (§9). PG 환불을 요청하고, 완료·실패 기록은 §7.3과 같습니다.

### 8.3 재판매 여부

운행이 출발한 뒤 배치가 그 운행의 `cancellation`마다 `resold_yn`을 정합니다. 취소된 예약의 좌석·구간 중 하나라도 다른 예약이 `SOLD`로 가졌으면 `'Y'`입니다. 출발 전에는 재판매가 계속 바뀌므로 `'N'`으로 둡니다.

---

## §9 취소표 제안

빈 좌석 이벤트(`RESERVATION_CANCELED`, `RESERVATION_EXPIRED`)를 소비 그룹 `seat-release`가 받아 실행합니다. 이 소비자가 커밋 후 Redis 보상의 보장 경로(§14.3)도 맡습니다.

**배정 원칙: 대기자 먼저.** 확정 취소(§8)나 결제 실패·결제 전 취소로 풀린 좌석은 Redis 키가 `REOFFER:R`로 남아 일반 사용자의 `hold.lua`를 막습니다. 대기자에게 제안하고, 맞는 대기자가 없을 때만 일반 판매로 돌립니다. HOLD 만료로 풀린 좌석은 Redis 키가 이미 TTL로 사라졌으므로 일반 사용자와 동시에 열립니다. 이벤트가 늦어도 `REOFFER` 키는 `policy(waitlist.reoffer_hold_sec)` 뒤 사라지므로 좌석이 오래 막히지 않습니다.

### 9.1 순서와 트랜잭션 경계

이벤트 하나를 DB 트랜잭션 T 하나로 처리합니다. T 안에 `processed_event`, SKIPPED 갱신, 제안 예약 쓰기가 모두 들어갑니다. T가 롤백되면 이벤트가 다시 전달되고 처음부터 다시 판단합니다.

1. Redis 보상 (T 밖, 멱등): `reoffer.lua`로 풀린 예약 R의 좌석 키를 `REOFFER:R`로, `limit_decr.lua`로 R의 한도를 감소합니다 (§14.2). 이미 한 번 했으면 아무 일도 일어나지 않습니다.
2. T 시작. `INSERT INTO processed_event (consumer_group = 'seat-release', event_id, processed_at)`. ORA-00001이면 이미 처리한 이벤트이므로 커밋하고 끝냅니다 (§12).
3. 빈 좌석·구간을 이벤트 payload(운행, 좌석 ID, 승하차역)로 정합니다.
4. 대기자 조회 (인덱스 `ix_waitlist_next`):
   ```sql
   SELECT waitlist_id, member_id, from_station_id, to_station_id, seat_grade, seat_count FROM waitlist
    WHERE run_id = :r AND status = 'WAITING' ORDER BY requested_at
      FOR UPDATE SKIP LOCKED
   ```
   한 건씩 fetch합니다. `SKIP LOCKED`는 fetch할 때 행을 잠그므로 읽은 행만 잠깁니다. 다른 인스턴스가 잡은 대기자는 건너뜁니다.
5. 대기자마다:
   - 구간·등급·매수가 빈 좌석에 맞지 않으면 다음 대기자로 넘어갑니다 (변경 없음).
   - 매수 한도(§10.6의 1회 한도, `limit_incr.lua`)에 걸리면 `UPDATE waitlist SET status = 'SKIPPED', updated_at = SYSTIMESTAMP WHERE waitlist_id = :w AND status = 'WAITING'`(T 안)을 하고 다음 대기자로 넘어갑니다.
   - 맞으면 6으로 갑니다.
6. 그 대기자 명의로 §2를 실행합니다. 다른 점은 다음과 같습니다.
   - 입장 토큰(`queue:pass`)을 검사하지 않습니다.
   - `idempotency_key = 'wl:' || waitlist_id`, `source = 'WAITLIST'`, `actor_type = 'SYSTEM'`
   - `hold.lua`에 인계 값 `REOFFER:R`을 넘겨, 그 값인 키는 비어 있는 것으로 보고 새 예약 R'로 덮어씁니다. 실패하면(REOFFER가 만료돼 일반 사용자가 먼저 잡음) R'의 한도를 되돌리고 9로 갑니다.
   - **제안 예약도 `purchase_counter`를 증가시킵니다.**
   - §2.2 쓰기와 함께 T 안에서 다음을 실행합니다 (1행이어야 함). `notification`(`type = 'WAITLIST_OFFER'`)도 INSERT합니다.
     ```sql
     UPDATE waitlist SET status = 'OFFERED', offered_at = SYSTIMESTAMP, offer_deadline_at = :d,
            offered_reservation_id = :R2, updated_at = SYSTIMESTAMP
      WHERE waitlist_id = :w AND status = 'WAITING'
     ```
7. 빈 좌석이 남았으면 5부터 다음 대기자로 계속합니다.
8. 더 이상 맞는 대기자가 없으면 남은 `REOFFER:R` 키를 `release.lua`로 지워 일반 판매로 돌립니다.
9. COMMIT. 실패하면 R'에 대해 §2.3 보상을 하고(좌석 키는 지워져 일반 판매로 열림), 이벤트 재전달을 기다립니다.

### 9.2 수락과 만료

수락은 결제(§4, §5)입니다. 결제 시작 때 `offer_deadline_at`도 함께 연장됩니다(§4-5). 기한이 지나면 §6 → §7이 예약을 만료시키고 `waitlist`는 `EXPIRED`가 됩니다. 그 빈 좌석 이벤트로 다음 대기자에게 다시 제안합니다.

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
- `:max`는 §10.6으로 고른 값입니다. 같은 요청 안에서는 Redis 판정(§2.1)과 같은 값을 씁니다.

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

### 10.6 한도 값 고르기

`purchase_limit_policy`에서 scope별로 하나를 고릅니다.

1. 후보: 지금 시각이 `valid_from` ~ `valid_to` 안인 행 (NULL은 제한 없음).
2. 그 운행의 `sale_event_id`와 같은 행사 정책이 있으면 그것을, 없으면 상시 정책(`sale_event_id IS NULL`)을 씁니다.
3. 같은 조건의 행이 여러 개면 가장 작은 `max_seats`를 씁니다.

| scope | 검사 위치 | 정책이 없으면 |
|---|---|---|
| `PER_RESERVATION` | §2.1-0 (요청 매수 n과 비교, 카운터 없음) | 제한 없음 |
| `PER_RUN` | §2.1-2, §10.1 | 제한 없음 |
| `PER_HOLIDAY` | §2.1-2, §10.1. 운행에 `sale_event_id`가 있고 그 행사 정책이 있을 때만 | 적용 안 함 |

### 10.7 Redis 한도 자가 복구

커밋 후 보상이 끝내 유실되면 `limit:*`가 DB보다 크게 남아 정상 사용자를 막을 수 있습니다 (§0.1 위반). 그래서 `limit_incr.lua`가 한도 초과로 0을 반환하면 한 번만 DB와 대조합니다.

1. `purchase_counter`에서 해당 scope의 `seat_count`를 읽습니다 (행이 없으면 0).
2. `seat_count + n <= max`면 Redis 값이 틀린 것입니다. `SET limit:… seat_count`로 맞춘 뒤 `limit_incr.lua`를 한 번 다시 실행합니다.
3. 그래도 넘으면 거절합니다.

진행 중인 다른 요청의 증가분까지 덮어써 Redis 값이 낮아질 수 있지만, 최종 판정은 DB 카운터(§10.1)이므로 초과 판매는 생기지 않습니다.

---

## §11 outbox 기록·릴레이

### 11.1 기록

```sql
INSERT INTO outbox_event (event_id, seq, aggregate_type, aggregate_id, partition_key, shard_no, event_type, payload, status, retry_count)
VALUES (:uuid, outbox_seq.NEXTVAL, :type, :aggId, :pkey, ORA_HASH(TO_CHAR(:pkey), 15), :evt, :json, 'PENDING', 0)
```

- 예약 흐름의 `partition_key`는 항상 `reservation_id`입니다.
- `:pkey`는 **항상 문자열로 바인딩**하고 식에서도 `TO_CHAR`로 감쌉니다. `ORA_HASH`는 NUMBER와 VARCHAR2의 해시가 다르므로, 코드 경로마다 타입이 다르면 같은 예약의 이벤트가 다른 샤드로 가서 순서가 깨집니다 (T32).
- 상태를 바꾸는 트랜잭션 안에서, reservation 행 UPDATE·INSERT **뒤에** 실행합니다 (0.5). 같은 예약의 다음 트랜잭션은 reservation 행 락에서 기다리므로, 다음 이벤트의 `seq`가 항상 더 큽니다.

### 11.2 샤드 담당 (리스)

샤드는 16개로 고정합니다 (`policy(outbox.shard_count)`, `shard_no` CHECK와 같아야 함). 릴레이 인스턴스는 샤드마다 Redis 리스를 잡은 샤드만 처리합니다.

- 획득: `SET relay:shard:{n} :instanceId NX PX policy(relay.lease_sec)*1000`
- 갱신: 리스 시간의 1/3마다 `extend.lua`로 값이 자기 ID일 때만 연장합니다.
- 갱신에 실패하면 **그 샤드 처리를 즉시 멈춥니다.**
- 인스턴스 수가 바뀌어도 리스가 끝나기 전에는 다른 인스턴스가 그 샤드를 가져가지 못합니다.

### 11.3 조회와 발행

Oracle은 `SELECT … FOR UPDATE` 커서를 **여는 순간 조건에 맞는 행 전체**를 잠급니다. fetch 건수로 줄지 않으므로, 적체가 수만 건이면 수만 행이 잠깁니다. 그래서 먼저 맨 앞 N개의 rowid만 뽑고 그 행만 잠급니다.

```sql
SELECT event_id, seq, status, partition_key, event_type, payload, retry_count FROM outbox_event
 WHERE rowid IN (
         SELECT rid FROM (
           SELECT rowid AS rid FROM outbox_event
            WHERE (CASE WHEN status IN ('PENDING', 'FAILED') THEN shard_no END) = :n
            ORDER BY (CASE WHEN status IN ('PENDING', 'FAILED') THEN seq END))
          WHERE ROWNUM <= policy(outbox.relay_batch))
   AND status IN ('PENDING', 'FAILED')
 ORDER BY seq
   FOR UPDATE WAIT policy(relay.lock_wait_sec)
```

- 안쪽 쿼리는 정렬한 뒤 `ROWNUM`으로 자르므로 맨 앞 N개가 정확히 뽑힙니다. 바깥의 `status` 조건은 락을 기다리는 동안 이전 담당자가 발행을 끝낸 행을 빼기 위한 것입니다.
- **`SKIP LOCKED`를 쓰지 않습니다.** 리스가 넘어가는 순간 이전 담당자가 잡은 앞 행을 건너뛰면 순서가 깨집니다. 기다리다 시간이 지나면 이번 회차를 포기합니다.
- 맨 앞 행이 `FAILED`면 §11.4대로 이 샤드를 처리하지 않습니다.
- `seq` 순서대로 하나씩 발행합니다.
  - Kafka 프로듀서: `enable.idempotence=true`, `acks=all`, `max.in.flight.requests.per.connection ≤ 5`
  - 성공: `UPDATE outbox_event SET status = 'PUBLISHED', published_at = SYSTIMESTAMP, updated_at = SYSTIMESTAMP WHERE event_id = :id`
  - 실패: `retry_count = retry_count + 1`(한도에 도달하면 `status = 'FAILED'`도)로 갱신하고, **그 샤드의 이번 회차를 즉시 멈춥니다.** 같은 샤드의 다음 행은 같은 예약의 뒤 이벤트일 수 있으므로, 앞 행이 성공하기 전에는 발행하지 않습니다. 다음 회차에 그 행부터 다시 시도합니다.
- 배치마다 COMMIT합니다 (실패로 멈출 때도 그때까지 발행한 행과 retry_count를 커밋).

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

정리는 `processed_at < SYSTIMESTAMP - policy(inbox.retention_days)`인 행을 배치로 지웁니다 (인덱스 `ix_inbox_processed`). 보관 기간은 Kafka 보관 기간보다 **길어야** 재전달 중복을 막습니다. Kafka 기본 보관이 7일(`log.retention.hours=168`)이므로 `inbox.retention_days`는 8일입니다. Kafka 보관을 늘리면 이 값도 함께 늘립니다.

| 소비 그룹 | 이벤트 | 하는 일 |
|---|---|---|
| `seat-release` | `RESERVATION_CANCELED`, `RESERVATION_EXPIRED` | Redis 보상 보장 경로 + 취소표 제안 (§9) |
| 알림·로그 등 | 각자 | 각 기능 문서 |

---

## §13 MongoDB 적재·보관

### 13.1 적재

`behavior_log`와 `replay_event`는 앱이 Kafka에 보내고, 적재 컨슈머가 `insertMany`로 배치 저장합니다 (`policy(behavior.batch_size)`). `replay_event`는 `{session_id, seq}` 유니크 인덱스로 재전송 중복을 막습니다 (중복 키 오류는 무시).

### 13.2 보관 (`expire_at` + TTL `expireAfterSeconds: 0`)

| 컬렉션 | `expire_at` 계산 | 보류 |
|---|---|---|
| behavior_log | `ts` + `behavior.retention_days` (180일, 팀 확정) | 없음 |
| replay_session | `started_at` + `replay.retention_days` (`retention_until`과 같은 값) | `legal_hold = true`면 필드 없음 |
| replay_event | 세션의 `expire_at`과 같은 값 | 세션이 `legal_hold`면 필드 없음 |
| queue_log | `entered_at` + `queue_log.retention_days` | 없음 |
| evidence_snapshot | 케이스가 열려 있는 동안 필드 없음. 종료 시 `closed_at` + `evidence.retention_days` | 케이스 재개 시 필드 제거 |

- **컨슈머는 `replay_event`를 저장하기 전에 세션의 `legal_hold`를 확인**합니다. 캐시를 쓰되 TTL은 `policy(replay.hold_cache_sec)` 이하입니다. 보류 중이면 `expire_at` 없이 저장합니다.
- 보류를 걸 때:
  1. `replay_session.legal_hold = true` 저장
  2. 그 세션의 `replay_session`·`replay_event`에서 `$unset: {expire_at: ""}`
  3. **`policy(replay.hold_cache_sec)`가 지난 뒤 2를 한 번 더 실행합니다.** 캐시가 아직 "보류 아님"이던 창 동안 `expire_at`이 붙은 채 저장된 이벤트를 지웁니다. 지연 실행은 스케줄러(작업 큐)로 하고, 실패하면 재시도합니다 (T28).
- 보류를 풀 때: `expire_at = max(retention_until, 지금 + 1일)`로 다시 설정합니다. `retention_until`은 `$unset` 대상이 아니므로 원래 보관 기한이 그대로 남아 있습니다.

---

## §14 Redis 키와 Lua 스크립트

### 14.1 키

키 이름의 `{…}`는 자리표시자입니다 (머리말 참고).

| 키 | 값 | 만료 |
|---|---|---|
| `idem:{memberId}:{key}`, `idem:pay:{reservationId}:{key}` | reservation_id / payment_id | `idem.ttl_sec` |
| `queue:{runId}`, `queue:active:{runId}`, `queue:pass:{runId}:{memberId}` | 대기열 | `queue.pass_ttl_sec` |
| `seat:hold:{runId}:{seatId}:{segNo}` | `R`(HOLD), `SOLD:R`(확정), `REOFFER:R`(대기자 제안 대기) | `pay_deadline_at` / 운행 출발 시각 / `waitlist.reoffer_hold_sec` |
| `limit:{runId}:{ciHash}`, `limit:event:{saleEventId}:{ciHash}` | 보유 매수 | 운행 출발·행사 종료 |
| `limit:dec:{reservationId}` | 1 (이 예약의 한도 감소를 이미 했다는 표시) | 운행 출발·행사 종료 중 늦은 쪽 |
| `relay:shard:{n}` | 릴레이 인스턴스 ID | `relay.lease_sec` |
| `rate:login:{ipHash}`, `rate:api:{memberId}` | 횟수 | 짧은 창 |
| `risk:{subjectType}:{hash}`, `policy:cache`, `seatmap:{runId}` | 캐시 | |

### 14.2 스크립트

| 스크립트 | 동작 |
|---|---|
| `hold.lua` | KEYS 전부에 대해, 다른 값이 하나라도 있으면 0 반환. 아니면 전부 `SET 값 PXAT 만료` 후 1 반환. ARGV로 인계 값(`REOFFER:R`)을 받으면 그 값인 키는 비어 있는 것으로 봄 (§9 전용) |
| `release.lua` | KEYS 중 값이 ARGV[1]인 키만 DEL (compare-and-delete) |
| `extend.lua` | KEYS 중 값이 ARGV[1]인 키만 `PEXPIREAT` (결제 연장, 리스 갱신). 없는 키는 만들지 않음 |
| `rehold.lua` | KEYS 중 값이 R이거나 없는 키를 `SET R PXAT 만료` (§6.2 PG 결과 모름) |
| `sold.lua` | KEYS를 값과 상관없이 `SET SOLD:R PXAT 출발 시각` (DB가 확정했으므로 덮어씀) |
| `reoffer.lua` | KEYS 중 값이 R 또는 `SOLD:R`인 키만 `SET REOFFER:R PX reoffer_hold`. 없거나 다른 값이면 그대로 |
| `limit_incr.lua` | 키마다 없으면 `SET 복원값 NX`, 그 뒤 INCRBY n. 하나라도 한도를 넘으면 이번 증가분을 전부 DECRBY하고 0 반환 |
| `limit_decr.lua` | KEYS[1] = `limit:dec:{R}`. `SET NX PXAT`가 성공했을 때만 나머지 키를 DECRBY n (0 미만이면 0). **예약 하나에 한 번만 감소**하므로 빠른 경로와 보장 경로가 둘 다 실행돼도 안전 |

### 14.3 Redis 보상

**DB가 롤백됐을 때** (커밋 없음, §2.3): 그 자리에서 되돌립니다. `seat:hold`는 `release.lua`, `limit:*`는 `limit_decr.lua`, `idem`은 compare-and-delete입니다. 이 보상이 유실되면 seat 키는 HOLD 값이라 마감(최대 `reservation.pay_deadline_min`) 뒤 TTL로 사라지고, 한도는 다음 거절 때 §10.7이 바로잡습니다.

**DB가 커밋된 뒤** (§3, §7, §8): 같은 일을 두 경로로 합니다.

| 경로 | 언제 | 하는 일 |
|---|---|---|
| 빠른 경로 | 커밋 직후 앱이 바로 | `reoffer.lua`(좌석 키 → `REOFFER:R`), `limit_decr.lua` |
| 보장 경로 | 같은 트랜잭션의 outbox 빈 좌석 이벤트를 `seat-release`가 소비할 때 (§9.1-1) | 같은 두 스크립트 |

두 스크립트 모두 두 번 실행해도 결과가 같으므로(compare 조건, `limit:dec` 표시), 앱이 커밋 직후 죽어도 outbox가 다시 실행해 줍니다. 그래서 `SOLD:R`·`limit:*`가 출발 시각까지 남아 좌석을 못 팔거나 정상 사용자가 한도에 막히는 일이 없습니다. `REOFFER:R` 키는 §9가 대기자에게 넘기거나 지웁니다.

### 14.4 클러스터로 바꿀 경우

지금은 단일 노드 전제입니다. 클러스터에서는 한 Lua가 쓰는 키가 같은 슬롯이어야 하므로 해시 태그를 이렇게 바꿉니다. 여기서만 중괄호가 진짜 해시 태그입니다.

- 좌석: `seat:hold:{<runId>}:<seatId>:<segNo>`. 한 예약의 여러 좌석·구간이 같은 슬롯에 들어가도록 태그를 운행 단위로 통일합니다.
- 한도: `limit:{<ciHash>}:run:<runId>`, `limit:{<ciHash>}:event:<saleEventId>`, 표시 키 `limit:{<ciHash>}:dec:<reservationId>`. CI 단위 태그입니다.

`seat:hold`와 `limit`은 슬롯이 다르므로 지금처럼 다른 스크립트로 나눠 둡니다.

### 14.5 Redis 설정

| 설정 | 값 | 이유 |
|---|---|---|
| `maxmemory-policy` | `noeviction` | 메모리가 차도 `idem`·`seat:hold`·리스 키가 조용히 밀려나지 않게 합니다. 대신 쓰기 오류로 드러납니다 |
| `appendonly` | `yes` | 재시작 후 키를 되살립니다 |
| `appendfsync` | `everysec` | 최대 1초 유실. 한도는 §10.4·§10.7이, 좌석은 DB(§2.2-1)가 최종 판정이라 정합성은 유지됩니다 |
| 구성 | 단일 노드 | §14.4 |

---

## §15 시간 값 (예시, `app_policy`)

| 키 | 예시 | 쓰는 곳 |
|---|---|---|
| `reservation.pay_deadline_min` | 10 | §2 최초 마감 |
| `payment.pg_timeout_sec` | 180 | §4 연장 (앱카드·ISP 인증 시간 포함) |
| `payment.extend_grace_sec` | 60 | §4 연장 |
| `payment.pg_recheck_sec` | 60 | §6.2 PG 결과를 모를 때 다음 조회까지 |
| `payment.pg_unknown_max_min` | 30 | §6.2 결과 모름 알림 |
| `idem.ttl_sec` | 600 | §1 |
| `relay.lease_sec` | 15 | §11.2 |
| `relay.lock_wait_sec` | 5 | §11.3 |
| `outbox.max_retry` | 5 | §11.3 |
| `inbox.retention_days` | 8 | §12 (Kafka 보관 7일보다 길게) |
| `waitlist.reoffer_hold_sec` | 60 | §9 대기자 우선 보류 시간 |
| `behavior.retention_days` | 180 | §13.2 (팀 확정) |
| `replay.hold_cache_sec` | 30 | §13.2 legal_hold 캐시 TTL, 두 번째 `$unset` 지연 |
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
| T7 | PG 승인 지연 중 스캐너 실행 | 만료되지 않고 PG 조회 후 확정 | §6.2 |
| T8 | PG 장애로 결과 모름 | 자동 만료 없음, next_check_at 연기, seat:hold 유지, 알림 | §6.2 |
| T9 | 좌석을 잃은 뒤 승인 도착 | 롤백 + 환불 시작 | §5.1, §7.3 |
| T10 | 취소와 만료가 동시에 도착 | 한쪽만 처리, 카운터 한 번 감소 | §10.2 |
| T11 | 같은 CI 첫 예약 2건이 동시에 카운터 생성 | 한도 유지 (ORA-00001 재시도) | §10.1 |
| T12 | 서로 다른 CI 재선점 2건 교차 (이전 예약 집합이 겹치게) | 데드락 없음 | §3, §10.3 |
| T13 | DB가 한도 초과로 거절 | Redis hold·limit·idem 원복 | §2.3 |
| T14 | Redis 재시작 후 예약 | limit 복원 후 정상 판정 | §10.4 |
| T15 | 확정 예약 취소 | SOLD 행 삭제, 카운터 감소, 환불 요청, 좌석 키 REOFFER | §8 |
| T16 | 취소표 제안 시 대기자가 한도 초과 | SKIPPED 후 다음 대기자 | §9 |
| T17 | 인스턴스 2대가 같은 빈 좌석 이벤트 처리 | 대기자 한 명에게 한 번만 제안 | §9 |
| T18 | 같은 예약 이벤트 3개를 릴레이 2대가 처리 | seq 순서로 발행 | §11 |
| T19 | 이벤트 발행이 max_retry 실패 | FAILED, 그 샤드만 정지, 같은 예약 뒤 이벤트 미발행 | §11.4 |
| T20 | 릴레이 인스턴스 추가·제거 중 발행 | 리스 이동 중 순서 유지 | §11.2 |
| T21 | 같은 Kafka 메시지 2회 소비 | 업무 처리 1회 | §12 |
| T22 | legal_hold 이후 도착한 녹화 이벤트 | expire_at 없음 (삭제 안 됨) | §13.2 |
| T23 | 네이티브 UPDATE 후 JPA로 같은 예약 수정 | 낙관적 락 충돌 감지 | §0.3 |
| T24 | payment가 FAILED로 기록된 뒤 승인 도착 | APPROVED 기록 + PAY_FAILED 환불 시작, 예약은 풀린 그대로 | §5.1, §7.3 |
| T25 | 재시도 한도 미만 발행 실패 | 그 샤드 이번 회차 즉시 중단, 같은 예약 뒤 이벤트 미발행 | §11.3 |
| T26 | 취소 커밋 직후 앱 종료 (빠른 경로 Redis 보상 유실) | seat-release 소비로 좌석 키·한도 복구 | §14.3 |
| T27 | PG 결과를 모르는 결제가 N건을 넘음 | HOLD 만료가 계속 처리됨 | §6 |
| T28 | legal_hold를 건 직후 캐시 창 안에 도착한 이벤트 | 두 번째 $unset 후 expire_at 없음 | §13.2 |
| T29 | 만료된 예약에 대한 승인 콜백 재전송 | "성공"이 아니라 "환불 진행 중" | §5.1 |
| T30 | 확정 예약 취소 직후 일반 사용자가 그 좌석 선점 | 대기자 제안 전에는 Redis에서 거절, 대기자 없으면 해제 후 성공 | §9 |
| T31 | idem TTL이 지난 뒤 같은 키로 선점 재요청 | 기존 예약 반환, 새 요청의 hold·limit 원복 | §1 |
| T32 | 같은 예약의 이벤트를 숫자·문자열로 바인딩해 INSERT | 같은 shard_no | §11.1 |
| T33 | limit:*가 DB 카운터보다 큼 (보상 유실 흉내) | 다음 요청에서 자가 복구 후 정상 판정 | §10.7 |
| T34 | 기동 점검 | SESSIONTIMEZONE·SYSTIMESTAMP가 +09:00 | §0.7 |
| T35 | 같은 대기자에게 이벤트 재전달 | 제안 예약 1건 (`wl:` 키 UNIQUE) | §1, §9 |

---

## §17 비교 실험과 지표 정의

기획서의 성능 비교와 성과 지표를 측정 가능한 형태로 정의합니다. 부하는 k6 시나리오 하나를 고정하고 비교 대상만 바꿉니다.

### 17.1 좌석 선점 방식 비교

| 비교군 | 방식 | 구현 |
|---|---|---|
| A 비관적 락 | 운행 좌석 행을 미리 만들고 `SELECT … FOR UPDATE` 후 상태 변경 | 실험용 전략 클래스 |
| B 낙관적 락 | 같은 행에 `version` 조건부 UPDATE, 실패 시 재시도 | 실험용 전략 클래스 |
| C 현재 설계 | Redis `hold.lua` 1차 + DB PK 최종 (§2) | 본 구현 |

- 시나리오: 같은 좌석 100·1000명 동시, 인기 운행 하나에 몰림, 운행 여러 개에 고르게 분산
- 측정: TPS, 응답 p95·p99, 중복 예약 수(모두 0이어야 함), DB 쓰기 수, 락 대기 시간, 오류율
- `SeatHoldStrategy` 같은 인터페이스 뒤에 두고 설정으로 바꿉니다.

### 17.2 Kafka 메시지 키 비교

| 비교군 | partition_key |
|---|---|
| 현재 | `reservation_id` |
| 비교 | `run_id` (열차 운행 단위) |

- 측정: 파티션별 메시지 수의 최대/평균(쏠림), 인기 운행의 컨슈머 지연 p95, 같은 예약 이벤트의 순서 위반 수
- 실험에서만 설정으로 키를 바꿉니다. `shard_no`도 partition_key에서 계산되므로 릴레이 순서 보장은 그대로입니다.

### 17.3 지표 정의

| 지표 | 정의 |
|---|---|
| 좌석 복구율 | 자동 복구 대상(PG 결과가 실패·없음으로 확정됐거나 기한이 지난 HOLD) 중 좌석 행·Redis 키·한도가 모두 복구된 비율. 목표 100% |
| PG 결과 모름 | 복구율 분모에서 빼고, 건수와 관리자 처리까지 걸린 시간으로 따로 보고 |
| 중복 예약·중복 결제 | 같은 좌석·구간의 SOLD 행 2개 이상 / 예약당 APPROVED 2개 이상. 목표 0 |
| 재배정 순서 보장 | 대기자 제안 순서가 `requested_at` 순서와 다른 건수 (SKIPPED·조건 불일치 제외). 목표 0 |
