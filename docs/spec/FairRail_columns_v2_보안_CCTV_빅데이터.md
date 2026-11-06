# FairRail 추가 명세 v2 — 보안·CCTV 되돌아보기·빅데이터

기존 `FairRail_columns.md`(v1)에 더해지는 테이블입니다. v1 테이블은 그대로 두고, 바뀌는 곳만 아래 "v1 변경 사항"에 적었습니다.
`출처` 열의 **외부**는 Kaggle 등 외부 데이터셋 원본, **생성**은 가상 데이터, **시스템**은 서비스가 실행 중에 기록하는 값입니다.
`빅데이터` 표시는 건수가 수십만~수천만 단위로 쌓이는 컬렉션입니다. ERD 편집기의 "빅데이터 흐리게" 버튼이 이 표시를 기준으로 동작합니다.

---

## 0. 추가 기능 요약

| 기능 | 핵심 아이디어 | 새 테이블 |
|---|---|---|
| Argon2id 로그인 보안 | 비밀번호는 Argon2id PHC 문자열로 저장. 파라미터·페퍼 버전을 함께 기록해 나중에 강도를 올려도 로그인 시 자동 재해싱 | `member_credential`, `identity_verification`, `auth_session`, `login_attempt` |
| CCTV 되돌아보기 | 로그인 세션을 녹화 단위로 삼아, 화면 행동(클릭·마우스 궤적)과 서버 상태 변경(좌석 선점·결제·취소)을 **하나의 타임라인**에 기록. 의심 케이스가 열리면 같은 CI·기기의 여러 계정 세션을 나란히 재생 | `replay_session`, `replay_event`, `suspicious_case`, `case_session`, `case_marker`, `evidence_snapshot`, `replay_access_log` |
| 빅데이터 분석 | Kaggle 원본을 MongoDB에 그대로 적재하고, 패턴을 뽑아 가상 데이터와 위험 모델에 반영. 학습 결과를 버전별로 기록 | `ext_hotel_booking`, `ext_web_access_log`, `ext_renfe_price`, `ext_bot_detection`, `risk_feature`, `model_run` |

---

## 1. v1 변경 사항

| 대상 | 변경 | 이유 |
|---|---|---|
| `member.password_hash` | 삭제 → `member_credential`로 이동 | 회원 조회 쿼리·DTO에 해시가 섞이지 않게 분리. 인증 테이블만 접근 권한을 좁힐 수 있음 |
| `risk_score.model_version` | `model_run.model_version` FK 추가 | 점수가 어떤 학습 결과로 나왔는지 추적 |
| `behavior_log.session_id` | `auth_session.session_id` 논리 참조 | 서버 로그와 CCTV 녹화를 같은 세션 ID로 연결 |
| `behavior_log`, `queue_log` | 빅데이터 표시 | 요청 단위 로그라 건수가 가장 많음 |

### behavior_log 와 replay_event 의 차이

| | behavior_log (v1) | replay_event (v2) |
|---|---|---|
| 수집 위치 | 서버 (API 요청 단위) | 클라이언트 (화면 이벤트 단위) |
| 대상 | 모든 사용자 | 녹화 대상 세션만 (평시 샘플링, 위험 시 전체) |
| 용도 | 위험 점수 집계·통계 | 사람이 보고 판단하는 재생 |
| 보관 | TTL 180일 | 기본 90일, 케이스 연결 시 증거로 동결 |

---

## 2. 보안·인증 (Argon2id)

### 2-1. `member_credential` 로그인 인증 정보 (Oracle)

| 컬럼 | 타입 | 출처 | 설명 | 이유 |
|---|---|---|---|---|
| member_id | NUMBER PK, FK → member | 생성 | 회원 (1:1) | 프로필과 인증 정보 분리 |
| password_hash | VARCHAR2(255) | 시스템 | Argon2id PHC 문자열. 예: `$argon2id$v=19$m=19456,t=2,p=1$<salt>$<hash>` | 솔트와 파라미터가 문자열 안에 들어 있어 salt 컬럼이 따로 필요 없음 |
| hash_algo | VARCHAR2(20) | 시스템 | ARGON2ID | 알고리즘 교체 대비 |
| hash_params | VARCHAR2(40) | 시스템 | `m=19456,t=2,p=1` | 정책 파라미터와 다르면 재해싱 대상. 통계·조회용으로 따로 둠 |
| pepper_key_id | VARCHAR2(20) | 시스템 | 페퍼 키 버전 | 페퍼(서버 비밀값)는 DB 밖(환경변수·KMS)에 두고 버전만 기록. 키 교체 시 어느 키로 해싱했는지 판별 |
| needs_rehash | CHAR(1) | 시스템 | Y/N | 다음 로그인 성공 시 새 파라미터로 다시 해싱 (평문은 로그인 순간에만 있으므로) |
| failed_count | NUMBER(3) | 시스템 | 연속 로그인 실패 횟수 | 계정 잠금 기준 |
| locked_until | TIMESTAMP | 시스템 | 잠금 해제 시각 | 무차별 대입 방지 |
| password_changed_at | TIMESTAMP | 시스템 | 비밀번호 변경 시각 | 변경 직후 대량 구매 같은 탈취 의심 신호 |
| last_login_at | TIMESTAMP | 시스템 | 마지막 로그인 | 휴면 계정 갑작스런 활동 탐지 |

### 2-2. `identity_verification` 본인인증 이력 (Oracle)

| 컬럼 | 타입 | 출처 | 설명 | 이유 |
|---|---|---|---|---|
| verification_id | NUMBER PK | 생성 | | |
| member_id | NUMBER FK → member | 생성 | 인증한 계정 | |
| ci_hash | VARCHAR2(64) | 생성 | 인증 결과 CI 해시 | 같은 CI로 짧은 기간에 여러 계정을 인증하면 다계정 신호 |
| provider | VARCHAR2(20) | 생성 | MOCK_PASS / MOCK_PHONE | 모의 본인인증 |
| result | VARCHAR2(10) | 시스템 | SUCCESS / FAIL | |
| verified_at | TIMESTAMP | 생성 | 인증 시각 | |

### 2-3. `auth_session` 로그인 세션 (Oracle)

| 컬럼 | 타입 | 출처 | 설명 | 이유 |
|---|---|---|---|---|
| session_id | VARCHAR2(36) PK | 시스템 | UUID | **CCTV 녹화 단위.** replay_session, behavior_log와 같은 키 |
| member_id | NUMBER FK → member | 생성 | | |
| refresh_token_hash | VARCHAR2(64) | 시스템 | 리프레시 토큰 SHA-256 | 토큰은 무작위 고엔트로피 값이라 느린 Argon2가 필요 없음. 매 갱신 요청마다 검증해야 해서 빠른 해시가 맞음 |
| device_hash | VARCHAR2(64) | 생성 | 기기 지문 해시 | |
| ip_hash | VARCHAR2(64) | 생성 | IP 해시 | |
| user_agent | VARCHAR2(300) | 생성 | | |
| created_at | TIMESTAMP | 시스템 | 로그인 시각 | |
| expires_at | TIMESTAMP | 시스템 | 만료 시각 | |
| revoked_at | TIMESTAMP | 시스템 | 강제 종료 시각 | |
| revoke_reason | VARCHAR2(20) | 시스템 | LOGOUT / ROTATED / ADMIN / SUSPICIOUS | 관리자 조치로 끊긴 세션 구분 |

### 2-4. `login_attempt` 로그인 시도 (MongoDB, 빅데이터)

| 필드 | 타입 | 출처 | 설명 | 이유 |
|---|---|---|---|---|
| _id | ObjectId | 시스템 | | |
| member_id | Long | 생성 | 대상 계정 (없으면 null) | |
| email_hash | String | 생성 | 입력한 이메일 해시 | 없는 계정 대상 시도도 추적 → 크리덴셜 스터핑 탐지 |
| result | String | 생성 | SUCCESS / WRONG_PASSWORD / LOCKED / NOT_FOUND / RATE_LIMITED | |
| ip_hash, device_hash | String | 생성 | | 한 IP에서 여러 계정 시도 탐지 |
| user_agent | String | 생성 | | |
| session_id | String | 시스템 | 성공 시 발급된 세션 | |
| verify_ms | Int | 시스템 | Argon2 검증 소요 시간 | **예매 오픈 직전 로그인 폭주 시 CPU·메모리 병목 측정** (부하 테스트 수치) |
| ts | Date | 생성 | 시도 시각 | TTL 인덱스 기준 |

### 운영 고려 사항

| 항목 | 내용 |
|---|---|
| 파라미터 | OWASP 권장값 중 하나인 m=19456(19MiB), t=2, p=1로 시작하고, 서버 사양에서 검증 시간 측정 후 조정 |
| 메모리 | 해시 1회에 약 19MiB. 동시 로그인 100건이면 약 1.9GB → **동시 검증 수를 세마포어로 제한**하고 초과 요청은 대기 |
| 피크 분산 | 예매 오픈 전에 로그인하도록 유도, 오픈 시각엔 이미 발급된 세션으로 대기열 진입 |
| 타이밍 공격 | 없는 계정도 더미 해시로 검증해서 응답 시간을 같게 유지 |
| 라이브러리 | Spring Security `Argon2PasswordEncoder` (Bouncy Castle 필요) |

---

## 3. CCTV 되돌아보기

```
로그인 → auth_session.session_id 발급 = 녹화 시작
  화면 이벤트 ──┐
  서버 도메인 이벤트(Kafka) ──┴→ replay_event (같은 session_id, seq 순)
위험 점수 임계 초과 / 규칙 적중 / 관리자 지정
  → suspicious_case 생성
  → 같은 CI·기기·결제수단 세션을 case_session으로 묶음
  → 자동 마커(case_marker) 표시: "0.1초 간격 좌석 클릭 28회" 등
  → evidence_snapshot으로 동결 (TTL 삭제 방지 + 해시로 무결성)
관리자가 타임라인 재생·마커 추가·판정 → admin_action
열람 기록은 replay_access_log에 전부 남김
```

재생 방식은 화면 DOM 전체를 녹화하는 방식(rrweb 등) 대신 **화면 ID + 요소 ID + 좌표 + 도메인 이벤트**를 기록하고 재생기가 화면을 다시 그리는 방식을 기본으로 합니다. 저장량이 작고, 개인정보가 화면 통째로 남지 않습니다. DOM 녹화는 확장 과제로 둡니다.

### 3-1. `replay_session` 녹화 세션 (MongoDB, 빅데이터)

| 필드 | 타입 | 출처 | 설명 | 이유 |
|---|---|---|---|---|
| session_id | String PK | 시스템 | = auth_session.session_id | 로그인 세션과 1:1 |
| member_id | Long | 생성 | | |
| ci_hash, device_hash, ip_hash | String | 생성 | 묶음 키 | 케이스에서 연관 세션 검색 |
| started_at, ended_at | Date | 생성 | 녹화 구간 | |
| event_count | Int | 시스템 | 이벤트 수 | 재생 전 분량 확인 |
| run_ids | Array | 생성 | 이 세션에서 본 운행 | 특정 열차 기준으로 세션 검색 |
| recording_mode | String | 시스템 | SAMPLED / FULL | 평시 샘플링, 위험 점수 높은 사용자는 전체 녹화 → **저장량 제어** |
| risk_score_at_start | Double | 시스템 | 시작 시점 점수 | 녹화 모드 결정 근거 |
| mask_policy_version | String | 시스템 | 입력 마스킹 규칙 버전 | 어떤 규칙으로 가렸는지 추적 |
| retention_until | Date | 시스템 | 보관 기한 (기본 90일) | 개인정보 최소 보관 |
| legal_hold | Boolean | 시스템 | 삭제 보류 | 케이스에 연결되면 true |

### 3-2. `replay_event` 녹화 이벤트 (MongoDB 시계열 컬렉션, 빅데이터)

`timeField: ts`, `metaField: session_id`, `granularity: seconds`, `expireAfterSeconds: 7776000`(90일)

| 필드 | 타입 | 출처 | 설명 | 이유 |
|---|---|---|---|---|
| session_id | String (metaField) | 시스템 | 녹화 세션 | 세션별 버킷 저장 → 한 세션 재생 조회가 빠름 |
| ts | Date (timeField) | 생성 | 이벤트 시각 (ms) | |
| seq | Long | 시스템 | 세션 내 순번 | 같은 ms에 여러 이벤트가 와도 순서 보장 |
| t_offset_ms | Long | 시스템 | 세션 시작부터 경과 시간 | 재생 타임라인 위치, 여러 세션 동시 재생 시 정렬 |
| type | String | 생성 | PAGE_VIEW / CLICK / INPUT / SCROLL / MOUSE_PATH / VISIBILITY / API / DOMAIN | |
| screen | String | 생성 | 화면 ID (queue, seat_map, payment) | 재생기가 화면을 다시 그리는 기준 |
| target | String | 생성 | 요소 ID (seat-5A, btn-pay) | 어떤 좌석·버튼을 눌렀는지 |
| x, y | Int | 생성 | 클릭 좌표 (화면 비율 0~1000) | 기기 해상도와 무관하게 재생 |
| path | Array | 생성 | 마우스 궤적 샘플 [[dt, x, y], …] | **사람은 곡선·가감속, 매크로는 직선·등속·순간이동** |
| input_masked | String | 시스템 | 입력값 마스킹 (길이만 남김) | 개인정보 미보관 |
| api | Object | 시스템 | { method, path, status, latency_ms } | 화면 행동과 서버 응답을 같이 봄 |
| domain_event | Object | 시스템 | { type: SEAT_HELD, ref_id, kafka_event_id } | 클릭 → 좌석 선점 → 결제 → 취소가 한 줄로 이어짐 |

### 3-3. `suspicious_case` 의심 케이스 (Oracle)

| 컬럼 | 타입 | 출처 | 설명 | 이유 |
|---|---|---|---|---|
| case_id | NUMBER PK | 시스템 | | |
| subject_type | VARCHAR2(10) | 시스템 | CI / PAYMENT / DEVICE | 계정이 아닌 묶음 단위 |
| subject_hash | VARCHAR2(64) | 시스템 | | |
| trigger_type | VARCHAR2(20) | 시스템 | RISK_THRESHOLD / RULE / MODEL / ADMIN | 어떻게 열렸는지 |
| trigger_detail | VARCHAR2(200) | 시스템 | 예: 같은 CI 4계정 동시 좌석 선점 | 관리자가 첫 화면에서 이유를 봄 |
| risk_score_at_open | NUMBER(5,2) | 시스템 | 생성 시점 점수 | |
| window_from, window_to | TIMESTAMP | 시스템 | 되돌아볼 시간 범위 | 재생 범위 기본값 |
| status | VARCHAR2(12) | 시스템 | OPEN / REVIEWING / CONFIRMED / DISMISSED | |
| assignee_id | NUMBER | 시스템 | 담당 관리자 | |
| verdict | VARCHAR2(20) | 시스템 | RESELLER / MACRO / CANCEL_ABUSE / NORMAL | synthetic_label과 비교해 **오탐률** 측정 |
| admin_action_id | NUMBER FK → admin_action | 시스템 | 최종 조치 | |
| opened_at, closed_at | TIMESTAMP | 시스템 | | 처리 소요 시간 |

### 3-4. `case_session` 케이스-세션 연결 (Oracle)

| 컬럼 | 타입 | 출처 | 설명 | 이유 |
|---|---|---|---|---|
| case_id | NUMBER PK, FK → suspicious_case | 시스템 | | |
| session_id | VARCHAR2(36) PK, FK → auth_session | 시스템 | | 한 케이스에 여러 세션 |
| member_id | NUMBER FK → member | 시스템 | 세션 계정 | |
| link_reason | VARCHAR2(20) | 시스템 | TRIGGER / SAME_CI / SAME_DEVICE / SAME_PAYMENT / SAME_IP | **다계정을 나란히 재생하는 근거** |
| sync_offset_ms | NUMBER | 시스템 | 동시 재생 시간 보정 | 기기 시계 오차 보정 |

### 3-5. `case_marker` 타임라인 마커 (Oracle)

| 컬럼 | 타입 | 출처 | 설명 | 이유 |
|---|---|---|---|---|
| marker_id | NUMBER PK | 시스템 | | |
| case_id | NUMBER FK → suspicious_case | 시스템 | | |
| session_id | VARCHAR2(36) | 시스템 | 표시할 세션 | |
| at_ts | TIMESTAMP | 시스템 | 타임라인 위치 | 누르면 그 시점으로 이동 |
| marker_type | VARCHAR2(10) | 시스템 | AUTO / MANUAL | 시스템 탐지와 관리자 메모 구분 |
| rule_code | VARCHAR2(30) | 시스템 | FAST_CLICK / SAME_SEAT_RETRY / CANCEL_AFTER_PAY / MULTI_ACCOUNT_SYNC / LINEAR_MOUSE | 어떤 규칙이 잡았는지 |
| label | VARCHAR2(200) | 시스템 | 예: 0.1초 간격 좌석 클릭 28회 | |
| severity | VARCHAR2(6) | 시스템 | LOW / MID / HIGH | |
| created_by | NUMBER | 시스템 | 작성 관리자 (AUTO는 null) | |

### 3-6. `evidence_snapshot` 증거 동결 (MongoDB, 빅데이터)

| 필드 | 타입 | 출처 | 설명 | 이유 |
|---|---|---|---|---|
| _id | ObjectId | 시스템 | | |
| case_id | Long | 시스템 | 케이스 | |
| session_id | String | 시스템 | | |
| events | Array | 시스템 | 해당 구간 replay_event 복사본 | 원본이 TTL로 지워져도 케이스 증거는 남음 |
| event_count | Int | 시스템 | | |
| sha256 | String | 시스템 | events 전체 해시 | **사후 변조 여부 확인** |
| frozen_at | Date | 시스템 | 동결 시각 | |
| frozen_by | Long | 시스템 | 동결한 관리자 | |

### 3-7. `replay_access_log` 녹화 열람 기록 (Oracle)

| 컬럼 | 타입 | 출처 | 설명 | 이유 |
|---|---|---|---|---|
| access_id | NUMBER PK | 시스템 | | |
| admin_id | NUMBER | 시스템 | 열람자 | |
| case_id | NUMBER FK → suspicious_case | 시스템 | | 케이스 없이 임의 열람 불가 |
| session_id | VARCHAR2(36) | 시스템 | | |
| action | VARCHAR2(10) | 시스템 | VIEW / UNMASK / EXPORT | 마스킹 해제는 별도 기록 |
| purpose | VARCHAR2(200) | 시스템 | 열람 사유 (필수) | 녹화 열람 자체가 개인정보 처리 → 누가 언제 왜 봤는지 감사 |
| accessed_at | TIMESTAMP | 시스템 | | |

---

## 4. 빅데이터 (외부 데이터셋 원본·분석)

외부 데이터셋은 원본 컬럼 그대로 MongoDB `ext_*` 컬렉션에 적재하고, 변환 결과만 FairRail 테이블과 모델에 씁니다. 원본 보존은 "실제 데이터로 패턴을 검증했다"는 발표 근거가 됩니다.

### 4-1. `ext_hotel_booking` Hotel Booking Demand 원본 (MongoDB, 빅데이터, 약 12만 건)

주요 컬럼만 적었습니다. 원본 32개 컬럼을 전부 적재합니다.

| 필드 | 타입 | 출처 | 설명 | FairRail 활용 |
|---|---|---|---|---|
| hotel | String | 외부 | City / Resort | 도메인 구분 |
| is_canceled | Int | 외부 | 취소 여부 0/1 | 취소 예측 라벨 |
| lead_time | Int | 외부 | 예약~도착 일수 | 예매~출발 간격과 취소율 관계 |
| arrival_date_year / month / day_of_month | Int/String | 외부 | 도착일 | 성수기(명절) 효과 비교 |
| adults | Int | 외부 | 인원 | 매수와 취소율 관계 |
| previous_cancellations | Int | 외부 | 과거 취소 횟수 | **반복 취소 위험 점수 가중치 근거** |
| previous_bookings_not_canceled | Int | 외부 | 과거 정상 이용 횟수 | 신뢰 이력이 위험을 상쇄하는 정도 |
| is_repeated_guest | Int | 외부 | 재방문 여부 | 신규 계정 기본 신뢰도 근거 |
| booking_changes | Int | 외부 | 예약 변경 횟수 | |
| deposit_type | String | 외부 | No Deposit / Non Refund / Refundable | 취소 수수료 정책이 취소율에 주는 영향 |
| days_in_waiting_list | Int | 외부 | 대기 일수 | 취소표 대기 설계 참고 |
| market_segment, distribution_channel | String | 외부 | 판매 경로 (TA/TO 등) | 대리점 경로 = 대량 구매자 패턴 |
| customer_type | String | 외부 | Transient / Group 등 | |
| adr | Double | 외부 | 1박 평균 요금 | |
| reservation_status | String | 외부 | Check-Out / Canceled / No-Show | 노쇼 비율 |
| reservation_status_date | String | 외부 | 상태 변경일 | 취소 시점 분포 → minutes_before_departure 생성 |

### 4-2. `ext_web_access_log` Web Server Access Logs 원본 (MongoDB, 빅데이터)

Nginx combined 로그 형식을 파싱해서 적재합니다.

| 필드 | 타입 | 출처 | 설명 | FairRail 활용 |
|---|---|---|---|---|
| ip | String | 외부 | 요청 IP (적재 시 해시) | IP 집중도 |
| ts | Date | 외부 | 요청 시각 | 요청 간격 분포 |
| method, url, protocol | String | 외부 | 요청 정보 | 반복 조회 패턴 |
| status | Int | 외부 | HTTP 상태 | |
| bytes | Int | 외부 | 응답 크기 | |
| referrer | String | 외부 | | 직접 접근 비율 (봇은 referrer 없음) |
| user_agent | String | 외부 | | 봇 UA 라벨링 |
| session_key | String | 시스템 | ip+UA 30분 윈도우로 만든 세션 | 세션 단위 피처 추출 |
| interval_ms | Int | 시스템 | 같은 세션 직전 요청과 간격 | **매크로 interval_ms 분포의 실데이터 근거** |

### 4-3. `ext_renfe_price` Renfe 가격 관측 원본 (MongoDB, 빅데이터)

| 필드 | 타입 | 출처 | 설명 | FairRail 활용 |
|---|---|---|---|---|
| insert_date | Date | 외부 | 관측 시각 | |
| origin, destination | String | 외부 | 출발·도착역 | |
| start_date, end_date | Date | 외부 | 출발·도착 시각 | |
| train_type | String | 외부 | AVE 등 | |
| train_class, fare | String | 외부 | 등급·요금제 | |
| price | Double | 외부 | 가격 | |
| days_before | Int | 시스템 | start_date − insert_date | **출발일 대비 수요 곡선 → 가상 트래픽 분포** |

### 4-4. `ext_bot_detection` Web Bot Detection Dataset (MongoDB, 빅데이터, 선택)

| 필드 | 타입 | 출처 | 설명 | FairRail 활용 |
|---|---|---|---|---|
| session_id | String | 외부 | 세션 | |
| label | String | 외부 | human / moderate bot / advanced bot | 마우스 궤적 판별 기준 검증 |
| web_log | Array | 외부 | 세션 요청 로그 | |
| mouse_movements | Array | 외부 | 마우스 좌표 시퀀스 | replay_event.path와 같은 형태로 변환 |

> 공개 페이지에서 파일 확보 가능 여부를 먼저 확인하고, 실제 필드명에 맞춰 확정합니다.

### 4-5. `risk_feature` 학습용 피처 스냅샷 (MongoDB, 빅데이터)

| 필드 | 타입 | 출처 | 설명 | 이유 |
|---|---|---|---|---|
| subject_type, subject_hash | String | 시스템 | 대상 | |
| window_date | Date | 시스템 | 집계 기준일 | 시점별 재현 |
| features | Object | 시스템 | risk_score의 모든 신호 + replay 기반 신호(마우스 직선도 등) | 신호 추가 시 스키마 변경 없음 |
| label | String | 생성 | synthetic_label 조인 값 | 학습·평가에만 사용 |
| source | String | 시스템 | SYNTHETIC / EXT_HOTEL / EXT_LOG | 어떤 데이터에서 나온 피처인지 |
| model_version | String | 시스템 | 이 피처로 학습한 모델 | |

### 4-6. `model_run` 모델 학습 기록 (Oracle)

| 컬럼 | 타입 | 출처 | 설명 | 이유 |
|---|---|---|---|---|
| model_version | VARCHAR2(20) PK | 시스템 | 예: iforest-2026.11-01 | risk_score.model_version이 참조 |
| algorithm | VARCHAR2(20) | 시스템 | RULE / IFOREST | 두 방식 비교 |
| params | CLOB | 시스템 | contamination, n_estimators 등 (JSON) | 재현 |
| train_source | VARCHAR2(100) | 시스템 | 학습 데이터 범위 | |
| trained_at | TIMESTAMP | 시스템 | | |
| precision_score | NUMBER(4,3) | 시스템 | 정밀도 | **발표용 성능 수치** |
| recall_score | NUMBER(4,3) | 시스템 | 재현율 | |
| f1_score | NUMBER(4,3) | 시스템 | F1 | |
| threshold | NUMBER(5,2) | 시스템 | 케이스 자동 생성 임계값 | suspicious_case 트리거 기준 |
| is_active | CHAR(1) | 시스템 | 운영 적용 여부 | 한 번에 하나만 Y |

---

## 5. 성과 목표 추가

| 지표 | 측정 방법 |
|---|---|
| Argon2 로그인 처리량 | login_attempt.verify_ms p95, 동시 검증 제한 전후 TPS 비교 |
| CCTV 저장량 | 샘플링/전체 녹화 비율별 replay_event 용량 비교 |
| 케이스 정확도 | suspicious_case.verdict vs synthetic_label 오탐·미탐률 |
| 증거 무결성 | evidence_snapshot.sha256 재계산 일치율 100% |

---

## 참고 자료

**보안**
- OWASP Password Storage Cheat Sheet: https://cheatsheetseries.owasp.org/cheatsheets/Password_Storage_Cheat_Sheet.html
- Argon2id 기본 파라미터(OWASP 두 번째 권장값 m=19456, t=2, p=1)와 PHC 문자열 예시: https://rubydoc.info/gems/argon2id/file/README.md
- Argon2 vs bcrypt 비교: https://mojoauth.com/security-guides/bcrypt-vs-argon2
- Spring Security Argon2PasswordEncoder: https://docs.spring.io/spring-security/reference/features/authentication/password-storage.html

**CCTV 되돌아보기**
- MongoDB Time Series Collections (timeField, metaField): https://www.mongodb.com/docs/current/core/timeseries-collections/
- MongoDB 시계열 metaField 설계: https://oneuptime.com/blog/post/2026-03-31-mongodb-time-series-metafields/view
- rrweb (DOM 녹화 방식 확장 시 참고): https://github.com/rrweb-io/rrweb/blob/main/guide.md

**빅데이터**
- Kaggle, Hotel Booking Demand: https://www.kaggle.com/datasets/jessemostipak/hotel-booking-demand
- Kaggle, Web Server Access Logs 활용 예: https://github.com/zaki1003/bot-detection-prototype
- Iliou et al., Web Bot Detection Dataset, Bournemouth University (2020): https://bordar.bournemouth.ac.uk/272/
- Kaggle, Spanish High Speed Rail Tickets Pricing (Renfe): https://www.kaggle.com/thegurusteam/spanish-high-speed-rail-system-ticket-pricing
- v1 명세의 공공데이터·기획 배경 출처는 `FairRail_columns.md` 참고
