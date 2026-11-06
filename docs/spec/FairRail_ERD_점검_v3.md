# FairRail ERD 점검 보고서 v3

`FairRail_columns.md`(v1)와 `FairRail_columns_v2_보안_CCTV_빅데이터.md`(v2)를 함께 점검한 결과입니다.
v1·v2 파일은 기록으로 두고, 이 문서에 **수정·추가·확장 대비** 사항만 모았습니다. 점검 결과는 ERD 편집기에도 반영했으므로, 전체 최신 명세는 편집기의 "내보내기 → Markdown 명세"로 한 번에 받을 수 있습니다.

---

## 0. 점검 방법과 결과 요약

| 점검 | 방법 |
|---|---|
| 기능 누락 | 기획서 3장(주요 기능)·4장(핵심 과제)·11장(성과 목표)의 항목마다 담당 테이블과 검증 방법을 대응 (5장 추적표) |
| 관계·키 | 모든 FK의 대상 PK 존재·타입 일치, PK 없는 테이블, FK 없이 남은 `*_id` 컬럼을 스크립트로 전수 검사 |
| 동시성·순서 | 중복 예약·중복 결제·Kafka 재전송·대기열 우회 등 실패 시나리오를 하나씩 따라가며 막는 장치가 실제로 있는지 확인 (6장) |
| 빅데이터 | MongoDB 컬렉션 설계를 공식 제약(문서 크기, 시계열 컬렉션 특성)과 대조 |

| 구분 | 건수 | 내용 |
|---|---|---|
| 오류 수정 | 12 | 그대로 구현하면 버그·우회·저장 실패가 나는 부분 |
| 누락 추가 | 4개 테이블, 26개 컬럼, Redis 키 3개 | 기획서 기능을 끝까지 구현하려면 필요한 부분 |
| 확장 대비 | 10 | 지금은 자리만 두고 2주차 말·발표 후 판단 |

검사 스크립트에서 FK 타입 불일치는 0건이었습니다. FK 없이 남은 ID 컬럼 14개 중 7개를 FK로 연결했습니다. 나머지 7개는 일부러 FK를 걸지 않습니다. PG·Kafka 등 외부 시스템 값(`pg_tx_id`, `refund_pg_tx_id`, `event_id`), 여러 테이블을 가리키는 다형 참조(`outbox_event.aggregate_id`, `notification.ref_id` + `ref_type`), 테이블이 아닌 묶음·키 번호(`group_id`, `pepper_key_id`, `token_family_id`), 외부 데이터셋의 자체 ID(`ext_bot_detection.session_id`)입니다.

점검 반영 후 전체 규모는 **53개 테이블 · 444개 컬럼 · 관계 75개 · 빅데이터 11개**입니다.

---

## 1. 오류 수정

### 1-1. 반드시 고쳐야 하는 것

| # | 위치 | 문제 | 수정 | 이유 |
|---|---|---|---|---|
| 1 | Redis 대기열 | 대기열을 통과했다는 증명이 없음. 매크로가 좌석 선점 API를 직접 호출하면 **대기열과 위험 점수 순번 조정이 통째로 무력화** | `queue:pass:{runId}:{memberId}` 입장 토큰(TTL) 추가. 좌석 조회·선점 API가 토큰을 검사 | 기획서의 핵심 차별점(위험 사용자 후순위)이 우회되지 않게 함 |
| 2 | `replay_event` | 시계열 컬렉션의 metaField를 session_id로 잡으면 세션마다 버킷이 따로 생겨 압축 이점이 사라짐. 시계열 컬렉션엔 unique 인덱스도 걸 수 없어 클라이언트 재전송 중복을 못 막음 | **일반 컬렉션**으로 변경. UNIQUE `{session_id: 1, seq: 1}` + TTL `{ts: 1}` 90일 | 재생은 "한 세션을 seq 순으로 읽기"가 전부라 일반 컬렉션+복합 인덱스가 더 맞음 |
| 3 | `evidence_snapshot.events` | 이벤트 배열을 문서 하나에 넣으면 MongoDB 문서 16MB 한도에 걸림 (마우스 궤적이 긴 세션) | `chunk_no`, `chunk_count` 추가해 조각 저장. 조각마다 sha256, 전체 해시는 `suspicious_case.evidence_hash`(Oracle)에 | 저장 실패 방지 + 증거 해시를 다른 DB에 둬서 한쪽 변조를 다른 쪽으로 확인 |
| 4 | `reservation.idempotency_key` | 전역 UNIQUE. 다른 사용자의 클라이언트가 같은 키를 만들면 정상 요청이 거부됨 | `UNIQUE(member_id, idempotency_key)` | 멱등 범위는 요청자 단위 |
| 5 | `payment.idempotency_key` | 같은 문제. 또 키가 달라도 한 예약에 승인 2건이 들어가는 걸 막지 못함 | `UNIQUE(reservation_id, idempotency_key)` + 함수 기반 유니크 인덱스 `ON payment (CASE WHEN status='APPROVED' THEN reservation_id END)` | **"중복 결제 0건"을 DB가 보장** (키가 다른 재시도에도) |
| 6 | `outbox_event.aggregate_id` | 결제 이벤트가 payment_id를 키로 쓰면 같은 예약의 "선점→결제→확정" 이벤트가 다른 파티션으로 흩어져 **순서 보장 실패** | `partition_key` 컬럼 추가, 예약 흐름 이벤트는 모두 reservation_id. `aggregate_id`는 VARCHAR2(36)로 | 기획서 "예약 ID 기준 파티셔닝으로 상태 변경 순서 보장"을 구조로 강제 |
| 7 | `seat_inventory` | PK 없음 (UNIQUE만) | `PK(run_id, seat_id, segment_no)` | 같은 효과에 더해 JPA 엔티티 식별자로 바로 사용 |
| 8 | 관리자 | 관리자 ID를 쓰는 테이블이 5개인데 관리자 테이블이 없음 | `admin_user` 추가 후 FK 연결 | 녹화 열람·마스킹 해제 권한을 역할로 제한하려면 필요 |

### 1-2. 정합성 보완

| # | 위치 | 문제 | 수정 |
|---|---|---|---|
| 9 | `notification.ref_id` | 어느 테이블을 가리키는지 알 수 없음 | `ref_type` (RESERVATION / WAITLIST / CASE) 추가 |
| 10 | `case_marker.session_id`, `replay_access_log.session_id` | FK 누락 | `auth_session` FK 연결 |
| 11 | `risk_score` | 점수는 CI·결제수단·기기 단위인데 대기열은 회원 단위 → 결합 규칙 없음 | 비고에 규칙 명시: **회원 패널티 = 연결된 CI·결제수단·기기 점수 중 최댓값** |
| 12 | `seat_inventory` ↔ `seat` | 선점한 좌석이 그 운행 열차의 좌석인지 FK로 강제 불가 (`seat.train_id = train_run.train_id`) | INSERT 전 애플리케이션 검증으로 명시, 통합 테스트 항목에 추가 |

---

## 2. 누락 추가

### 2-1. 새 테이블

#### `admin_user` 관리자 (Oracle, 보안·인증)

| 컬럼 | 타입 | 출처 | 설명 | 이유 |
|---|---|---|---|---|
| admin_id | NUMBER PK | 생성 | 관리자 ID | admin_action, suspicious_case, case_marker, replay_access_log, evidence_snapshot이 참조 |
| login_id | VARCHAR2(50) UNIQUE | 생성 | 로그인 ID | |
| password_hash | VARCHAR2(255) | 시스템 | Argon2id PHC 문자열 | 회원과 같은 정책 |
| role | VARCHAR2(20) | 생성 | VIEWER / REVIEWER / SUPERVISOR | 마스킹 해제·내보내기는 SUPERVISOR만 |
| mfa_secret_enc | VARCHAR2(200) | 시스템 | TOTP 비밀키 암호문 | 녹화·개인정보 접근 계정이라 2단계 인증 자리 확보 (구현은 확장) |
| status | VARCHAR2(10) | 시스템 | ACTIVE / DISABLED | |
| last_login_at | TIMESTAMP | 시스템 | 마지막 로그인 | |

#### `sale_event` 명절 예매 행사 (Oracle, 기준 데이터)

| 컬럼 | 타입 | 출처 | 설명 | 이유 |
|---|---|---|---|---|
| sale_event_id | NUMBER PK | 생성 | | |
| name | VARCHAR2(50) | 생성 | 예: 2026 추석 | |
| holiday_from | DATE | 생성 | 연휴 시작 | `PER_HOLIDAY` 매수 제한의 기간 정의 (v1에 없던 부분) |
| holiday_to | DATE | 생성 | 연휴 끝 | |
| sale_open_at | TIMESTAMP | 생성 | 일반 예매 오픈 | 부하 테스트 시나리오 기준 |
| priority_open_at | TIMESTAMP | 생성 | 교통약자 사전 예매 오픈 | 확장 시 사용 |
| status | VARCHAR2(10) | 시스템 | PLANNED / OPEN / CLOSED | |

`train_run.sale_event_id`, `purchase_limit_policy.sale_event_id`가 참조합니다.

#### `cancel_fee_policy` 취소 수수료 정책 (Oracle, 예약·결제)

| 컬럼 | 타입 | 출처 | 설명 | 이유 |
|---|---|---|---|---|
| fee_policy_id | NUMBER PK | 생성 | | |
| sale_event_id | NUMBER FK → sale_event | 생성 | 적용 행사 (null이면 상시) | 명절만 수수료 강화 가능 |
| min_minutes_before | NUMBER | 생성 | 출발 전 구간 시작(분) | |
| max_minutes_before | NUMBER | 생성 | 출발 전 구간 끝(분) | |
| fee_rate | NUMBER(4,3) | 생성 | 수수료율 | **기획 배경의 노쇼 증가에 대한 정책 수단.** 구간·비율은 팀이 정함 |
| after_departure | CHAR(1) | 생성 | 출발 후 반환 여부 | 출발 후 반환은 재판매 불가 구간 |

#### `ext_dataset` 외부 데이터셋 카탈로그 (Oracle, 외부 빅데이터)

| 컬럼 | 타입 | 출처 | 설명 | 이유 |
|---|---|---|---|---|
| dataset_id | VARCHAR2(40) PK | 시스템 | 예: hotel_booking@v1 | 모든 `ext_*` 문서의 dataset_id가 참조 |
| name | VARCHAR2(100) | 시스템 | 데이터셋 이름 | |
| source_url | VARCHAR2(300) | 시스템 | 원본 주소 | 발표 출처 |
| license | VARCHAR2(50) | 시스템 | 확인한 라이선스 | **기획서 "사용 전 라이선스 확인" 원칙의 기록** |
| license_checked_at | DATE | 시스템 | 확인일 | |
| row_count | NUMBER | 시스템 | 적재 건수 | 빅데이터 규모 수치 |
| checksum_sha256 | VARCHAR2(64) | 시스템 | 원본 파일 해시 | 같은 파일로 재현했는지 확인 |
| ingested_at | TIMESTAMP | 시스템 | 적재 시각 | |
| caveat | VARCHAR2(300) | 시스템 | 도메인 차이 등 유의사항 | 호텔 데이터·검색 크롤러 봇 등 한계 명시 |

### 2-2. 기존 테이블에 추가하는 컬럼

| 테이블 | 컬럼 | 타입 | 이유 |
|---|---|---|---|
| member | name | VARCHAR2(50) | 회원가입·예매자 확인에 필요 (v1에 없었음) |
| member | phone_enc | VARCHAR2(200) | 알림 발송에 원문이 필요해 해시 대신 **AES-256-GCM 암호화** |
| member | phone_hash | VARCHAR2(64) | 암호문끼리는 비교 불가 → 같은 번호 중복 가입 탐지용 HMAC |
| member | withdrawn_at | TIMESTAMP | 소프트 삭제. 위험 이력은 보존 기간 후 파기 |
| train_run | sale_event_id | NUMBER FK | 운행을 명절 행사에 연결 |
| purchase_limit_policy | sale_event_id | NUMBER FK | PER_HOLIDAY 범위 |
| reservation_seat | ticket_no | VARCHAR2(20) UNIQUE | 승차권 번호. 예매 내역·반환·신고 대상 식별 |
| cancellation | cancel_fee | NUMBER(10) | 취소 수수료 |
| cancellation | fee_policy_id | NUMBER FK | 적용 정책 |
| cancellation | refund_pg_tx_id | VARCHAR2(64) | PG 환불 대사 (v1은 환불 금액만 있었음) |
| cancellation | refund_status | VARCHAR2(10) | 환불 실패 재시도 |
| outbox_event | partition_key | VARCHAR2(64) | 1-1 #6 |
| notification | ref_type | VARCHAR2(20) | 1-2 #9 |
| reservation_history | actor_type | VARCHAR2(10) | USER / SYSTEM / ADMIN. 관리자 강제 취소 구분 |
| saga_instance | timeout_at | TIMESTAMP | 지나면 보상 실행. 멈춘 Saga 자동 처리 |
| auth_session | token_family_id | VARCHAR2(36) | 회전된 옛 리프레시 토큰이 다시 쓰이면 계열 전체 폐기 (탈취 탐지) |
| queue_log | session_id, ticket_no | String, Long | CCTV 재생 연결, 사용자에게 보인 번호표와 대조 |
| model_run | decay_half_life_days | NUMBER(4) | 기획서 "기간 경과 시 점수 감소"의 파라미터 |
| suspicious_case | evidence_hash | VARCHAR2(64) | 1-1 #3 |
| evidence_snapshot | chunk_no, chunk_count | Int | 1-1 #3 |
| ext_* 4개 | dataset_id | String | ext_dataset 연결 (적재 이력·라이선스 추적) |

### 2-3. Redis 키 추가

| 키 | 타입 | 설명 | 이유 |
|---|---|---|---|
| `queue:pass:{runId}:{memberId}` | STRING + TTL | 입장 토큰 | 1-1 #1 대기열 우회 차단 |
| `rate:login:{ipHash}` | STRING + TTL | 로그인 시도 카운터 | Argon2 연산 남용·크리덴셜 스터핑 차단 (`login_attempt.result = RATE_LIMITED`의 근거) |
| `rate:api:{memberId}` | STRING + TTL | 초당 API 호출 수 | 매크로 요청 폭주 1차 차단 |

여러 구간을 한 번에 잡는 `seat:hold`는 Lua 스크립트로 모든 키를 원자적으로 `SET NX`합니다. Redis는 빠른 1차 판정, 최종 판정은 `seat_inventory` PK입니다.

---

## 3. 확장성으로 둘 것

| # | 항목 | 지금 해 둔 것 | 나중 작업 | 판단 시점 |
|---|---|---|---|---|
| 1 | 구간별 재고 | `segment_no` 컬럼, PK에 포함 | 0 대신 실제 구간 번호 사용 | 2주차 말 (기획서) |
| 2 | 승차권 양도·선물 | `ticket_no` | `ticket_transfer` 테이블 + 양도 횟수를 위험 신호로 | 발표 후 |
| 3 | 관리자 2단계 인증 | `admin_user.mfa_secret_enc` | TOTP 검증 | 3주차 여유 시 |
| 4 | 교통약자 사전 예매 | `sale_event.priority_open_at` | 사전 예매 대상 인증 | 발표 후 |
| 5 | DOM 녹화 재생 | `replay_event.type`에 값 추가로 수용 | rrweb 이벤트 저장 | 발표 후 |
| 6 | 앱 푸시 알림 | `notification.channel = PUSH` | `member_push_token` 테이블 | 앱(WebView) 배포 시 |
| 7 | 비밀번호 재설정 | 없음 | `password_reset_token` (토큰은 SHA-256 저장) | 3주차 여유 시 |
| 8 | 코드표 | 상태값 VARCHAR2 코드 규칙 | `common_code` 테이블 + 관리자 화면 | 필요 시 |
| 9 | 대용량 테이블 분할 | 모든 거래 테이블에 run_id·시각 컬럼 | reservation·payment를 운행일 기준 파티셔닝 (사용 Oracle 에디션 지원 여부 확인 필요) | 부하 테스트 결과 보고 |
| 10 | 해시 키 교체 | `pepper_key_id`(비밀번호만) | `*_hash` HMAC 키는 프로젝트 기간 고정. 교체하면 기존 해시와 연결이 끊기므로 재계산 배치 필요 | 운영 전환 시 |

---

## 4. 이번 점검에서 바뀐 설계 결정

| 결정 | 이전 | 이후 | 근거 |
|---|---|---|---|
| replay_event 저장 방식 | MongoDB 시계열 컬렉션 | 일반 컬렉션 + `{session_id, seq}` 유니크 | 1-1 #2 |
| 증거 저장 | 문서 1개 | 조각 저장 + Oracle에 전체 해시 | 1-1 #3 |
| 중복 결제 방지 | 결제 요청 키 UNIQUE | 예약당 승인 1건 함수 기반 유니크 인덱스 | 1-1 #5 |
| Kafka 키 | aggregate_id | partition_key (예약 흐름은 reservation_id) | 1-1 #6 |

---

## 5. 기능 ↔ 테이블 추적표

### 5-1. 주요 기능 (기획서 3장)

| 기능 | 테이블·키 | 상태 |
|---|---|---|
| 회원가입·모의 본인인증 | member, member_credential, identity_verification | ✅ (v3에서 이름·연락처 보강) |
| 로그인 (Argon2id) | member_credential, auth_session, login_attempt, `rate:login` | ✅ |
| 열차 조회 | train, train_run, train_stop, fare, `seatmap:{runId}` | ✅ |
| 대기열·번호표 | `queue:{runId}`, `queue:active`, `queue:pass`, queue_log | ✅ (v3에서 입장 토큰 추가) |
| 좌석 선택·예약, 1인 매수 제한 | seat_inventory, reservation, reservation_seat, purchase_limit_policy, sale_event, `limit:*` | ✅ |
| 결제 (PG 테스트) | payment, payment_method | ✅ |
| 예매 내역·취소 | reservation_seat.ticket_no, cancellation, cancel_fee_policy | ✅ (v3에서 환불·수수료 보강) |
| 취소표 예약 대기 | waitlist, notification | ✅ |
| 관리자: 열차·노선·좌석 등록 | route, route_station, train, train_car, seat, train_run | ✅ |
| 관리자: 실시간 현황·트래픽 | Prometheus·Grafana (DB 테이블 불필요) + reservation 집계 | ✅ |
| 관리자: 위험 사용자 확인·조치 | risk_score, admin_action, admin_user | ✅ (v3에서 관리자 테이블 추가) |
| CCTV 되돌아보기 | replay_session, replay_event, suspicious_case, case_session, case_marker, evidence_snapshot, replay_access_log | ✅ |
| 위험 점수 산정·순번 조정 | behavior_log, risk_feature, model_run, risk_score, `risk:*`, `queue:{runId}` score | ✅ |

### 5-2. 성과 목표 (기획서 11장 + v2)

| 목표 | 근거 데이터 | 검증 방법 |
|---|---|---|
| 좌석 중복 예약 0건 | seat_inventory PK | 같은 좌석 동시 선점 k6 테스트 후 `GROUP BY run_id, seat_id, segment_no HAVING COUNT(*) > 1` = 0 |
| 중복 결제 0건 | payment 함수 기반 유니크 인덱스 | 결제 버튼 연타·재시도 테스트 후 예약당 APPROVED 건수 ≤ 1 |
| 좌석 복구율 100% | saga_instance, seat_inventory, cancellation | 결제 실패·기한 초과 후 해당 예약의 seat_inventory 행 0건 |
| 순서 보장 | reservation_history, outbox_event.partition_key | 이력에 허용되지 않은 전이(예: CANCELED→CONFIRMED) 0건 |
| 위험 사용자 순번 조정 | queue_log.initial_rank / adjusted_rank | 점수 구간별 평균 순번 하락폭 |
| TPS·응답 시간 개선 | Prometheus, login_attempt.verify_ms | 개선 전후 p95 비교 |
| 위험 점수 정확도 | synthetic_label, model_run | 정밀도·재현율·F1 |
| 케이스 오탐률 | suspicious_case.verdict vs synthetic_label | 오탐·미탐 비율 |
| 증거 무결성 | evidence_snapshot.sha256, suspicious_case.evidence_hash | 재계산 일치율 100% |

---

## 6. 실패 시나리오 점검

| # | 시나리오 | 막는 장치 | 결과 |
|---|---|---|---|
| 1 | 두 사람이 같은 좌석을 동시에 누름 | Redis `SET NX` 1차 → `seat_inventory` PK 2차 | 한 명만 성공 |
| 2 | 서울→대전, 대전→부산이 같은 좌석 | segment 1·2와 3·4로 PK가 다름 | 둘 다 성공 (구간 재판매) |
| 3 | 결제 버튼 연타 | `UNIQUE(reservation_id, idempotency_key)` | 첫 요청만 처리 |
| 4 | 키를 바꿔 결제 재시도 | 승인 1건 함수 기반 유니크 인덱스 | 두 번째 승인 저장 실패 → 즉시 환불 보상 |
| 5 | 결제 실패 | saga_instance → 보상 → seat_inventory 행 삭제 | 좌석 복구 |
| 6 | 결제 기한 초과 | Redis TTL 만료 + `(status, pay_deadline_at)` 스캐너 | Redis·DB 양쪽 반환 |
| 7 | Kafka가 같은 이벤트를 두 번 전달 | processed_event (Inbox) | 두 번째 skip |
| 8 | 서버가 DB 저장 후 이벤트 발행 전에 죽음 | outbox_event (같은 트랜잭션) | 재기동 후 릴레이가 발행 |
| 9 | 선점→결제→확정 이벤트가 섞여 도착 | partition_key = reservation_id | 같은 파티션, 순서대로 소비 |
| 10 | 매크로가 대기열 없이 좌석 API 호출 | `queue:pass` 토큰 검사 | 거부 (v3에서 막음) |
| 11 | 한 사람이 계정 4개로 매수 제한 우회 | 매수 집계를 ci_hash 기준 (`limit:{runId}:{ciHash}`) | 합산 제한 |
| 12 | 다른 CI 계정을 사서 우회 | 같은 기기·결제수단 → risk_score → 순번 하락, suspicious_case | 묶음 탐지 후 CCTV로 확인 |
| 13 | 로그인 폭주로 Argon2가 CPU를 다 씀 | 동시 검증 세마포어 + `rate:login` | 응답 지연은 생겨도 서버 다운 없음 (verify_ms로 측정) |
| 14 | 탈취한 리프레시 토큰 재사용 | token_family_id | 계열 전체 폐기 |
| 15 | 클라이언트가 녹화 이벤트를 재전송 | replay_event `{session_id, seq}` 유니크 | 중복 저장 없음 (v3에서 막음) |
| 16 | 녹화 원본이 TTL로 삭제 | 케이스 연결 시 legal_hold + evidence_snapshot | 증거 보존 |
| 17 | 관리자가 이유 없이 녹화 열람 | replay_access_log.purpose 필수, UNMASK는 SUPERVISOR | 감사 기록 |

---

## 7. 빅데이터 규모 가정

가상 데이터 생성량을 정할 때 쓰는 출발점입니다. 실제 수치는 생성 후 `ext_dataset.row_count`와 Mongo `collStats`로 확인해 발표 자료를 갱신합니다.

| 가정 | 값 |
|---|---|
| 가상 회원 | 20만 계정 (어뷰저 비율은 synthetic_label로 조절) |
| 예매 오픈 1회 동시 접속 | 5만 세션 |
| 세션당 behavior_log | 약 60건 |
| 녹화 | 위험 상위 10% 전체 녹화, 나머지는 클릭·도메인 이벤트만 (마우스 궤적 제외) |

| 컬렉션 | 오픈 1회 예상 건수 |
|---|---|
| behavior_log | 약 300만 |
| replay_event | 전체 녹화 5천 세션 × 약 400 + 샘플 4.5만 세션 × 약 80 = 약 560만 |
| login_attempt | 약 6.5만 (실패·재시도 포함) |
| ext_hotel_booking | 약 12만 (원본 그대로) |

---

## 8. 팀이 정해야 할 것

| 항목 | 선택지 | 영향 |
|---|---|---|
| 구간 재고 진행 | 진행 / segment_no=0 고정 | 스키마 변경 없음, 로직만 달라짐 |
| 취소 수수료 구간·비율 | cancel_fee_policy 행 값 | 노쇼 억제 효과를 가상 데이터로 비교 가능 |
| 녹화 샘플링 비율·보관 기간 | 기본 10% 전체 녹화, 90일 | 저장량, 개인정보 부담 |
| 회원 패널티 결합 규칙 | 최댓값(기본) / 가중 합 | 다계정 묶음 효과 |
| Oracle 에디션 | 파티셔닝 지원 여부 | 확장 #9 가능 여부 |

---

## 참고 자료

- MongoDB, BSON 문서 크기 16MB 한도와 GridFS: https://www.mongodb.com/docs/upcoming/core/gridfs/
- MongoDB 문서 크기 한도 정리: https://fast.io/resources/mongodb-document-size-limit/
- MongoDB 16MB 초과 오류 대응: https://oneuptime.com/blog/post/2026-03-31-mongodb-fix-mongoerror-document-exceeds-16mb/markdown
- MongoDB Time Series Collections: https://www.mongodb.com/docs/current/core/timeseries-collections/
- MongoDB 시계열 metaField 카디널리티와 버킷 수: https://oneuptime.com/blog/post/2026-03-31-mongodb-time-series-metafields/view
- Argon2id 파라미터·PHC 형식: https://rubydoc.info/gems/argon2id/file/README.md
- OWASP Password Storage Cheat Sheet: https://cheatsheetseries.owasp.org/cheatsheets/Password_Storage_Cheat_Sheet.html
- v1·v2 문서의 공공데이터·외부 데이터셋·기획 배경 출처는 각 문서 참고
