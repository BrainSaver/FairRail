# FairRail 데이터 컬럼 명세

명절 열차 공정 예매 시스템의 테이블·컬렉션·Redis 키 명세서입니다.
`출처` 열의 **공공**은 공공데이터포털 값을 그대로 적재, **생성**은 가상 데이터로 생성, **시스템**은 서비스가 실행 중에 기록하는 값입니다.

---

## 0. 설계 재검토 결과

1차 초안을 기획서의 핵심 과제(중복 예약 0건, 순서 보장, 구간 재고, 위험 점수)에 맞춰 다시 점검하고 아래처럼 고쳤습니다.

| # | 1차 초안의 문제 | 변경 | 이유 |
|---|---|---|---|
| 1 | `train_schedule` 하나에 열차 정의와 운행 날짜가 섞여 있음 | `train`(열차 정의) + `train_run`(날짜별 운행)으로 분리 | 같은 101열차가 설·추석에 반복 운행됨. 좌석 재고는 날짜별로 따로 관리해야 함 |
| 2 | 좌석이 열차에 붙어 있어 날짜별 재고 구분 불가 | 물리 좌석 `seat`은 열차 기준, 판매 재고 `seat_inventory`는 `train_run` 기준 | 좌석 배치는 고정, 판매 상태만 날짜별로 바뀜 |
| 3 | 중복 예약 방지를 애플리케이션 락에만 의존 | `seat_inventory`에 `(run_id, seat_id, segment_no)` UNIQUE 제약 | 락이 실패해도 DB가 최종 방어선. "중복 0건"을 구조적으로 보장 |
| 4 | 구간 재고가 예약 테이블의 from/to 범위로만 표현됨 | 구간을 `segment_no`(인접 역 사이 1칸) 단위 행으로 저장 | 서울→대전, 대전→부산 재판매 시 겹침 검사가 단순 UNIQUE 체크로 끝남. 확장 과제 미진행 시엔 전 구간 1행으로 사용 |
| 5 | Kafka 소비자 측 중복 처리 방어 없음 | `processed_event`(Inbox) 추가 | Kafka는 at-least-once. Outbox로 발행 보장 + Inbox로 중복 소비 방지가 한 쌍 |
| 6 | 상태 변경 이력이 없음 | `reservation_history` 추가 | "상태 변경 순서 보장"을 테스트로 증명하려면 이력이 필요 |
| 7 | 1인 매수 제한 기준이 계정 단위 | `purchase_limit_policy` + `ci_hash` 기준 집계 | 다계정 우회 방지. 기획서의 "계정이 아닌 인증 정보 단위" 원칙과 일치 |
| 8 | 결제 금액이 운임 테이블 참조뿐 | `reservation.total_amount`에 예약 시점 금액 저장 | 운임이 바뀌어도 과거 결제 금액 보존 |
| 9 | 정답 라벨 `user_type`이 회원 테이블에 섞임 | 별도 `synthetic_label` 테이블로 분리 | 운영 스키마와 실험용 정답을 분리해야 서비스 로직이 라벨을 참조하는 실수 방지 |
| 10 | 대기열 구조 미정의 | Redis 키 명세 + MongoDB `queue_log` 추가 | 순번 조정이 의도대로 됐는지 사후 검증 가능 |
| 11 | 알림·관리자 조치 기록 없음 | `notification`, `admin_action` 추가 | 취소표 재배정 알림 흐름, "관리자 검토 후 조치" 운영 원칙 근거 |

---

## 1. 공통 규칙

| 항목 | 규칙 | 이유 |
|---|---|---|
| PK | `NUMBER(19)` 시퀀스 또는 Snowflake ID | 분산 환경에서 ID 충돌 방지, Kafka 키로 사용 |
| 시간 | `TIMESTAMP`, KST 저장 | 결제 기한·취소 시간 계산 일관성 |
| 공통 컬럼 | 모든 테이블에 `created_at`, `updated_at` | 디버깅, 트러블슈팅 문서화 |
| 식별 정보 | `*_hash`는 HMAC-SHA256(비밀 솔트) | 원문 미보관, 같은 값끼리만 묶임 |
| 상태값 | `VARCHAR2` 코드 + 코드표 문서화 | Enum 추가 시 스키마 변경 불필요 |
| 금액 | `NUMBER(10)` 원 단위 | 부동소수점 오차 방지 |

---

## 2. 기준 데이터 (Oracle)

### 2-1. `station` 역

| 컬럼 | 타입 | 출처 | 설명 | 이유 |
|---|---|---|---|---|
| station_id | VARCHAR2(10) PK | 공공 | 역 코드 | 공공데이터 코드 그대로 써야 다른 데이터와 조인 가능 |
| station_name | VARCHAR2(50) | 공공 | 역 이름 | 화면 표시 |
| latitude | NUMBER(9,6) | 공공 | 위도 | 선택. 지도·관리자 화면 |
| longitude | NUMBER(9,6) | 공공 | 경도 | 선택 |

### 2-2. `route` 노선

| 컬럼 | 타입 | 출처 | 설명 | 이유 |
|---|---|---|---|---|
| route_id | NUMBER PK | 생성 | 노선 ID | |
| route_name | VARCHAR2(50) | 공공 | 노선명 (예: 경부선) | |
| origin_station_id | VARCHAR2(10) FK | 공공 | 기점역 | |
| dest_station_id | VARCHAR2(10) FK | 공공 | 종점역 | |

### 2-3. `route_station` 노선별 역 순서

| 컬럼 | 타입 | 출처 | 설명 | 이유 |
|---|---|---|---|---|
| route_id | NUMBER PK, FK | 생성 | 노선 | |
| station_id | VARCHAR2(10) PK, FK | 공공 | 역 | |
| station_order | NUMBER(3) | 공공 | 노선 내 순번 (1부터) | **구간 재고의 핵심.** 인접 순번 사이가 1개 segment |
| distance_from_origin_km | NUMBER(7,1) | 공공 | 기점부터 누적 거리 | 운임 계산, 구간 거리 = 두 역 누적거리 차 |

> 한 역이 여러 노선에 속할 수 있어 `station`과 분리했습니다. 노선 추가 시 행만 추가하면 됩니다.

### 2-4. `car_type` 차량 유형

| 컬럼 | 타입 | 출처 | 설명 | 이유 |
|---|---|---|---|---|
| car_type_code | VARCHAR2(10) PK | 공공 | 차량 유형 코드 | 실제 코드값으로 세팅 |
| car_type_name | VARCHAR2(50) | 공공 | 차량 유형명 | |
| seat_count | NUMBER(3) | 공공 | 좌석 수 | `seat` 자동 생성 기준 |
| seat_grade | VARCHAR2(10) | 공공/생성 | GENERAL / FIRST | 등급별 운임·재고 분리 |
| seat_columns | VARCHAR2(10) | 생성 | 좌석 열 배치 (예: ABCD) | 좌석 번호(5A) 생성 규칙 |

> 다운로드 후 실제 헤더명에 맞춰 컬럼명을 조정하세요.

### 2-5. `train` 열차 (정의)

| 컬럼 | 타입 | 출처 | 설명 | 이유 |
|---|---|---|---|---|
| train_id | NUMBER PK | 생성 | 열차 ID | |
| train_no | VARCHAR2(10) | 생성 | 열차 번호 (101, 103…) | |
| train_kind | VARCHAR2(20) | 생성 | KTX / 새마을 등 | 운임 단가 구분 |
| route_id | NUMBER FK | 생성 | 운행 노선 | |
| direction | VARCHAR2(4) | 생성 | DOWN / UP | 상·하행 구분 |

### 2-6. `train_car` 열차 편성

| 컬럼 | 타입 | 출처 | 설명 | 이유 |
|---|---|---|---|---|
| train_id | NUMBER PK, FK | 생성 | 열차 | |
| car_no | NUMBER(2) PK | 생성 | 호차 번호 | |
| car_type_code | VARCHAR2(10) FK | 공공 | 차량 유형 | 호차마다 좌석 수·등급이 다름 |

### 2-7. `seat` 물리 좌석

| 컬럼 | 타입 | 출처 | 설명 | 이유 |
|---|---|---|---|---|
| seat_id | NUMBER PK | 생성 | 좌석 ID | |
| train_id | NUMBER FK | 생성 | 열차 | |
| car_no | NUMBER(2) | 생성 | 호차 | |
| seat_no | VARCHAR2(5) | 생성 | 좌석 번호 (5A) | 화면 표시 |
| seat_grade | VARCHAR2(10) | 생성 | 등급 | car_type에서 상속 |
| is_window | CHAR(1) | 생성 | 창측 여부 Y/N | 좌석 선호 분포를 가상 트래픽에 반영 |

> `train_car` × `car_type.seat_count`로 스크립트 자동 생성. UNIQUE(train_id, car_no, seat_no)

### 2-8. `train_run` 날짜별 운행

| 컬럼 | 타입 | 출처 | 설명 | 이유 |
|---|---|---|---|---|
| run_id | NUMBER PK | 생성 | 운행 ID | 대기열·재고·Kafka 집계의 기준 단위 |
| train_id | NUMBER FK | 생성 | 열차 | |
| run_date | DATE | 생성 | 운행일 | 명절 기간 |
| sale_open_at | TIMESTAMP | 생성 | 예매 오픈 시각 | **트래픽 폭증 시점.** 부하 테스트 시나리오 기준 |
| sale_close_at | TIMESTAMP | 생성 | 판매 마감 | |
| status | VARCHAR2(10) | 시스템 | SCHEDULED / ON_SALE / CLOSED / DEPARTED | 판매 가능 여부 판단 |

> UNIQUE(train_id, run_date)

### 2-9. `train_stop` 정차 시각

| 컬럼 | 타입 | 출처 | 설명 | 이유 |
|---|---|---|---|---|
| run_id | NUMBER PK, FK | 생성 | 운행 | 날짜별 시각 변경 대응 |
| station_id | VARCHAR2(10) PK, FK | 공공 | 정차역 | |
| stop_order | NUMBER(3) | 생성 | 정차 순서 | `route_station.station_order`와 매핑 |
| arrival_time | TIMESTAMP | 생성 | 도착 시각 | |
| departure_time | TIMESTAMP | 생성 | 출발 시각 | **출발 직전 취소** 판단 기준 |

### 2-10. `fare` 운임

| 컬럼 | 타입 | 출처 | 설명 | 이유 |
|---|---|---|---|---|
| fare_id | NUMBER PK | 생성 | | |
| train_kind | VARCHAR2(20) | 생성 | 열차 종류 | |
| seat_grade | VARCHAR2(10) | 생성 | 좌석 등급 | |
| from_station_id | VARCHAR2(10) FK | 공공 | 출발역 | |
| to_station_id | VARCHAR2(10) FK | 공공 | 도착역 | |
| amount | NUMBER(10) | 생성 | 운임 | 거리 × 단가로 산출 |
| valid_from / valid_to | DATE | 생성 | 적용 기간 | 운임 변경 이력 대응 |

### 2-11. `purchase_limit_policy` 매수 제한 정책

| 컬럼 | 타입 | 출처 | 설명 | 이유 |
|---|---|---|---|---|
| policy_id | NUMBER PK | 생성 | | |
| scope | VARCHAR2(20) | 생성 | PER_RESERVATION / PER_RUN / PER_HOLIDAY | 1회·열차별·명절 전체 제한을 코드 수정 없이 조정 |
| max_seats | NUMBER(3) | 생성 | 최대 매수 | |
| valid_from / valid_to | TIMESTAMP | 생성 | 적용 기간 | 설·추석별 다른 정책 |

---

## 3. 회원·식별 (Oracle)

### 3-1. `member` 회원

| 컬럼 | 타입 | 출처 | 설명 | 이유 |
|---|---|---|---|---|
| member_id | NUMBER PK | 생성 | 회원 ID | |
| email | VARCHAR2(100) UNIQUE | 생성 | 로그인 ID | |
| password_hash | VARCHAR2(100) | 생성 | 비밀번호 해시 | |
| ci_hash | VARCHAR2(64) | 생성 | 모의 본인인증 CI 해시 | **위험 점수·매수 제한의 묶음 단위.** 다계정이어도 같은 값 |
| status | VARCHAR2(10) | 시스템 | ACTIVE / RESTRICTED / BANNED | 관리자 조치 반영 |
| created_at | TIMESTAMP | 생성 | 가입 시각 | **신규 계정 판별** (기본 신뢰도 낮음) |

> ci_hash는 UNIQUE를 걸지 않습니다. 가상 데이터에서 다계정 어뷰저를 재현하려면 같은 CI가 여러 계정에 있어야 하기 때문입니다.

### 3-2. `payment_method` 결제 수단

| 컬럼 | 타입 | 출처 | 설명 | 이유 |
|---|---|---|---|---|
| method_id | NUMBER PK | 생성 | | |
| member_id | NUMBER FK | 생성 | | |
| method_hash | VARCHAR2(64) | 생성 | 카드 번호 해시 | **묶음 단위.** 여러 계정이 같은 카드를 쓰면 연결 |
| method_type | VARCHAR2(10) | 생성 | CARD / ACCOUNT / PAY | |
| card_last4 | CHAR(4) | 생성 | 끝 4자리 | 화면 표시용 |

### 3-3. `member_device` 기기

| 컬럼 | 타입 | 출처 | 설명 | 이유 |
|---|---|---|---|---|
| device_hash | VARCHAR2(64) PK | 생성 | 기기 지문 해시 | **묶음 단위** |
| member_id | NUMBER PK, FK | 생성 | | 한 기기 다계정 탐지 (N:M) |
| first_seen_at | TIMESTAMP | 생성 | 최초 사용 | |
| last_seen_at | TIMESTAMP | 시스템 | 최근 사용 | |

---

## 4. 예약·결제 (Oracle)

### 4-1. `seat_inventory` 좌석 구간 재고 ★

| 컬럼 | 타입 | 출처 | 설명 | 이유 |
|---|---|---|---|---|
| run_id | NUMBER FK | 시스템 | 운행 | |
| seat_id | NUMBER FK | 시스템 | 좌석 | |
| segment_no | NUMBER(3) | 시스템 | 구간 번호 (역 순번 i → i+1 = i) | 구간 단위 점유 |
| reservation_id | NUMBER FK | 시스템 | 점유 예약 | 반환 시 이 예약 행만 삭제 |
| status | VARCHAR2(10) | 시스템 | HOLD / SOLD | 선점과 확정 구분 |

> **UNIQUE(run_id, seat_id, segment_no)** — 같은 좌석 같은 구간에 두 행이 들어갈 수 없으므로 동시성 버그가 있어도 중복 예약 0건이 DB에서 보장됩니다.
> 서울(1)→대전(3) 예약 시 segment 1, 2 두 행 INSERT. 대전(3)→부산(5)은 segment 3, 4라 충돌 없이 재판매.
> 확장 과제를 안 하면 segment_no를 항상 0 한 행으로 쓰면 되고, 스키마 변경은 없습니다.

### 4-2. `reservation` 예약

| 컬럼 | 타입 | 출처 | 설명 | 이유 |
|---|---|---|---|---|
| reservation_id | NUMBER PK | 시스템 | 예약 ID | **Kafka 파티션 키** → 상태 변경 순서 보장 |
| member_id | NUMBER FK | 생성 | 예약자 | |
| ci_hash | VARCHAR2(64) | 생성 | 예약 시점 CI | 매수 제한 집계를 조인 없이 빠르게 |
| run_id | NUMBER FK | 생성 | 운행 | |
| from_station_id | VARCHAR2(10) FK | 공공 | 승차역 | |
| to_station_id | VARCHAR2(10) FK | 공공 | 하차역 | |
| seat_count | NUMBER(2) | 생성 | 예약 매수 | **1회 구매 매수** 위험 신호 |
| total_amount | NUMBER(10) | 시스템 | 예약 시점 금액 | 운임 변경과 무관하게 보존 |
| status | VARCHAR2(12) | 시스템 | HOLD / PAYMENT_PENDING / CONFIRMED / CANCELED / EXPIRED | 상태 머신 |
| channel | VARCHAR2(10) | 생성 | WEB / APP | 채널별 트래픽 분석 |
| source | VARCHAR2(10) | 시스템 | NORMAL / WAITLIST | 취소표 재배정 여부 |
| held_at | TIMESTAMP | 시스템 | 좌석 선점 시각 | |
| pay_deadline_at | TIMESTAMP | 시스템 | 결제 기한 | 초과 시 자동 반환 |
| confirmed_at | TIMESTAMP | 시스템 | 확정 시각 | **구매→취소 시간** 계산 시작점 |
| canceled_at | TIMESTAMP | 시스템 | 취소 시각 | |
| idempotency_key | VARCHAR2(64) UNIQUE | 시스템 | 클라이언트 요청 키 | 따닥 클릭·재시도 시 중복 예약 방지 |
| version | NUMBER | 시스템 | 낙관적 락 버전 | 락 방식 성능 비교 실험용 |

> 인덱스: (status, pay_deadline_at) — 만료 스캐너용, (ci_hash, run_id) — 매수 제한 집계용

### 4-3. `reservation_seat` 예약 좌석

| 컬럼 | 타입 | 출처 | 설명 | 이유 |
|---|---|---|---|---|
| reservation_id | NUMBER PK, FK | 시스템 | | |
| seat_id | NUMBER PK, FK | 시스템 | | 한 예약에 여러 좌석 |
| passenger_type | VARCHAR2(10) | 생성 | ADULT / CHILD / SENIOR | 운임 할인 확장 |
| amount | NUMBER(10) | 시스템 | 좌석별 금액 | 부분 취소 대응 |

### 4-4. `reservation_history` 상태 이력

| 컬럼 | 타입 | 출처 | 설명 | 이유 |
|---|---|---|---|---|
| history_id | NUMBER PK | 시스템 | | |
| reservation_id | NUMBER FK | 시스템 | | |
| from_status | VARCHAR2(12) | 시스템 | 이전 상태 | |
| to_status | VARCHAR2(12) | 시스템 | 변경 상태 | 잘못된 전이(CANCELED→CONFIRMED) 탐지 |
| event_id | VARCHAR2(36) | 시스템 | 원인 Kafka 이벤트 | 어떤 이벤트가 바꿨는지 추적 |
| changed_at | TIMESTAMP | 시스템 | | **순서 보장 검증 근거** |

### 4-5. `payment` 결제

| 컬럼 | 타입 | 출처 | 설명 | 이유 |
|---|---|---|---|---|
| payment_id | NUMBER PK | 시스템 | | |
| reservation_id | NUMBER FK | 시스템 | | |
| method_id | NUMBER FK | 생성 | 결제 수단 | 결제 수단 단위 위험 점수 |
| amount | NUMBER(10) | 시스템 | 결제 금액 | |
| status | VARCHAR2(10) | 시스템 | REQUESTED / APPROVED / FAILED / REFUNDED | Saga 보상 트리거 |
| pg_tx_id | VARCHAR2(64) | 시스템 | PG 거래 ID | PG 대사·환불 |
| fail_reason | VARCHAR2(100) | 시스템 | 실패 사유 | 트러블슈팅 |
| idempotency_key | VARCHAR2(64) UNIQUE | 시스템 | 결제 요청 키 | **중복 결제 0건** |
| requested_at / approved_at | TIMESTAMP | 시스템 | | 결제 소요 시간 측정 |

### 4-6. `cancellation` 취소·환불

| 컬럼 | 타입 | 출처 | 설명 | 이유 |
|---|---|---|---|---|
| cancel_id | NUMBER PK | 시스템 | | |
| reservation_id | NUMBER FK | 시스템 | | |
| cancel_type | VARCHAR2(10) | 시스템 | USER / EXPIRED / PAY_FAILED / ADMIN | 사용자 취소만 위험 신호로 집계 |
| canceled_at | TIMESTAMP | 생성 | 취소 시각 | |
| minutes_after_purchase | NUMBER | 시스템 | 확정 후 취소까지 분 | **구매 후 취소 시간** 위험 신호 |
| minutes_before_departure | NUMBER | 시스템 | 출발 전 남은 분 | **노쇼성 직전 취소** 탐지, 기획 배경 통계와 연결 |
| refund_amount | NUMBER(10) | 시스템 | 환불액 | |
| resold_yn | CHAR(1) | 시스템 | 재판매 여부 | **재판매율** 성과 지표 |

---

## 5. 이벤트 신뢰성 (Oracle)

### 5-1. `outbox_event` 발행 대기 이벤트

| 컬럼 | 타입 | 출처 | 설명 | 이유 |
|---|---|---|---|---|
| event_id | VARCHAR2(36) PK | 시스템 | UUID | 소비자 중복 판별 키 |
| aggregate_type | VARCHAR2(20) | 시스템 | RESERVATION / PAYMENT / WAITLIST | 토픽 라우팅 |
| aggregate_id | NUMBER | 시스템 | reservation_id 등 | **Kafka 메시지 키 = 파티션 결정** |
| event_type | VARCHAR2(30) | 시스템 | SEAT_HELD, PAYMENT_APPROVED … | |
| payload | CLOB (JSON) | 시스템 | 이벤트 본문 | 스키마 변경에 유연 |
| status | VARCHAR2(10) | 시스템 | PENDING / PUBLISHED / FAILED | 릴레이가 PENDING만 발행 |
| retry_count | NUMBER(2) | 시스템 | 재시도 횟수 | 무한 재시도 방지 |
| created_at / published_at | TIMESTAMP | 시스템 | | 발행 지연 모니터링 |

> 비즈니스 변경과 같은 트랜잭션에서 INSERT → 이벤트 유실 0건.

### 5-2. `processed_event` 처리 완료 이벤트 (Inbox)

| 컬럼 | 타입 | 출처 | 설명 | 이유 |
|---|---|---|---|---|
| consumer_group | VARCHAR2(50) PK | 시스템 | 소비자 그룹 | 그룹마다 독립 처리 |
| event_id | VARCHAR2(36) PK | 시스템 | 이벤트 ID | 이미 있으면 skip → **멱등 소비** |
| processed_at | TIMESTAMP | 시스템 | | 보관 기간 후 삭제 |

### 5-3. `saga_instance` Saga 진행 상태

| 컬럼 | 타입 | 출처 | 설명 | 이유 |
|---|---|---|---|---|
| saga_id | VARCHAR2(36) PK | 시스템 | | |
| reservation_id | NUMBER FK | 시스템 | | |
| current_step | VARCHAR2(20) | 시스템 | SEAT_HELD / PAYING / CONFIRMED / COMPENSATING | 중단 지점에서 재개·보상 |
| status | VARCHAR2(10) | 시스템 | RUNNING / DONE / COMPENSATED | **좌석 복구율 100%** 검증 |
| updated_at | TIMESTAMP | 시스템 | | 멈춘 Saga 탐지 |

---

## 6. 취소표 재배정 (Oracle)

### 6-1. `waitlist` 취소표 대기

| 컬럼 | 타입 | 출처 | 설명 | 이유 |
|---|---|---|---|---|
| waitlist_id | NUMBER PK | 생성 | | |
| member_id | NUMBER FK | 생성 | | |
| run_id | NUMBER FK | 생성 | | |
| from_station_id / to_station_id | VARCHAR2(10) | 공공 | 희망 구간 | 구간 일치 취소표만 배정 |
| seat_grade | VARCHAR2(10) | 생성 | 희망 등급 | |
| seat_count | NUMBER(2) | 생성 | 희망 매수 | |
| requested_at | TIMESTAMP | 생성 | 신청 시각 | **대기 순서 기준** |
| offered_at | TIMESTAMP | 시스템 | 배정 제안 시각 | |
| offer_deadline_at | TIMESTAMP | 시스템 | 결제 기한 | 초과 시 다음 대기자 |
| offered_reservation_id | NUMBER FK | 시스템 | 제안된 예약 | |
| status | VARCHAR2(10) | 시스템 | WAITING / OFFERED / ACCEPTED / EXPIRED / CANCELED | |

### 6-2. `notification` 알림

| 컬럼 | 타입 | 출처 | 설명 | 이유 |
|---|---|---|---|---|
| notification_id | NUMBER PK | 시스템 | | |
| member_id | NUMBER FK | 시스템 | | |
| type | VARCHAR2(20) | 시스템 | WAITLIST_OFFER / PAY_REMINDER / EXPIRED | |
| ref_id | NUMBER | 시스템 | 관련 예약·대기 ID | |
| channel | VARCHAR2(10) | 시스템 | PUSH / EMAIL / IN_APP | 채널 추가 확장 |
| sent_at / read_at | TIMESTAMP | 시스템 | | 알림→결제 전환 분석 |

---

## 7. 위험 점수·관리자 (Oracle)

### 7-1. `risk_score` 위험 점수 (현재값)

| 컬럼 | 타입 | 출처 | 설명 | 이유 |
|---|---|---|---|---|
| subject_type | VARCHAR2(10) PK | 시스템 | CI / PAYMENT / DEVICE | 계정이 아닌 식별 단위 |
| subject_hash | VARCHAR2(64) PK | 시스템 | 해당 해시 | |
| total_purchase_seats | NUMBER | 시스템 | 누적 구매 매수 | 신호 |
| max_single_purchase | NUMBER | 시스템 | 1회 최대 매수 | 신호 |
| cancel_ratio | NUMBER(4,3) | 시스템 | 취소 비율 | 신호 |
| avg_minutes_to_cancel | NUMBER | 시스템 | 평균 구매→취소 시간 | 신호 |
| last_minute_cancel_cnt | NUMBER | 시스템 | 출발 직전 취소 수 | 신호 |
| linked_account_cnt | NUMBER | 시스템 | 연결된 계정 수 | 다계정 신호 |
| avg_request_interval_ms | NUMBER | 시스템 | 평균 요청 간격 | 매크로 신호 |
| account_age_days | NUMBER | 시스템 | 가장 오래된 계정 나이 | 신규 계정 기본 신뢰도 |
| rule_score | NUMBER(5,2) | 시스템 | 규칙 기반 점수 | |
| iforest_score | NUMBER(5,2) | 시스템 | Isolation Forest 점수 | **두 방식 비교** |
| final_score | NUMBER(5,2) | 시스템 | 최종 점수 (0~100) | 대기열 순번 조정량 |
| reasons | CLOB (JSON) | 시스템 | 점수 근거 목록 | **운영 원칙: 근거 기록** |
| model_version | VARCHAR2(20) | 시스템 | 산정 모델 버전 | 모델 교체 시 비교 |
| calculated_at | TIMESTAMP | 시스템 | 산정 시각 | **감쇠 기준** |
| review_status | VARCHAR2(10) | 시스템 | NONE / PENDING / CONFIRMED / CLEARED | 높은 점수는 검토 후 조치 |

### 7-2. `risk_score_history` 점수 이력

| 컬럼 | 타입 | 출처 | 설명 | 이유 |
|---|---|---|---|---|
| history_id | NUMBER PK | 시스템 | | |
| subject_type / subject_hash | | 시스템 | | |
| final_score | NUMBER(5,2) | 시스템 | 당시 점수 | 감쇠 동작 검증, 이의 제기 대응 |
| reasons | CLOB | 시스템 | 당시 근거 | |
| calculated_at | TIMESTAMP | 시스템 | | |

### 7-3. `admin_action` 관리자 조치

| 컬럼 | 타입 | 출처 | 설명 | 이유 |
|---|---|---|---|---|
| action_id | NUMBER PK | 시스템 | | |
| admin_id | NUMBER | 시스템 | 조치자 | 감사 추적 |
| subject_type / subject_hash | | 시스템 | 대상 | |
| action_type | VARCHAR2(20) | 시스템 | CONFIRM / CLEAR / RESTRICT / BAN | |
| memo | VARCHAR2(500) | 시스템 | 사유 | |
| acted_at | TIMESTAMP | 시스템 | | |

---

## 8. MongoDB 컬렉션

### 8-1. `behavior_log` 행동 로그

| 필드 | 타입 | 출처 | 설명 | 이유 |
|---|---|---|---|---|
| _id | ObjectId | 시스템 | | |
| member_id | Long | 생성 | | |
| ci_hash | String | 생성 | | 묶음 단위 집계 |
| device_hash | String | 생성 | | 묶음 단위 집계 |
| ip_hash | String | 생성 | | IP 집중도 |
| session_id | String | 생성 | | 세션 단위 패턴 |
| event_type | String | 생성 | VIEW_TRAIN / VIEW_SEAT / QUEUE_ENTER / SEAT_HOLD / PAY / CANCEL | |
| run_id | Long | 생성 | 대상 운행 | 인기 열차 쏠림 분석 |
| ts | Date | 생성 | 이벤트 시각 (ms) | |
| interval_ms | Int | 생성 | 직전 요청과 간격 | **매크로 신호** (사람은 수백 ms~초, 봇은 균일·짧음) |
| user_agent | String | 생성 | | 헤드리스 브라우저 탐지 |
| channel | String | 생성 | WEB / APP | |
| response_status | Int | 시스템 | HTTP 상태 | 차단·에러 분석 |
| meta | Object | 시스템 | 이벤트별 추가 정보 | 스키마 변경 없이 필드 확장 |

> 인덱스: { ci_hash: 1, ts: -1 }, { run_id: 1, ts: 1 }, TTL { ts: 1 } (예: 180일)
> 대량 적재 시 샤드 키 후보: { ci_hash: "hashed" }

### 8-2. `queue_log` 대기열 기록

| 필드 | 타입 | 출처 | 설명 | 이유 |
|---|---|---|---|---|
| member_id | Long | 시스템 | | |
| run_id | Long | 시스템 | | |
| entered_at | Date | 시스템 | 실제 진입 시각 | |
| risk_score | Double | 시스템 | 진입 시 점수 | |
| penalty_ms | Long | 시스템 | 뒤로 밀린 양 | |
| initial_rank | Long | 시스템 | 조정 전 순번 | **조정이 의도대로 됐는지 검증** |
| adjusted_rank | Long | 시스템 | 조정 후 순번 | |
| admitted_at | Date | 시스템 | 입장 시각 | 실제 대기 시간 vs 예상 대기 시간 비교 |
| left_reason | String | 시스템 | ADMITTED / TIMEOUT / LEFT | 이탈률 |

---

## 9. Redis 키

| 키 | 타입 | 값 | 설명 | 이유 |
|---|---|---|---|---|
| `queue:{runId}` | ZSET | member=memberId, score=진입시각ms + penalty_ms | 대기열 | 위험 점수를 score에 더하면 별도 지연 없이 후순위 처리 |
| `queue:active:{runId}` | ZSET | member=memberId, score=만료시각 | 입장 허용된 사용자 | 동시 입장 인원 제한 |
| `queue:throughput:{runId}` | STRING | 초당 입장 처리 수 | 예상 대기 시간 계산 | 대기시간 = 내 순번 ÷ 처리량 |
| `seat:hold:{runId}:{seatId}:{segNo}` | STRING (TTL) | reservationId | 좌석 선점 | TTL = 결제 기한, 만료 시 자동 반환 |
| `limit:{runId}:{ciHash}` | STRING | 구매 매수 | 매수 제한 빠른 체크 | DB 조회 없이 1차 차단 |
| `risk:{subjectType}:{hash}` | STRING | final_score | 점수 캐시 | 대기열 진입 시 DB 미조회 |
| `seatmap:{runId}` | HASH | seatId → 상태 | 좌석 조회 캐시 | 조회 트래픽을 DB에서 분리 |

---

## 10. 가상 데이터 전용

### `synthetic_label` 정답 라벨 (운영 로직에서 참조 금지)

| 컬럼 | 타입 | 설명 | 이유 |
|---|---|---|---|
| member_id | NUMBER PK | 회원 | |
| user_type | VARCHAR2(20) | NORMAL / RESELLER / CANCEL_ABUSER / MACRO | 위험 점수의 **정밀도·재현율 측정** |
| group_id | NUMBER | 같은 어뷰저가 만든 다계정 묶음 | 묶음 탐지 성능 측정 |
| generation_params | CLOB (JSON) | 생성 시 사용한 분포 파라미터 | 재현 가능성, 발표 시 근거 |

### 생성 시 반영할 패턴

| 유형 | 생성 규칙 | 근거 데이터 |
|---|---|---|
| NORMAL | 1~2매, 취소율 낮음, 요청 간격 불규칙 | Hotel Booking의 일반 예약 분포 |
| RESELLER | 상한 근처 매수, 다계정·같은 결제수단, 출발 직전 대량 취소 | Hotel Booking 취소 이력·리드타임 관계 |
| CANCEL_ABUSER | 예약 후 단시간 반복 취소 | Hotel Booking `previous_cancellations` 패턴 |
| MACRO | 오픈 직후 집중, interval_ms 짧고 균일, 반복 조회 | Web Server Access Logs 봇 특징 |
| 트래픽 분포 | 오픈 시각 스파이크 후 감쇠, 출발일 근접 시 재증가 | Renfe 출발일 대비 판매 추이 |

---

## 11. 확장 포인트 정리

| 확장 | 스키마 변경 필요 여부 |
|---|---|
| 구간 재고 진행 | 없음 (segment_no 사용만 시작) |
| 노선·역 추가 | 없음 (route_station 행 추가) |
| 매수 제한 정책 변경 | 없음 (policy 행 추가) |
| 알림 채널 추가 | 없음 (channel 코드 추가) |
| 위험 신호 추가 | risk_score 컬럼 추가, 로그는 meta 필드 활용 |
| 위험 모델 교체 | 없음 (model_version으로 구분) |
| 이벤트 종류 추가 | 없음 (event_type 코드 + payload JSON) |

---

## 참고 자료

**공공데이터포털 (기준 데이터)**
- 한국철도공사_차세대예약발매_차량유형코드: https://www.data.go.kr/data/15137680/fileData.do
- 한국철도공사_철도운행거리_전체: https://www.data.go.kr/data/15137040/fileData.do
- 한국철도공사_KTX 노선별 역정보 (노선 내 역 순번): https://www.data.go.kr/dcat/metadata/15127571
- 한국철도공사 역간 최단 운행거리 (출발·도착역 코드별 거리, 경유역): https://www.data.go.kr/dcat/metadata/15153835
- 한국철도공사 간선 철도역 위치정보 (위경도): https://www.data.go.kr/dcat/metadata/15127532
- 한국철도공사_공통기준 역상세 정보: https://www.data.go.kr/data/15153852/fileData.do
- 한국철도공사 역별 키로정 (여객·화물 구간 거리): https://www.data.go.kr/dcat/metadata/15153841
- 한국철도공사 세그먼트 구간 정보: https://www.data.go.kr/dcat/metadata/15153579
- 한국철도공사 역무열차종별 코드 (KTX·새마을 등 명칭): https://www.data.go.kr/dcat/metadata/15154143

**패턴 검증용 외부 데이터**
- Kaggle, Hotel Booking Demand: https://www.kaggle.com/datasets/jessemostipak/hotel-booking-demand
- Kaggle, Web Server Access Logs 활용 예: https://github.com/zaki1003/bot-detection-prototype
- Iliou et al., Web Bot Detection Dataset, Bournemouth University (2020): https://bordar.bournemouth.ac.uk/272/
- Kaggle, Spanish High Speed Rail Tickets Pricing (Renfe): https://www.kaggle.com/thegurusteam/spanish-high-speed-rail-system-ticket-pricing

**기획 배경**
- 세계일보, 「추석 기차표, 언제 예매하지?」 (2026.08.29): https://www.segye.com/newsView/20260829505201
- 쿠키뉴스, 「설 승차권 암표 거래 절대 안 돼」 (2026.02.09): https://www.kukinews.com/article/view/kuk202602090043
- 헤럴드경제, 「작년 명절 노쇼 기차표 5년 새 5.3배 급증」 (2026.02.11): https://www.heraldk.com/article/2026021119093519927
