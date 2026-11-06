# FairRail ERD 재점검 보고서 v4

v3 점검 이후 팀 결정 사항을 예시값으로 채우고, 지금까지 만든 내용(v1·v2·v3 명세, 설계 문서, 확장 계획)을 ERD 편집기에 모두 넣은 뒤 한 번 더 전체를 점검한 결과입니다.

---

## 0. 결과 요약

| 항목 | v3 | v4 |
|---|---|---|
| 테이블 | 53 | **58** (운영 54 + 확장 예정 4) |
| 저장소 | | Oracle 42 · MongoDB 11 · Redis 1 (+ 확장 예정 4) |
| 컬럼 | 444 | **480** |
| 관계 | 75 | **83** |
| NOT NULL 지정 컬럼 | 0 (PK만) | **157** (+ PK·공통 컬럼) |
| DDL CHECK 제약 | 0 | **54** |
| FK 인덱스 | 0 | **46** |
| 예시 데이터 | 0 | **24행** (5개 테이블) |

| 점검 결과 | 건수 |
|---|---|
| 이번에 찾아서 고친 오류 | 11 |
| 새로 넣은 것 | 9 |
| 고치지 않고 남긴 문제점 (결정 필요·범위 밖) | 8 |
| 검사 스크립트 | FAIL 0 · WARN 0 (md 비교 시 의도된 차이 1건: member.password_hash 이동) |

---

## 1. 점검 방법

| 점검 | 방법 | 결과 |
|---|---|---|
| md ↔ 편집기 비교 | v1·v2·v3 명세의 `### \`테이블\`` 표 첫 열을 편집기 스키마와 자동 대조 (`tools/check-erd.js`) | 아래 2장 |
| v3 추가 컬럼 26개 | v3 보고서 2-2 표의 테이블·컬럼을 하나씩 대조 | 26개 전부 존재 |
| 구조 무결성 | 테이블·컬럼 중복, PK 유무, FK 대상·타입 일치, FK 표시 누락, Oracle 예약어, 30자 제한, 배치(LAYOUT) 누락 | 통과 |
| 예시 데이터 | 없는 컬럼, CHECK 허용값 밖 값, FK 값이 대상 예시에 없는 경우, PK null | 통과 |
| 마이그레이션 | v2·v3에 저장해 둔 브라우저가 v4로 올라왔을 때 새로 연 편집기와 결과가 같은지 | 같음 |
| 패치 멱등성 | 패치를 두 번 적용해도 결과가 같은지 | 같음 |
| DDL 문법 | 생성 DDL 573문장을 SQL 파서(sqlglot, Oracle 방언)로 파싱 | 573/573 통과 |
| 실제 화면 | 헤드리스 Chrome으로 새로 열기·v3 저장 상태에서 열기·모바일 폭 각각 테이블 선택, 예시 행, 문서 창, 문서 속 테이블 링크 이동, 빅데이터 흐리게, 확장 예정 숨기기, 내보내기 3종 실행 | 스크립트 오류 0 |
| 편집 → 패치 왕복 | 편집기 JSON에서 컬럼 추가·타입 변경·컬럼 삭제·테이블 추가 → `tools/erd-diff.js`로 패치 생성 → HTML에 적용 → 다시 비교 | "차이 없음" |

---

## 2. md 명세 ↔ 편집기 비교

| 문서 | 비교한 테이블 | 차이 | 판단 |
|---|---|---|---|
| FairRail_columns.md (v1) | 31 | `member.password_hash` 1건 | v2에서 `member_credential`로 옮긴 것. 정상 |
| FairRail_columns_v2_보안_CCTV_빅데이터.md | 17 | 0 | |
| FairRail_ERD_점검_v3.md (새 테이블) | 4 | 0 | |
| v3 보고서 2-2 (추가 컬럼 26개) | 21행 | 0 | |

v2 문서에 적힌 "replay_event = 시계열 컬렉션", "evidence_snapshot = 문서 1개"는 v3에서 바뀐 설계입니다. **이제 최신 명세의 원본은 편집기**이고, md 파일들은 변경 이력으로만 둡니다. 최신 전체 명세는 편집기 "내보내기 → Markdown 명세"로 한 파일로 받을 수 있고, 여기에 결정 사항·예시 데이터·설계 문서까지 포함됩니다.

---

## 3. 이번에 찾아서 고친 오류

| # | 구분 | 문제 | 수정 |
|---|---|---|---|
| 1 | 스키마 | **PK 외 모든 컬럼이 NULL 허용.** 예약자·운행·결제 금액 없이도 행이 저장됨 | NOT NULL(NN) 키 추가. FK·상태 코드는 자동 지정하고, 의미상 비어도 되는 15개(상시 정책의 sale_event_id, 판정 전 verdict 등)는 제외 목록으로 관리. 나머지 필수값은 명시 지정 |
| 2 | DDL | `NOT NULL DEFAULT` 순서. Oracle은 DEFAULT가 제약보다 앞이어야 함 | `DEFAULT SYSTIMESTAMP NOT NULL` 순서로 생성 |
| 3 | 편집기 | HTML 파일을 **직접 열면 한글이 깨짐** (charset 선언 없음) | `<meta charset="utf-8">` 추가 |
| 4 | 편집기 | HTML 파일을 직접 열면 **숨긴 창이 화면 전체를 덮어 클릭이 안 됨** | `[hidden]` 규칙을 파일 안에 포함 |
| 5 | 스키마 | 관리자 로그인·세션이 회원 전용 구조. 관리자 계정 무차별 대입을 기록할 곳이 없음 | `login_attempt`, `auth_session`에 `actor_type`, `admin_id` 추가. 세션에는 "회원/관리자 중 하나만" 행 단위 CHECK |
| 6 | 스키마 | 명절 전체 매수 제한(PER_HOLIDAY)을 빠르게 확인할 Redis 키 없음 | `limit:event:{saleEventId}:{ciHash}` 추가 |
| 7 | 스키마 | 좌석 등급 코드가 `car_type`에만 정의되고 `seat`·`fare`·`waitlist`는 자유 텍스트 | 모두 `GENERAL / FIRST`로 통일, CHECK 적용 |
| 8 | 스키마 | `phone_enc` 암호화 키 버전 없음. 키를 바꾸면 복호화할 키를 모름 | `member.enc_key_id` 추가 |
| 9 | DDL | Oracle은 FK에 인덱스를 자동으로 만들지 않음. 부모 삭제 시 잠금·조인 성능 문제 | FK 인덱스 46개 자동 생성 (PK·UNIQUE 앞 컬럼은 제외) |
| 10 | DDL | 제약 이름이 30자를 넘는 경우 (Oracle 12.1 이하 오류) | 30자 이내로 자동 축약, 중복 없음 확인 |
| 11 | 편집기 | 테이블 상자에서 `PK FK` 표시가 두 줄로 깨져 행을 넘침 | 키 칸 너비 조정 |

---

## 4. 새로 넣은 것

| # | 내용 | 위치 |
|---|---|---|
| 1 | **팀 결정 사항 13개를 예시값으로** 채움. 상태(예시/검토 중/확정)를 바꾸며 관리 | 편집기 "문서 → 팀 결정 사항" (편집 가능) |
| 2 | `app_policy` 운영 설정 테이블 + 예시 13행 (구간 재고 OFF, 결제 기한 10분, 녹화 10%·90일, Argon2 동시 검증 32 등) | 기준 데이터 |
| 3 | 예시 행: `sale_event` 1, `purchase_limit_policy` 3, `cancel_fee_policy` 5, `model_run` 2 | 각 테이블 패널 "예시 데이터", DDL INSERT |
| 4 | 확장 예정 테이블 4개 (`ticket_transfer`, `member_push_token`, `password_reset_token`, `common_code`). 점선 표시, DDL 제외 | "확장 예정" 버튼으로 숨기기 |
| 5 | 설계 문서 7종을 편집기 안에 넣음: 결정 사항, 공통 규칙, 흐름, 기능 추적표, 실패 시나리오 19개, 가상 데이터 생성, 확장 계획, 변경 이력. 문서 속 테이블 이름을 누르면 구조도로 이동 | "문서" 버튼, 첫 화면 패널 |
| 6 | DDL 개선: NOT NULL, CHECK, FK 인덱스, 함수 기반 유니크 인덱스, 예시 데이터 INSERT | "내보내기 → Oracle DDL" |
| 7 | Markdown 내보내기를 전체 명세(결정 사항 + 모든 테이블 + 예시 데이터 + 설계 문서)로 확장 | "내보내기 → Markdown 명세" |
| 8 | 검사 스크립트 `tools/check-erd.js` (구조·예시·마이그레이션·DDL·md 비교, DDL 파일 생성) | 팀 저장소 |
| 9 | 패치 생성 스크립트 `tools/erd-diff.js` (팀원이 편집기에서 고친 JSON → 다음 버전 패치 코드) | 팀 저장소, CLAUDE.md 절차 |

---

## 5. 남은 문제점

| # | 문제 | 영향 | 권장 조치 | 시점 |
|---|---|---|---|---|
| 1 | MongoDB 인덱스·TTL·유니크가 비고 텍스트로만 있음. 편집기 DDL은 Oracle 전용 | Mongo 쪽은 손으로 만들어야 함 | `mongo-init.js`에 behavior_log, replay_event, login_attempt 인덱스·TTL 작성 | 1주차 인프라 |
| 2 | DDL은 파서로 문법만 확인. 실제 Oracle 실행 검증은 아직 | 에디션별 차이(함수 기반 인덱스 등) 가능성 | Docker Oracle에 DDL 1회 실행 후 결과 기록 | 1주차 |
| 3 | 시간은 TIMESTAMP(KST, 시간대 없음) | 서버·DB·JVM 시간대가 다르면 결제 기한 계산 오류 | Docker·JVM·DB 시간대를 Asia/Seoul로 고정 | 1주차 |
| 4 | 예시값은 실제 코레일 기준이 아님 (수수료율, 매수 제한, 일정) | 발표 시 오해 가능 | 확정 전까지 "예시" 상태 유지, 발표 자료에 명시 | 확정 시 |
| 5 | 편집기 저장은 브라우저마다 따로 | 여러 명이 동시에 고치면 서로 덮어씀 | JSON 내보내기 → erd-diff 패치 → 한 명이 병합 (CLAUDE.md 절차) | 상시 |
| 6 | 복합 PK 테이블 9개 | JPA 매핑이 단일 PK보다 복잡 | `@IdClass` 또는 `@EmbeddedId`: route_station, train_car, train_stop, member_device, seat_inventory, reservation_seat, processed_event, risk_score, case_session | 엔티티 작성 시 |
| 7 | Bot Detection 데이터셋 확보 여부 미정 | `ext_bot_detection` 필드 미확정 | 확보 못 하면 확장 예정으로 전환 | 1주차 |
| 8 | 편집기 글꼴은 외부(Google Fonts)에서 불러옴 | 오프라인이면 시스템 글꼴로 대체 (기능 영향 없음) | 그대로 둠 | - |

---

## 6. 결정 사항 (예시값)

| 항목 | 예시값 | 반영 위치 |
|---|---|---|
| 구간 재고 진행 | OFF (segment_no = 0) | app_policy inventory.segment_mode |
| 1인 매수 제한 | 1회 4매 · 열차당 4매 · 명절 전체 8매 | purchase_limit_policy |
| 취소 수수료 | 3일 전 0% · 1~3일 5% · 3시간~1일 10% · 3시간 이내 20% · 출발 후 40% | cancel_fee_policy |
| 결제 기한 | 10분 | app_policy reservation.pay_deadline_min |
| 대기열 처리량 | 초당 200명 · 입장 토큰 300초 | app_policy queue.* |
| 패널티 결합 | MAX | app_policy risk.member_penalty_rule |
| 점수 → 대기 지연 | 1점당 1초 | app_policy risk.penalty_ms_per_point |
| 케이스 임계값 | 80점 | model_run.threshold |
| 점수 감쇠 | 반감기 30일 | model_run.decay_half_life_days |
| 녹화 샘플링 | 위험 상위 10%, 70점 이상 무조건 | app_policy replay.* |
| 녹화 보관 | 90일 | app_policy replay.retention_days |
| Argon2id | m=19456, t=2, p=1 · 동시 검증 32 | app_policy auth.* |
| Oracle 에디션 | Docker Oracle Free, 파티셔닝 미사용 전제 | 인프라 |

---

## 참고 자료

- Oracle 예약어 목록: https://docs.oracle.com/en/database/oracle/oracle-database/19/sqlrf/Oracle-SQL-Reserved-Words.html
- sqlglot (DDL 문법 확인에 사용한 SQL 파서): https://github.com/tobymao/sqlglot
- v1~v3 문서의 출처는 각 문서 참고
