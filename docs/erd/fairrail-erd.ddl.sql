-- FairRail Oracle DDL (ERD 편집기에서 생성, 스키마 v5)
-- 공통 컬럼 created_at, updated_at 자동 포함 (수정 없는 테이블은 updated_at 생략) · 제약 이름은 30자 이내로 축약
-- 상태 코드 CHECK 제약은 컬럼 설명이 "A / B / C" 형식일 때 자동 생성
-- 확장 예정이라 제외: ticket_transfer, member_push_token, password_reset_token, common_code

CREATE TABLE station (
  station_id                 VARCHAR2(10) NOT NULL,
  station_name               VARCHAR2(50) NOT NULL,
  latitude                   NUMBER(9,6),
  longitude                  NUMBER(9,6),
  created_at                 TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
  updated_at                 TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
  CONSTRAINT pk_station PRIMARY KEY (station_id)
);
COMMENT ON TABLE station IS '역 - 역 기본 정보. 공공데이터의 역 코드를 그대로 PK로 사용한다.';
COMMENT ON COLUMN station.station_id IS '역 코드 / 공공데이터 코드 그대로 써야 다른 데이터와 조인 가능';
COMMENT ON COLUMN station.station_name IS '역 이름 / 화면 표시';
COMMENT ON COLUMN station.latitude IS '위도 / 선택. 지도·관리자 화면';
COMMENT ON COLUMN station.longitude IS '경도 / 선택';
COMMENT ON COLUMN station.created_at IS '생성 시각';
COMMENT ON COLUMN station.updated_at IS '수정 시각';

CREATE TABLE route (
  route_id                   NUMBER NOT NULL,
  route_name                 VARCHAR2(50) NOT NULL,
  origin_station_id          VARCHAR2(10) NOT NULL,
  dest_station_id            VARCHAR2(10) NOT NULL,
  created_at                 TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
  updated_at                 TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
  CONSTRAINT pk_route PRIMARY KEY (route_id)
);
COMMENT ON TABLE route IS '노선 - 노선(예: 경부선)과 기점·종점역.';
COMMENT ON COLUMN route.route_id IS '노선 ID';
COMMENT ON COLUMN route.route_name IS '노선명 (예: 경부선)';
COMMENT ON COLUMN route.origin_station_id IS '기점역';
COMMENT ON COLUMN route.dest_station_id IS '종점역';
COMMENT ON COLUMN route.created_at IS '생성 시각';
COMMENT ON COLUMN route.updated_at IS '수정 시각';

CREATE TABLE route_station (
  route_id                   NUMBER NOT NULL,
  station_id                 VARCHAR2(10) NOT NULL,
  station_order              NUMBER(3) NOT NULL,
  distance_from_origin_km    NUMBER(7,1) NOT NULL,
  created_at                 TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
  updated_at                 TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
  CONSTRAINT pk_route_station PRIMARY KEY (route_id, station_id)
);
COMMENT ON TABLE route_station IS '노선별 역 순서 - 노선 안에서 각 역의 순번과 누적 거리. 구간 재고와 운임 계산의 기준.';
COMMENT ON COLUMN route_station.route_id IS '노선';
COMMENT ON COLUMN route_station.station_id IS '역';
COMMENT ON COLUMN route_station.station_order IS '노선 내 순번 (1부터) / 구간 재고의 핵심. 인접 순번 사이가 1개 segment';
COMMENT ON COLUMN route_station.distance_from_origin_km IS '기점부터 누적 거리 / 운임 계산, 구간 거리 = 두 역 누적거리 차';
COMMENT ON COLUMN route_station.created_at IS '생성 시각';
COMMENT ON COLUMN route_station.updated_at IS '수정 시각';

CREATE TABLE car_type (
  car_type_code              VARCHAR2(10) NOT NULL,
  car_type_name              VARCHAR2(50),
  seat_count                 NUMBER(3) NOT NULL,
  seat_grade                 VARCHAR2(10) NOT NULL,
  seat_columns               VARCHAR2(10),
  created_at                 TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
  updated_at                 TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
  CONSTRAINT pk_car_type PRIMARY KEY (car_type_code),
  CONSTRAINT ck_car_type_seat_grade CHECK (seat_grade IN ('GENERAL', 'FIRST'))
);
COMMENT ON TABLE car_type IS '차량 유형 - 차량 유형 코드와 좌석 수. seat 자동 생성의 기준.';
COMMENT ON COLUMN car_type.car_type_code IS '차량 유형 코드 / 실제 코드값으로 세팅';
COMMENT ON COLUMN car_type.car_type_name IS '차량 유형명';
COMMENT ON COLUMN car_type.seat_count IS '좌석 수 / seat 자동 생성 기준';
COMMENT ON COLUMN car_type.seat_grade IS 'GENERAL / FIRST / 등급별 운임·재고 분리';
COMMENT ON COLUMN car_type.seat_columns IS '좌석 열 배치 (예: ABCD) / 좌석 번호(5A) 생성 규칙';
COMMENT ON COLUMN car_type.created_at IS '생성 시각';
COMMENT ON COLUMN car_type.updated_at IS '수정 시각';

CREATE TABLE train (
  train_id                   NUMBER NOT NULL,
  train_no                   VARCHAR2(10) NOT NULL,
  train_kind                 VARCHAR2(20) NOT NULL,
  route_id                   NUMBER NOT NULL,
  direction                  VARCHAR2(4) NOT NULL,
  created_at                 TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
  updated_at                 TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
  CONSTRAINT pk_train PRIMARY KEY (train_id),
  CONSTRAINT ck_train_direction CHECK (direction IN ('DOWN', 'UP'))
);
COMMENT ON TABLE train IS '열차 (정의) - 열차 번호·종류·노선. 날짜와 무관한 열차 정의.';
COMMENT ON COLUMN train.train_id IS '열차 ID';
COMMENT ON COLUMN train.train_no IS '열차 번호 (101, 103…)';
COMMENT ON COLUMN train.train_kind IS 'KTX / 새마을 등 / 운임 단가 구분';
COMMENT ON COLUMN train.route_id IS '운행 노선';
COMMENT ON COLUMN train.direction IS 'DOWN / UP / 상·하행 구분';
COMMENT ON COLUMN train.created_at IS '생성 시각';
COMMENT ON COLUMN train.updated_at IS '수정 시각';

CREATE TABLE train_car (
  train_id                   NUMBER NOT NULL,
  car_no                     NUMBER(2) NOT NULL,
  car_type_code              VARCHAR2(10) NOT NULL,
  created_at                 TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
  updated_at                 TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
  CONSTRAINT pk_train_car PRIMARY KEY (train_id, car_no)
);
COMMENT ON TABLE train_car IS '열차 편성 - 열차의 호차별 차량 유형.';
COMMENT ON COLUMN train_car.train_id IS '열차';
COMMENT ON COLUMN train_car.car_no IS '호차 번호';
COMMENT ON COLUMN train_car.car_type_code IS '차량 유형 / 호차마다 좌석 수·등급이 다름';
COMMENT ON COLUMN train_car.created_at IS '생성 시각';
COMMENT ON COLUMN train_car.updated_at IS '수정 시각';

CREATE TABLE seat (
  seat_id                    NUMBER NOT NULL,
  train_id                   NUMBER NOT NULL,
  car_no                     NUMBER(2) NOT NULL,
  seat_no                    VARCHAR2(5) NOT NULL,
  seat_grade                 VARCHAR2(10) NOT NULL,
  is_window                  CHAR(1) NOT NULL,
  created_at                 TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
  updated_at                 TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
  CONSTRAINT pk_seat PRIMARY KEY (seat_id),
  CONSTRAINT uq_seat_18fi3k UNIQUE (train_id, car_no, seat_no),
  CONSTRAINT uq_seat_train_id_seat_id UNIQUE (train_id, seat_id),
  CONSTRAINT ck_seat_seat_grade CHECK (seat_grade IN ('GENERAL', 'FIRST')),
  CONSTRAINT ck_seat_is_window CHECK (is_window IN ('Y', 'N'))
);
COMMENT ON TABLE seat IS '물리 좌석 - 열차 기준의 고정 좌석 배치. 판매 상태는 seat_inventory에서 날짜별로 관리.';
COMMENT ON COLUMN seat.seat_id IS '좌석 ID';
COMMENT ON COLUMN seat.train_id IS '열차';
COMMENT ON COLUMN seat.car_no IS '호차';
COMMENT ON COLUMN seat.seat_no IS '좌석 번호 (5A) / 화면 표시';
COMMENT ON COLUMN seat.seat_grade IS 'GENERAL / FIRST / car_type에서 상속. 코드값 통일로 CHECK 제약 적용';
COMMENT ON COLUMN seat.is_window IS '창측 여부 Y/N / 좌석 선호 분포를 가상 트래픽에 반영';
COMMENT ON COLUMN seat.created_at IS '생성 시각';
COMMENT ON COLUMN seat.updated_at IS '수정 시각';

CREATE TABLE train_run (
  run_id                     NUMBER NOT NULL,
  train_id                   NUMBER NOT NULL,
  sale_event_id              NUMBER,
  run_date                   DATE NOT NULL,
  sale_open_at               TIMESTAMP NOT NULL,
  sale_close_at              TIMESTAMP,
  status                     VARCHAR2(10) NOT NULL,
  created_at                 TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
  updated_at                 TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
  CONSTRAINT pk_train_run PRIMARY KEY (run_id),
  CONSTRAINT uq_train_run_train_id_run_date UNIQUE (train_id, run_date),
  CONSTRAINT uq_train_run_run_id_train_id UNIQUE (run_id, train_id),
  CONSTRAINT ck_train_run_status CHECK (status IN ('SCHEDULED', 'ON_SALE', 'CLOSED', 'DEPARTED'))
);
COMMENT ON TABLE train_run IS '날짜별 운행 - 특정 날짜의 열차 운행. 대기열·재고·Kafka 집계의 기준 단위.';
COMMENT ON COLUMN train_run.run_id IS '운행 ID / 대기열·재고·Kafka 집계의 기준 단위';
COMMENT ON COLUMN train_run.train_id IS '열차';
COMMENT ON COLUMN train_run.sale_event_id IS '명절 예매 행사 / 오픈 일정·정책을 행사 단위로 묶음';
COMMENT ON COLUMN train_run.run_date IS '운행일 / 명절 기간';
COMMENT ON COLUMN train_run.sale_open_at IS '예매 오픈 시각 / 트래픽 폭증 시점. 부하 테스트 시나리오 기준';
COMMENT ON COLUMN train_run.sale_close_at IS '판매 마감';
COMMENT ON COLUMN train_run.status IS 'SCHEDULED / ON_SALE / CLOSED / DEPARTED / 판매 가능 여부 판단';
COMMENT ON COLUMN train_run.created_at IS '생성 시각';
COMMENT ON COLUMN train_run.updated_at IS '수정 시각';

CREATE TABLE train_stop (
  run_id                     NUMBER NOT NULL,
  station_id                 VARCHAR2(10) NOT NULL,
  stop_order                 NUMBER(3) NOT NULL,
  arrival_time               TIMESTAMP,
  departure_time             TIMESTAMP,
  created_at                 TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
  updated_at                 TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
  CONSTRAINT pk_train_stop PRIMARY KEY (run_id, station_id)
);
COMMENT ON TABLE train_stop IS '정차 시각 - 운행별 정차역과 도착·출발 시각.';
COMMENT ON COLUMN train_stop.run_id IS '운행 / 날짜별 시각 변경 대응';
COMMENT ON COLUMN train_stop.station_id IS '정차역';
COMMENT ON COLUMN train_stop.stop_order IS '정차 순서 / route_station.station_order와 매핑';
COMMENT ON COLUMN train_stop.arrival_time IS '도착 시각';
COMMENT ON COLUMN train_stop.departure_time IS '출발 시각 / 출발 직전 취소 판단 기준';
COMMENT ON COLUMN train_stop.created_at IS '생성 시각';
COMMENT ON COLUMN train_stop.updated_at IS '수정 시각';

CREATE TABLE fare (
  fare_id                    NUMBER NOT NULL,
  train_kind                 VARCHAR2(20),
  seat_grade                 VARCHAR2(10) NOT NULL,
  from_station_id            VARCHAR2(10) NOT NULL,
  to_station_id              VARCHAR2(10) NOT NULL,
  amount                     NUMBER(10) NOT NULL,
  valid_from                 DATE NOT NULL,
  valid_to                   DATE,
  created_at                 TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
  updated_at                 TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
  CONSTRAINT pk_fare PRIMARY KEY (fare_id),
  CONSTRAINT ck_fare_seat_grade CHECK (seat_grade IN ('GENERAL', 'FIRST'))
);
COMMENT ON TABLE fare IS '운임 - 열차 종류·등급·구간별 운임과 적용 기간.';
COMMENT ON COLUMN fare.train_kind IS '열차 종류';
COMMENT ON COLUMN fare.seat_grade IS 'GENERAL / FIRST / 좌석 등급 코드 통일';
COMMENT ON COLUMN fare.from_station_id IS '출발역';
COMMENT ON COLUMN fare.to_station_id IS '도착역';
COMMENT ON COLUMN fare.amount IS '운임 / 거리 × 단가로 산출';
COMMENT ON COLUMN fare.valid_from IS '적용 시작 / 운임 변경 이력 대응';
COMMENT ON COLUMN fare.valid_to IS '적용 종료';
COMMENT ON COLUMN fare.created_at IS '생성 시각';
COMMENT ON COLUMN fare.updated_at IS '수정 시각';

CREATE TABLE purchase_limit_policy (
  policy_id                  NUMBER NOT NULL,
  sale_event_id              NUMBER,
  scope                      VARCHAR2(20) NOT NULL,
  max_seats                  NUMBER(3) NOT NULL,
  valid_from                 TIMESTAMP,
  valid_to                   TIMESTAMP,
  created_at                 TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
  updated_at                 TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
  CONSTRAINT pk_purchase_limit_policy PRIMARY KEY (policy_id),
  CONSTRAINT ck_purchase_limit_policy_scope CHECK (scope IN ('PER_RESERVATION', 'PER_RUN', 'PER_HOLIDAY'))
);
COMMENT ON TABLE purchase_limit_policy IS '매수 제한 정책 - 1회·열차별·명절 전체 매수 제한을 코드 수정 없이 조정.';
COMMENT ON COLUMN purchase_limit_policy.sale_event_id IS '적용 행사 (null이면 상시) / PER_HOLIDAY 범위 정의';
COMMENT ON COLUMN purchase_limit_policy.scope IS 'PER_RESERVATION / PER_RUN / PER_HOLIDAY / 1회·열차별·명절 전체 제한을 코드 수정 없이 조정';
COMMENT ON COLUMN purchase_limit_policy.max_seats IS '최대 매수';
COMMENT ON COLUMN purchase_limit_policy.valid_from IS '적용 시작 / 설·추석별 다른 정책';
COMMENT ON COLUMN purchase_limit_policy.valid_to IS '적용 종료';
COMMENT ON COLUMN purchase_limit_policy.created_at IS '생성 시각';
COMMENT ON COLUMN purchase_limit_policy.updated_at IS '수정 시각';

CREATE TABLE member (
  member_id                  NUMBER NOT NULL,
  email                      VARCHAR2(100) NOT NULL,
  ci_hash                    VARCHAR2(64) NOT NULL,
  name                       VARCHAR2(50) NOT NULL,
  phone_enc                  VARCHAR2(200),
  phone_hash                 VARCHAR2(64),
  enc_key_id                 VARCHAR2(20),
  status                     VARCHAR2(10) NOT NULL,
  created_at                 TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
  withdrawn_at               TIMESTAMP,
  updated_at                 TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
  CONSTRAINT pk_member PRIMARY KEY (member_id),
  CONSTRAINT uq_member_email UNIQUE (email),
  CONSTRAINT ck_member_status CHECK (status IN ('ACTIVE', 'RESTRICTED', 'BANNED'))
);
COMMENT ON TABLE member IS '회원 - 회원 계정. ci_hash가 위험 점수·매수 제한의 묶음 단위. 비밀번호는 member_credential로 분리.';
COMMENT ON COLUMN member.member_id IS '회원 ID';
COMMENT ON COLUMN member.email IS '로그인 ID';
COMMENT ON COLUMN member.ci_hash IS '모의 본인인증 CI 해시 / 위험 점수·매수 제한의 묶음 단위. 다계정이어도 같은 값';
COMMENT ON COLUMN member.name IS '이름 / 회원가입·예매자 확인';
COMMENT ON COLUMN member.phone_enc IS '휴대폰 번호 암호문 (AES-256-GCM) / 알림 발송에 원문이 필요해 해시 대신 암호화';
COMMENT ON COLUMN member.phone_hash IS '휴대폰 번호 HMAC / 암호문끼리는 비교 불가 → 중복 가입 탐지';
COMMENT ON COLUMN member.enc_key_id IS 'phone_enc 암호화 키 버전 / 키 교체 시 어느 키로 복호화할지 판별';
COMMENT ON COLUMN member.status IS 'ACTIVE / RESTRICTED / BANNED / 관리자 조치 반영';
COMMENT ON COLUMN member.created_at IS '가입 시각 / 신규 계정 판별 (기본 신뢰도 낮음)';
COMMENT ON COLUMN member.withdrawn_at IS '탈퇴 시각 / 소프트 삭제. 위험 이력은 보존 기간 후 파기';
COMMENT ON COLUMN member.updated_at IS '수정 시각';

CREATE TABLE payment_method (
  method_id                  NUMBER NOT NULL,
  member_id                  NUMBER NOT NULL,
  method_hash                VARCHAR2(64),
  method_type                VARCHAR2(10) NOT NULL,
  card_last4                 CHAR(4),
  created_at                 TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
  updated_at                 TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
  CONSTRAINT pk_payment_method PRIMARY KEY (method_id),
  CONSTRAINT ck_payment_method_method_type CHECK (method_type IN ('CARD', 'ACCOUNT', 'PAY'))
);
COMMENT ON TABLE payment_method IS '결제 수단 - 회원의 결제 수단. method_hash로 여러 계정의 같은 카드를 연결.';
COMMENT ON COLUMN payment_method.method_hash IS '카드 번호 해시 / 묶음 단위. 여러 계정이 같은 카드를 쓰면 연결';
COMMENT ON COLUMN payment_method.method_type IS 'CARD / ACCOUNT / PAY';
COMMENT ON COLUMN payment_method.card_last4 IS '끝 4자리 / 화면 표시용';
COMMENT ON COLUMN payment_method.created_at IS '생성 시각';
COMMENT ON COLUMN payment_method.updated_at IS '수정 시각';

CREATE TABLE member_device (
  device_hash                VARCHAR2(64) NOT NULL,
  member_id                  NUMBER NOT NULL,
  first_seen_at              TIMESTAMP,
  last_seen_at               TIMESTAMP,
  created_at                 TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
  updated_at                 TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
  CONSTRAINT pk_member_device PRIMARY KEY (device_hash, member_id)
);
COMMENT ON TABLE member_device IS '기기 - 기기 지문과 회원의 N:M 연결. 한 기기 다계정 탐지.';
COMMENT ON COLUMN member_device.device_hash IS '기기 지문 해시 / 묶음 단위';
COMMENT ON COLUMN member_device.member_id IS '한 기기 다계정 탐지 (N:M)';
COMMENT ON COLUMN member_device.first_seen_at IS '최초 사용';
COMMENT ON COLUMN member_device.last_seen_at IS '최근 사용';
COMMENT ON COLUMN member_device.created_at IS '생성 시각';
COMMENT ON COLUMN member_device.updated_at IS '수정 시각';

CREATE TABLE seat_inventory (
  run_id                     NUMBER NOT NULL,
  train_id                   NUMBER NOT NULL,
  seat_id                    NUMBER NOT NULL,
  segment_no                 NUMBER(3) NOT NULL,
  reservation_id             NUMBER NOT NULL,
  status                     VARCHAR2(10) NOT NULL,
  hold_expires_at            TIMESTAMP,
  created_at                 TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
  updated_at                 TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
  CONSTRAINT pk_seat_inventory PRIMARY KEY (run_id, seat_id, segment_no),
  CONSTRAINT ck_seat_inventory_r1 CHECK ((status = 'HOLD' AND hold_expires_at IS NOT NULL) OR (status = 'SOLD' AND hold_expires_at IS NULL)),
  CONSTRAINT ck_seat_inventory_status CHECK (status IN ('HOLD', 'SOLD'))
);
COMMENT ON TABLE seat_inventory IS '좌석 구간 재고 ★ - 운행·좌석·구간 단위 점유. PK와 열차 일치 복합 FK로 중복 예약과 다른 열차 좌석 판매를 DB가 막고, HOLD는 hold_expires_at이 지나면 다음 사람이 이어받는다.';
COMMENT ON COLUMN seat_inventory.run_id IS '운행';
COMMENT ON COLUMN seat_inventory.train_id IS '좌석이 속한 열차 (= train_run.train_id) / 복합 FK 두 개로 다른 열차 좌석 판매를 DB가 차단';
COMMENT ON COLUMN seat_inventory.seat_id IS '좌석';
COMMENT ON COLUMN seat_inventory.segment_no IS '구간 번호 (역 순번 i → i+1 = i) / 구간 단위 점유';
COMMENT ON COLUMN seat_inventory.reservation_id IS '점유 예약 / 반환 시 이 예약 행만 삭제';
COMMENT ON COLUMN seat_inventory.status IS 'HOLD / SOLD / 선점과 확정 구분';
COMMENT ON COLUMN seat_inventory.hold_expires_at IS 'HOLD 만료 시각 (SOLD면 null) / Redis TTL이 끝난 뒤 남은 HOLD 행을 다른 사람이 이어받는 기준';
COMMENT ON COLUMN seat_inventory.created_at IS '생성 시각';
COMMENT ON COLUMN seat_inventory.updated_at IS '수정 시각';
CREATE INDEX ix_seatinv_hold ON seat_inventory (CASE WHEN status = 'HOLD' THEN hold_expires_at END);

CREATE TABLE reservation (
  reservation_id             NUMBER NOT NULL,
  member_id                  NUMBER NOT NULL,
  ci_hash                    VARCHAR2(64) NOT NULL,
  run_id                     NUMBER NOT NULL,
  from_station_id            VARCHAR2(10) NOT NULL,
  to_station_id              VARCHAR2(10) NOT NULL,
  seat_count                 NUMBER(2) NOT NULL,
  total_amount               NUMBER(10) NOT NULL,
  status                     VARCHAR2(16) NOT NULL,
  channel                    VARCHAR2(10) NOT NULL,
  source                     VARCHAR2(10) NOT NULL,
  held_at                    TIMESTAMP NOT NULL,
  pay_deadline_at            TIMESTAMP NOT NULL,
  confirmed_at               TIMESTAMP,
  canceled_at                TIMESTAMP,
  idempotency_key            VARCHAR2(64) NOT NULL,
  version                    NUMBER NOT NULL,
  created_at                 TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
  updated_at                 TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
  CONSTRAINT pk_reservation PRIMARY KEY (reservation_id),
  CONSTRAINT uq_reservation_1jld6p UNIQUE (member_id, idempotency_key),
  CONSTRAINT ck_reservation_status CHECK (status IN ('HOLD', 'PAYMENT_PENDING', 'CONFIRMED', 'CANCELED', 'EXPIRED')),
  CONSTRAINT ck_reservation_channel CHECK (channel IN ('WEB', 'APP')),
  CONSTRAINT ck_reservation_source CHECK (source IN ('NORMAL', 'WAITLIST'))
);
COMMENT ON TABLE reservation IS '예약 - 예약 상태 머신의 중심. reservation_id가 Kafka 파티션 키.';
COMMENT ON COLUMN reservation.reservation_id IS '예약 ID / Kafka 파티션 키 → 상태 변경 순서 보장';
COMMENT ON COLUMN reservation.member_id IS '예약자';
COMMENT ON COLUMN reservation.ci_hash IS '예약 시점 CI / 매수 제한 집계를 조인 없이 빠르게';
COMMENT ON COLUMN reservation.run_id IS '운행';
COMMENT ON COLUMN reservation.from_station_id IS '승차역';
COMMENT ON COLUMN reservation.to_station_id IS '하차역';
COMMENT ON COLUMN reservation.seat_count IS '예약 매수 / 1회 구매 매수 위험 신호';
COMMENT ON COLUMN reservation.total_amount IS '예약 시점 금액 / 운임 변경과 무관하게 보존';
COMMENT ON COLUMN reservation.status IS 'HOLD / PAYMENT_PENDING / CONFIRMED / CANCELED / EXPIRED / 상태 머신';
COMMENT ON COLUMN reservation.channel IS 'WEB / APP / 채널별 트래픽 분석';
COMMENT ON COLUMN reservation.source IS 'NORMAL / WAITLIST / 취소표 재배정 여부';
COMMENT ON COLUMN reservation.held_at IS '좌석 선점 시각';
COMMENT ON COLUMN reservation.pay_deadline_at IS '결제 기한 / 초과 시 자동 반환';
COMMENT ON COLUMN reservation.confirmed_at IS '확정 시각 / 구매→취소 시간 계산 시작점';
COMMENT ON COLUMN reservation.canceled_at IS '취소 시각';
COMMENT ON COLUMN reservation.idempotency_key IS '클라이언트 요청 키 / 따닥 클릭·재시도 시 중복 예약 방지. UNIQUE 범위는 회원 단위';
COMMENT ON COLUMN reservation.version IS '낙관적 락 버전 / 락 방식 성능 비교 실험용';
COMMENT ON COLUMN reservation.created_at IS '생성 시각';
COMMENT ON COLUMN reservation.updated_at IS '수정 시각';
CREATE INDEX ix_resv_deadline ON reservation (CASE WHEN status IN ('HOLD', 'PAYMENT_PENDING') THEN pay_deadline_at END);
CREATE INDEX ix_resv_ci_run ON reservation (ci_hash, run_id);

CREATE TABLE reservation_seat (
  reservation_id             NUMBER NOT NULL,
  seat_id                    NUMBER NOT NULL,
  ticket_no                  VARCHAR2(20) NOT NULL,
  passenger_type             VARCHAR2(10) NOT NULL,
  amount                     NUMBER(10) NOT NULL,
  created_at                 TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
  updated_at                 TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
  CONSTRAINT pk_reservation_seat PRIMARY KEY (reservation_id, seat_id),
  CONSTRAINT uq_reservation_seat_ticket_no UNIQUE (ticket_no),
  CONSTRAINT ck_reservation_seat_1i28wm CHECK (passenger_type IN ('ADULT', 'CHILD', 'SENIOR'))
);
COMMENT ON TABLE reservation_seat IS '예약 좌석 - 한 예약에 포함된 좌석과 좌석별 금액.';
COMMENT ON COLUMN reservation_seat.seat_id IS '한 예약에 여러 좌석';
COMMENT ON COLUMN reservation_seat.ticket_no IS '승차권 번호 / 예매 내역·반환·신고 대상 식별';
COMMENT ON COLUMN reservation_seat.passenger_type IS 'ADULT / CHILD / SENIOR / 운임 할인 확장';
COMMENT ON COLUMN reservation_seat.amount IS '좌석별 금액 / 부분 취소 대응';
COMMENT ON COLUMN reservation_seat.created_at IS '생성 시각';
COMMENT ON COLUMN reservation_seat.updated_at IS '수정 시각';

CREATE TABLE reservation_history (
  history_id                 NUMBER NOT NULL,
  reservation_id             NUMBER NOT NULL,
  from_status                VARCHAR2(16),
  to_status                  VARCHAR2(16) NOT NULL,
  event_id                   VARCHAR2(36),
  actor_type                 VARCHAR2(10) NOT NULL,
  changed_at                 TIMESTAMP NOT NULL,
  created_at                 TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
  CONSTRAINT pk_reservation_history PRIMARY KEY (history_id),
  CONSTRAINT ck_reservation_history_r1 CHECK (from_status IN ('HOLD', 'PAYMENT_PENDING', 'CONFIRMED', 'CANCELED', 'EXPIRED')),
  CONSTRAINT ck_reservation_history_o6xh4i CHECK (to_status IN ('HOLD', 'PAYMENT_PENDING', 'CONFIRMED', 'CANCELED', 'EXPIRED')),
  CONSTRAINT ck_reservation_history_1ip6ha CHECK (actor_type IN ('USER', 'SYSTEM', 'ADMIN'))
);
COMMENT ON TABLE reservation_history IS '예약 상태 이력 - 상태 전이 기록. 순서 보장과 잘못된 전이를 테스트로 증명하는 근거.';
COMMENT ON COLUMN reservation_history.from_status IS '이전 상태 / 첫 기록이면 null. 허용값은 비고의 CHECK (v4 nn-auto가 NOT NULL로 바꾸지 않도록 설명은 그대로 둠)';
COMMENT ON COLUMN reservation_history.to_status IS 'HOLD / PAYMENT_PENDING / CONFIRMED / CANCELED / EXPIRED / 변경 상태. 잘못된 전이(CANCELED→CONFIRMED) 탐지';
COMMENT ON COLUMN reservation_history.event_id IS '원인 Kafka 이벤트 / 어떤 이벤트가 바꿨는지 추적';
COMMENT ON COLUMN reservation_history.actor_type IS 'USER / SYSTEM / ADMIN / 누가 상태를 바꿨는지';
COMMENT ON COLUMN reservation_history.changed_at IS '변경 시각 / 순서 보장 검증 근거';
COMMENT ON COLUMN reservation_history.created_at IS '생성 시각';

CREATE TABLE payment (
  payment_id                 NUMBER NOT NULL,
  reservation_id             NUMBER NOT NULL,
  method_id                  NUMBER NOT NULL,
  amount                     NUMBER(10) NOT NULL,
  status                     VARCHAR2(10) NOT NULL,
  pg_tx_id                   VARCHAR2(64),
  fail_reason                VARCHAR2(100),
  idempotency_key            VARCHAR2(64) NOT NULL,
  requested_at               TIMESTAMP NOT NULL,
  approved_at                TIMESTAMP,
  created_at                 TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
  updated_at                 TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
  CONSTRAINT pk_payment PRIMARY KEY (payment_id),
  CONSTRAINT uq_payment_phs12n UNIQUE (reservation_id, idempotency_key),
  CONSTRAINT ck_payment_status CHECK (status IN ('REQUESTED', 'APPROVED', 'FAILED', 'REFUNDED'))
);
COMMENT ON TABLE payment IS '결제 - PG 결제 요청과 결과. 실패 시 Saga 보상 트리거.';
COMMENT ON COLUMN payment.method_id IS '결제 수단 / 결제 수단 단위 위험 점수';
COMMENT ON COLUMN payment.amount IS '결제 금액';
COMMENT ON COLUMN payment.status IS 'REQUESTED / APPROVED / FAILED / REFUNDED / Saga 보상 트리거';
COMMENT ON COLUMN payment.pg_tx_id IS 'PG 거래 ID / PG 대사·환불';
COMMENT ON COLUMN payment.fail_reason IS '실패 사유 / 트러블슈팅';
COMMENT ON COLUMN payment.idempotency_key IS '결제 요청 키 / 같은 요청 재시도 방지. UNIQUE 범위는 예약 단위';
COMMENT ON COLUMN payment.requested_at IS '요청 시각 / 결제 소요 시간 측정';
COMMENT ON COLUMN payment.approved_at IS '승인 시각';
COMMENT ON COLUMN payment.created_at IS '생성 시각';
COMMENT ON COLUMN payment.updated_at IS '수정 시각';
CREATE UNIQUE INDEX ux_payment_approved ON payment (CASE WHEN status = 'APPROVED' THEN reservation_id END);

CREATE TABLE cancellation (
  cancel_id                  NUMBER NOT NULL,
  reservation_id             NUMBER NOT NULL,
  cancel_type                VARCHAR2(10) NOT NULL,
  canceled_at                TIMESTAMP NOT NULL,
  minutes_after_purchase     NUMBER,
  minutes_before_departure   NUMBER,
  refund_amount              NUMBER(10) NOT NULL,
  cancel_fee                 NUMBER(10) NOT NULL,
  fee_policy_id              NUMBER,
  refund_pg_tx_id            VARCHAR2(64),
  refund_status              VARCHAR2(10),
  resold_yn                  CHAR(1) NOT NULL,
  created_at                 TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
  updated_at                 TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
  CONSTRAINT pk_cancellation PRIMARY KEY (cancel_id),
  CONSTRAINT ck_cancellation_cancel_type CHECK (cancel_type IN ('USER', 'EXPIRED', 'PAY_FAILED', 'ADMIN')),
  CONSTRAINT ck_cancellation_refund_status CHECK (refund_status IN ('REQUESTED', 'DONE', 'FAILED')),
  CONSTRAINT ck_cancellation_resold_yn CHECK (resold_yn IN ('Y', 'N'))
);
COMMENT ON TABLE cancellation IS '취소·환불 - 취소 유형과 시간 지표. 위험 신호와 재판매율 성과 지표의 원천.';
COMMENT ON COLUMN cancellation.cancel_type IS 'USER / EXPIRED / PAY_FAILED / ADMIN / 사용자 취소만 위험 신호로 집계';
COMMENT ON COLUMN cancellation.canceled_at IS '취소 시각';
COMMENT ON COLUMN cancellation.minutes_after_purchase IS '확정 후 취소까지 분 / 구매 후 취소 시간 위험 신호';
COMMENT ON COLUMN cancellation.minutes_before_departure IS '출발 전 남은 분 / 노쇼성 직전 취소 탐지, 기획 배경 통계와 연결';
COMMENT ON COLUMN cancellation.refund_amount IS '환불액';
COMMENT ON COLUMN cancellation.cancel_fee IS '취소 수수료 / 노쇼 억제 수단';
COMMENT ON COLUMN cancellation.fee_policy_id IS '적용 수수료 정책';
COMMENT ON COLUMN cancellation.refund_pg_tx_id IS 'PG 환불 거래 ID / 환불 대사';
COMMENT ON COLUMN cancellation.refund_status IS 'REQUESTED / DONE / FAILED / 환불 실패 재시도';
COMMENT ON COLUMN cancellation.resold_yn IS '재판매 여부 / 재판매율 성과 지표';
COMMENT ON COLUMN cancellation.created_at IS '생성 시각';
COMMENT ON COLUMN cancellation.updated_at IS '수정 시각';

CREATE TABLE outbox_event (
  event_id                   VARCHAR2(36) NOT NULL,
  aggregate_type             VARCHAR2(20) NOT NULL,
  aggregate_id               VARCHAR2(36) NOT NULL,
  partition_key              VARCHAR2(64) NOT NULL,
  event_type                 VARCHAR2(30) NOT NULL,
  payload                    CLOB NOT NULL,
  status                     VARCHAR2(10) NOT NULL,
  retry_count                NUMBER(2) NOT NULL,
  created_at                 TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
  published_at               TIMESTAMP,
  updated_at                 TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
  CONSTRAINT pk_outbox_event PRIMARY KEY (event_id),
  CONSTRAINT ck_outbox_event_aggregate_type CHECK (aggregate_type IN ('RESERVATION', 'PAYMENT', 'WAITLIST')),
  CONSTRAINT ck_outbox_event_status CHECK (status IN ('PENDING', 'PUBLISHED', 'FAILED'))
);
COMMENT ON TABLE outbox_event IS 'Outbox 이벤트 - 비즈니스 변경과 같은 트랜잭션에서 INSERT → 이벤트 유실 0건.';
COMMENT ON COLUMN outbox_event.event_id IS 'UUID / 소비자 중복 판별 키';
COMMENT ON COLUMN outbox_event.aggregate_type IS 'RESERVATION / PAYMENT / WAITLIST / 토픽 라우팅';
COMMENT ON COLUMN outbox_event.aggregate_id IS 'reservation_id, case_id 등 / 숫자·UUID 키 모두 수용';
COMMENT ON COLUMN outbox_event.partition_key IS 'Kafka 메시지 키 / 결제·취소 이벤트도 reservation_id를 키로 써야 같은 예약의 이벤트 순서 보장';
COMMENT ON COLUMN outbox_event.event_type IS 'SEAT_HELD, PAYMENT_APPROVED …';
COMMENT ON COLUMN outbox_event.payload IS '이벤트 본문 (JSON) / 스키마 변경에 유연';
COMMENT ON COLUMN outbox_event.status IS 'PENDING / PUBLISHED / FAILED / 릴레이가 PENDING만 발행';
COMMENT ON COLUMN outbox_event.retry_count IS '재시도 횟수 / 무한 재시도 방지';
COMMENT ON COLUMN outbox_event.created_at IS '생성 시각';
COMMENT ON COLUMN outbox_event.published_at IS '발행 시각 / 발행 지연 모니터링';
COMMENT ON COLUMN outbox_event.updated_at IS '수정 시각';
CREATE INDEX ix_outbox_pending ON outbox_event (CASE WHEN status = 'PENDING' THEN created_at END);

CREATE TABLE processed_event (
  consumer_group             VARCHAR2(50) NOT NULL,
  event_id                   VARCHAR2(36) NOT NULL,
  processed_at               TIMESTAMP NOT NULL,
  created_at                 TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
  CONSTRAINT pk_processed_event PRIMARY KEY (consumer_group, event_id)
);
COMMENT ON TABLE processed_event IS '처리 완료 (Inbox) - Kafka at-least-once 대응. 이미 처리한 이벤트는 skip → 멱등 소비.';
COMMENT ON COLUMN processed_event.consumer_group IS '소비자 그룹 / 그룹마다 독립 처리';
COMMENT ON COLUMN processed_event.event_id IS '이벤트 ID / 이미 있으면 skip → 멱등 소비';
COMMENT ON COLUMN processed_event.processed_at IS '처리 시각 / 보관 기간 후 삭제';
COMMENT ON COLUMN processed_event.created_at IS '생성 시각';

CREATE TABLE saga_instance (
  saga_id                    VARCHAR2(36) NOT NULL,
  reservation_id             NUMBER NOT NULL,
  current_step               VARCHAR2(20) NOT NULL,
  status                     VARCHAR2(12) NOT NULL,
  timeout_at                 TIMESTAMP,
  updated_at                 TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
  created_at                 TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
  CONSTRAINT pk_saga_instance PRIMARY KEY (saga_id),
  CONSTRAINT ck_saga_instance_current_step CHECK (current_step IN ('SEAT_HELD', 'PAYING', 'CONFIRMED', 'COMPENSATING')),
  CONSTRAINT ck_saga_instance_status CHECK (status IN ('RUNNING', 'DONE', 'COMPENSATED'))
);
COMMENT ON TABLE saga_instance IS 'Saga 진행 상태 - 예약→결제→확정 흐름의 진행 단계. 중단 지점에서 재개하거나 보상.';
COMMENT ON COLUMN saga_instance.current_step IS 'SEAT_HELD / PAYING / CONFIRMED / COMPENSATING / 중단 지점에서 재개·보상';
COMMENT ON COLUMN saga_instance.status IS 'RUNNING / DONE / COMPENSATED / 좌석 복구율 100% 검증';
COMMENT ON COLUMN saga_instance.timeout_at IS '다음 단계 제한 시각 / 지나면 보상 실행';
COMMENT ON COLUMN saga_instance.updated_at IS '갱신 시각 / 멈춘 Saga 탐지';
COMMENT ON COLUMN saga_instance.created_at IS '생성 시각';

CREATE TABLE waitlist (
  waitlist_id                NUMBER NOT NULL,
  member_id                  NUMBER NOT NULL,
  run_id                     NUMBER NOT NULL,
  from_station_id            VARCHAR2(10) NOT NULL,
  to_station_id              VARCHAR2(10) NOT NULL,
  seat_grade                 VARCHAR2(10) NOT NULL,
  seat_count                 NUMBER(2) NOT NULL,
  requested_at               TIMESTAMP NOT NULL,
  offered_at                 TIMESTAMP,
  offer_deadline_at          TIMESTAMP,
  offered_reservation_id     NUMBER,
  status                     VARCHAR2(10) NOT NULL,
  created_at                 TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
  updated_at                 TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
  CONSTRAINT pk_waitlist PRIMARY KEY (waitlist_id),
  CONSTRAINT ck_waitlist_seat_grade CHECK (seat_grade IN ('GENERAL', 'FIRST')),
  CONSTRAINT ck_waitlist_status CHECK (status IN ('WAITING', 'OFFERED', 'ACCEPTED', 'EXPIRED', 'CANCELED'))
);
COMMENT ON TABLE waitlist IS '취소표 대기 - 취소 발생 시 신청 순서대로 배정 → 알림 → 제한 시간 내 결제.';
COMMENT ON COLUMN waitlist.from_station_id IS '희망 승차역 / 구간 일치 취소표만 배정';
COMMENT ON COLUMN waitlist.to_station_id IS '희망 하차역';
COMMENT ON COLUMN waitlist.seat_grade IS 'GENERAL / FIRST / 희망 등급. 좌석 등급 코드 통일';
COMMENT ON COLUMN waitlist.seat_count IS '희망 매수';
COMMENT ON COLUMN waitlist.requested_at IS '신청 시각 / 대기 순서 기준';
COMMENT ON COLUMN waitlist.offered_at IS '배정 제안 시각';
COMMENT ON COLUMN waitlist.offer_deadline_at IS '결제 기한 / 초과 시 다음 대기자';
COMMENT ON COLUMN waitlist.offered_reservation_id IS '제안된 예약';
COMMENT ON COLUMN waitlist.status IS 'WAITING / OFFERED / ACCEPTED / EXPIRED / CANCELED';
COMMENT ON COLUMN waitlist.created_at IS '생성 시각';
COMMENT ON COLUMN waitlist.updated_at IS '수정 시각';
CREATE INDEX ix_waitlist_next ON waitlist (run_id, status, requested_at);

CREATE TABLE notification (
  notification_id            NUMBER NOT NULL,
  member_id                  NUMBER NOT NULL,
  type                       VARCHAR2(20) NOT NULL,
  ref_type                   VARCHAR2(20) NOT NULL,
  ref_id                     NUMBER,
  channel                    VARCHAR2(10) NOT NULL,
  sent_at                    TIMESTAMP,
  read_at                    TIMESTAMP,
  created_at                 TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
  updated_at                 TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
  CONSTRAINT pk_notification PRIMARY KEY (notification_id),
  CONSTRAINT ck_notification_type CHECK (type IN ('WAITLIST_OFFER', 'PAY_REMINDER', 'EXPIRED')),
  CONSTRAINT ck_notification_ref_type CHECK (ref_type IN ('RESERVATION', 'WAITLIST', 'CASE')),
  CONSTRAINT ck_notification_channel CHECK (channel IN ('PUSH', 'EMAIL', 'IN_APP'))
);
COMMENT ON TABLE notification IS '알림 - 취소표 배정·결제 독촉·만료 알림.';
COMMENT ON COLUMN notification.type IS 'WAITLIST_OFFER / PAY_REMINDER / EXPIRED';
COMMENT ON COLUMN notification.ref_type IS 'RESERVATION / WAITLIST / CASE / ref_id가 어느 테이블을 가리키는지';
COMMENT ON COLUMN notification.ref_id IS '관련 예약·대기 ID';
COMMENT ON COLUMN notification.channel IS 'PUSH / EMAIL / IN_APP / 채널 추가 확장';
COMMENT ON COLUMN notification.sent_at IS '발송 시각 / 알림→결제 전환 분석';
COMMENT ON COLUMN notification.read_at IS '확인 시각';
COMMENT ON COLUMN notification.created_at IS '생성 시각';
COMMENT ON COLUMN notification.updated_at IS '수정 시각';

CREATE TABLE risk_score (
  subject_type               VARCHAR2(10) NOT NULL,
  subject_hash               VARCHAR2(64) NOT NULL,
  total_purchase_seats       NUMBER,
  max_single_purchase        NUMBER,
  cancel_ratio               NUMBER(4,3),
  avg_minutes_to_cancel      NUMBER,
  last_minute_cancel_cnt     NUMBER,
  linked_account_cnt         NUMBER,
  avg_request_interval_ms    NUMBER,
  account_age_days           NUMBER,
  rule_score                 NUMBER(5,2),
  iforest_score              NUMBER(5,2),
  final_score                NUMBER(5,2) NOT NULL,
  reasons                    CLOB,
  model_version              VARCHAR2(20),
  calculated_at              TIMESTAMP NOT NULL,
  review_status              VARCHAR2(10) NOT NULL,
  created_at                 TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
  updated_at                 TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
  CONSTRAINT pk_risk_score PRIMARY KEY (subject_type, subject_hash),
  CONSTRAINT ck_risk_score_subject_type CHECK (subject_type IN ('CI', 'PAYMENT', 'DEVICE')),
  CONSTRAINT ck_risk_score_review_status CHECK (review_status IN ('NONE', 'PENDING', 'CONFIRMED', 'CLEARED'))
);
COMMENT ON TABLE risk_score IS '위험 점수 (현재값) - 계정이 아닌 CI·결제수단·기기 단위 위험 점수. final_score만큼 대기열 순번을 뒤로.';
COMMENT ON COLUMN risk_score.subject_type IS 'CI / PAYMENT / DEVICE / 계정이 아닌 식별 단위';
COMMENT ON COLUMN risk_score.subject_hash IS '해당 해시';
COMMENT ON COLUMN risk_score.total_purchase_seats IS '누적 구매 매수 / 신호';
COMMENT ON COLUMN risk_score.max_single_purchase IS '1회 최대 매수 / 신호';
COMMENT ON COLUMN risk_score.cancel_ratio IS '취소 비율 / 신호';
COMMENT ON COLUMN risk_score.avg_minutes_to_cancel IS '평균 구매→취소 시간 / 신호';
COMMENT ON COLUMN risk_score.last_minute_cancel_cnt IS '출발 직전 취소 수 / 신호';
COMMENT ON COLUMN risk_score.linked_account_cnt IS '연결된 계정 수 / 다계정 신호';
COMMENT ON COLUMN risk_score.avg_request_interval_ms IS '평균 요청 간격 / 매크로 신호';
COMMENT ON COLUMN risk_score.account_age_days IS '가장 오래된 계정 나이 / 신규 계정 기본 신뢰도';
COMMENT ON COLUMN risk_score.rule_score IS '규칙 기반 점수';
COMMENT ON COLUMN risk_score.iforest_score IS 'Isolation Forest 점수 / 두 방식 비교';
COMMENT ON COLUMN risk_score.final_score IS '최종 점수 (0~100) / 대기열 순번 조정량';
COMMENT ON COLUMN risk_score.reasons IS '점수 근거 목록 (JSON) / 운영 원칙: 근거 기록';
COMMENT ON COLUMN risk_score.model_version IS '산정 모델 버전 / 모델 교체 시 비교';
COMMENT ON COLUMN risk_score.calculated_at IS '산정 시각 / 감쇠 기준';
COMMENT ON COLUMN risk_score.review_status IS 'NONE / PENDING / CONFIRMED / CLEARED / 높은 점수는 검토 후 조치';
COMMENT ON COLUMN risk_score.created_at IS '생성 시각';
COMMENT ON COLUMN risk_score.updated_at IS '수정 시각';

CREATE TABLE risk_score_history (
  history_id                 NUMBER NOT NULL,
  subject_type               VARCHAR2(10) NOT NULL,
  subject_hash               VARCHAR2(64) NOT NULL,
  final_score                NUMBER(5,2) NOT NULL,
  reasons                    CLOB,
  calculated_at              TIMESTAMP NOT NULL,
  created_at                 TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
  updated_at                 TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
  CONSTRAINT pk_risk_score_history PRIMARY KEY (history_id),
  CONSTRAINT ck_risk_score_history_1bhekl CHECK (subject_type IN ('CI', 'PAYMENT', 'DEVICE'))
);
COMMENT ON TABLE risk_score_history IS '위험 점수 이력 - 산정 시점별 점수와 근거. 감쇠 동작 검증, 이의 제기 대응.';
COMMENT ON COLUMN risk_score_history.subject_type IS 'CI / PAYMENT / DEVICE / 대상 유형 코드 통일 (CHECK)';
COMMENT ON COLUMN risk_score_history.subject_hash IS '대상 해시';
COMMENT ON COLUMN risk_score_history.final_score IS '당시 점수 / 감쇠 동작 검증, 이의 제기 대응';
COMMENT ON COLUMN risk_score_history.reasons IS '당시 근거';
COMMENT ON COLUMN risk_score_history.calculated_at IS '산정 시각';
COMMENT ON COLUMN risk_score_history.created_at IS '생성 시각';
COMMENT ON COLUMN risk_score_history.updated_at IS '수정 시각';

CREATE TABLE admin_action (
  action_id                  NUMBER NOT NULL,
  admin_id                   NUMBER NOT NULL,
  subject_type               VARCHAR2(10) NOT NULL,
  subject_hash               VARCHAR2(64) NOT NULL,
  action_type                VARCHAR2(20) NOT NULL,
  memo                       VARCHAR2(500),
  acted_at                   TIMESTAMP NOT NULL,
  created_at                 TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
  updated_at                 TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
  CONSTRAINT pk_admin_action PRIMARY KEY (action_id),
  CONSTRAINT ck_admin_action_subject_type CHECK (subject_type IN ('CI', 'PAYMENT', 'DEVICE')),
  CONSTRAINT ck_admin_action_action_type CHECK (action_type IN ('CONFIRM', 'CLEAR', 'RESTRICT', 'BAN'))
);
COMMENT ON TABLE admin_action IS '관리자 조치 - 위험 사용자 검토·제재 기록. 감사 추적.';
COMMENT ON COLUMN admin_action.admin_id IS '조치자 / 감사 추적';
COMMENT ON COLUMN admin_action.subject_type IS 'CI / PAYMENT / DEVICE / 대상 유형 코드 통일 (CHECK)';
COMMENT ON COLUMN admin_action.subject_hash IS '대상 해시';
COMMENT ON COLUMN admin_action.action_type IS 'CONFIRM / CLEAR / RESTRICT / BAN';
COMMENT ON COLUMN admin_action.memo IS '사유';
COMMENT ON COLUMN admin_action.acted_at IS '조치 시각';
COMMENT ON COLUMN admin_action.created_at IS '생성 시각';
COMMENT ON COLUMN admin_action.updated_at IS '수정 시각';

CREATE TABLE synthetic_label (
  member_id                  NUMBER NOT NULL,
  user_type                  VARCHAR2(20) NOT NULL,
  group_id                   NUMBER,
  generation_params          CLOB,
  created_at                 TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
  updated_at                 TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
  CONSTRAINT pk_synthetic_label PRIMARY KEY (member_id),
  CONSTRAINT ck_synthetic_label_user_type CHECK (user_type IN ('NORMAL', 'RESELLER', 'CANCEL_ABUSER', 'MACRO'))
);
COMMENT ON TABLE synthetic_label IS '정답 라벨 - 가상 데이터의 정답. 위험 점수의 정밀도·재현율 측정용. 운영 로직에서 참조 금지.';
COMMENT ON COLUMN synthetic_label.member_id IS '회원';
COMMENT ON COLUMN synthetic_label.user_type IS 'NORMAL / RESELLER / CANCEL_ABUSER / MACRO / 위험 점수의 정밀도·재현율 측정';
COMMENT ON COLUMN synthetic_label.group_id IS '같은 어뷰저가 만든 다계정 묶음 / 묶음 탐지 성능 측정';
COMMENT ON COLUMN synthetic_label.generation_params IS '생성 시 사용한 분포 파라미터 (JSON) / 재현 가능성, 발표 시 근거';
COMMENT ON COLUMN synthetic_label.created_at IS '생성 시각';
COMMENT ON COLUMN synthetic_label.updated_at IS '수정 시각';

CREATE TABLE member_credential (
  member_id                  NUMBER NOT NULL,
  password_hash              VARCHAR2(255) NOT NULL,
  hash_algo                  VARCHAR2(20) NOT NULL,
  hash_params                VARCHAR2(40) NOT NULL,
  pepper_key_id              VARCHAR2(20),
  needs_rehash               CHAR(1) NOT NULL,
  failed_count               NUMBER(3) NOT NULL,
  locked_until               TIMESTAMP,
  password_changed_at        TIMESTAMP,
  last_login_at              TIMESTAMP,
  created_at                 TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
  updated_at                 TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
  CONSTRAINT pk_member_credential PRIMARY KEY (member_id),
  CONSTRAINT ck_member_credential_1tufte CHECK (needs_rehash IN ('Y', 'N'))
);
COMMENT ON TABLE member_credential IS '로그인 인증 정보 - Argon2id 비밀번호 해시와 잠금 상태. 회원 프로필과 분리해 해시가 일반 조회에 섞이지 않게 한다.';
COMMENT ON COLUMN member_credential.member_id IS '회원 (1:1) / 프로필과 인증 정보 분리';
COMMENT ON COLUMN member_credential.password_hash IS 'Argon2id PHC 문자열 ($argon2id$v=19$m=19456,t=2,p=1$salt$hash) / 솔트·파라미터가 문자열 안에 있어 salt 컬럼 불필요';
COMMENT ON COLUMN member_credential.hash_algo IS 'ARGON2ID / 알고리즘 교체 대비';
COMMENT ON COLUMN member_credential.hash_params IS 'm=19456,t=2,p=1 / 정책 파라미터와 다르면 재해싱 대상';
COMMENT ON COLUMN member_credential.pepper_key_id IS '페퍼 키 버전 / 페퍼는 DB 밖(환경변수·KMS)에 두고 버전만 기록';
COMMENT ON COLUMN member_credential.needs_rehash IS 'Y/N / 다음 로그인 성공 시 새 파라미터로 재해싱';
COMMENT ON COLUMN member_credential.failed_count IS '연속 로그인 실패 횟수 / 계정 잠금 기준';
COMMENT ON COLUMN member_credential.locked_until IS '잠금 해제 시각 / 무차별 대입 방지';
COMMENT ON COLUMN member_credential.password_changed_at IS '비밀번호 변경 시각 / 변경 직후 대량 구매 = 탈취 의심 신호';
COMMENT ON COLUMN member_credential.last_login_at IS '마지막 로그인 / 휴면 계정 갑작스런 활동 탐지';
COMMENT ON COLUMN member_credential.created_at IS '생성 시각';
COMMENT ON COLUMN member_credential.updated_at IS '수정 시각';

CREATE TABLE identity_verification (
  verification_id            NUMBER NOT NULL,
  member_id                  NUMBER NOT NULL,
  ci_hash                    VARCHAR2(64),
  provider                   VARCHAR2(20) NOT NULL,
  result                     VARCHAR2(10) NOT NULL,
  verified_at                TIMESTAMP,
  created_at                 TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
  updated_at                 TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
  CONSTRAINT pk_identity_verification PRIMARY KEY (verification_id),
  CONSTRAINT ck_identity_verificatio_raou0o CHECK (provider IN ('MOCK_PASS', 'MOCK_PHONE')),
  CONSTRAINT ck_identity_verificatio_14v838 CHECK (result IN ('SUCCESS', 'FAIL'))
);
COMMENT ON TABLE identity_verification IS '본인인증 이력 - 모의 본인인증 이력. 같은 CI로 여러 계정을 인증하는 다계정 신호를 잡는다.';
COMMENT ON COLUMN identity_verification.member_id IS '인증한 계정';
COMMENT ON COLUMN identity_verification.ci_hash IS '인증 결과 CI 해시 / 같은 CI로 짧은 기간 여러 계정 인증 = 다계정 신호';
COMMENT ON COLUMN identity_verification.provider IS 'MOCK_PASS / MOCK_PHONE / 모의 본인인증';
COMMENT ON COLUMN identity_verification.result IS 'SUCCESS / FAIL';
COMMENT ON COLUMN identity_verification.verified_at IS '인증 시각';
COMMENT ON COLUMN identity_verification.created_at IS '생성 시각';
COMMENT ON COLUMN identity_verification.updated_at IS '수정 시각';

CREATE TABLE auth_session (
  session_id                 VARCHAR2(36) NOT NULL,
  member_id                  NUMBER,
  actor_type                 VARCHAR2(10) NOT NULL,
  admin_id                   NUMBER,
  refresh_token_hash         VARCHAR2(64) NOT NULL,
  token_family_id            VARCHAR2(36) NOT NULL,
  device_hash                VARCHAR2(64),
  ip_hash                    VARCHAR2(64),
  user_agent                 VARCHAR2(300),
  created_at                 TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
  expires_at                 TIMESTAMP NOT NULL,
  revoked_at                 TIMESTAMP,
  revoke_reason              VARCHAR2(20),
  updated_at                 TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
  CONSTRAINT pk_auth_session PRIMARY KEY (session_id),
  CONSTRAINT ck_auth_session_r1 CHECK ((actor_type = 'MEMBER' AND member_id IS NOT NULL AND admin_id IS NULL) OR (actor_type = 'ADMIN' AND admin_id IS NOT NULL AND member_id IS NULL)),
  CONSTRAINT ck_auth_session_actor_type CHECK (actor_type IN ('MEMBER', 'ADMIN')),
  CONSTRAINT ck_auth_session_revoke_reason CHECK (revoke_reason IN ('LOGOUT', 'ROTATED', 'ADMIN', 'SUSPICIOUS'))
);
COMMENT ON TABLE auth_session IS '로그인 세션 - 로그인 세션과 리프레시 토큰. session_id가 CCTV 녹화 단위이자 행동 로그 연결 키.';
COMMENT ON COLUMN auth_session.session_id IS 'UUID / CCTV 녹화 단위. replay_session, behavior_log와 같은 키';
COMMENT ON COLUMN auth_session.actor_type IS 'MEMBER / ADMIN / 관리자 세션은 녹화 대상에서 제외';
COMMENT ON COLUMN auth_session.admin_id IS '관리자 세션일 때';
COMMENT ON COLUMN auth_session.refresh_token_hash IS '리프레시 토큰 SHA-256 / 고엔트로피 무작위 토큰이라 Argon2 불필요. 매 갱신마다 검증하므로 빠른 해시';
COMMENT ON COLUMN auth_session.token_family_id IS '토큰 계열 ID / 회전된 옛 토큰 재사용 시 계열 전체 폐기 (탈취 탐지)';
COMMENT ON COLUMN auth_session.device_hash IS '기기 지문 해시';
COMMENT ON COLUMN auth_session.ip_hash IS 'IP 해시';
COMMENT ON COLUMN auth_session.created_at IS '로그인 시각';
COMMENT ON COLUMN auth_session.expires_at IS '만료 시각';
COMMENT ON COLUMN auth_session.revoked_at IS '강제 종료 시각';
COMMENT ON COLUMN auth_session.revoke_reason IS 'LOGOUT / ROTATED / ADMIN / SUSPICIOUS / 관리자 조치로 끊긴 세션 구분';
COMMENT ON COLUMN auth_session.updated_at IS '수정 시각';

CREATE TABLE suspicious_case (
  case_id                    NUMBER NOT NULL,
  subject_type               VARCHAR2(10) NOT NULL,
  subject_hash               VARCHAR2(64) NOT NULL,
  trigger_type               VARCHAR2(20) NOT NULL,
  trigger_detail             VARCHAR2(200),
  risk_score_at_open         NUMBER(5,2),
  window_from                TIMESTAMP,
  window_to                  TIMESTAMP,
  status                     VARCHAR2(12) NOT NULL,
  assignee_id                NUMBER,
  verdict                    VARCHAR2(20),
  admin_action_id            NUMBER,
  evidence_hash              VARCHAR2(64),
  opened_at                  TIMESTAMP NOT NULL,
  closed_at                  TIMESTAMP,
  created_at                 TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
  updated_at                 TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
  CONSTRAINT pk_suspicious_case PRIMARY KEY (case_id),
  CONSTRAINT ck_suspicious_case_ieldms CHECK (subject_type IN ('CI', 'PAYMENT', 'DEVICE')),
  CONSTRAINT ck_suspicious_case_ovoexs CHECK (trigger_type IN ('RISK_THRESHOLD', 'RULE', 'MODEL', 'ADMIN')),
  CONSTRAINT ck_suspicious_case_status CHECK (status IN ('OPEN', 'REVIEWING', 'CONFIRMED', 'DISMISSED')),
  CONSTRAINT ck_suspicious_case_verdict CHECK (verdict IN ('RESELLER', 'MACRO', 'CANCEL_ABUSE', 'NORMAL'))
);
COMMENT ON TABLE suspicious_case IS '의심 케이스 - 위험 점수·규칙·관리자 지정으로 열리는 조사 건. 되돌아볼 시간 범위와 판정을 기록.';
COMMENT ON COLUMN suspicious_case.subject_type IS 'CI / PAYMENT / DEVICE / 계정이 아닌 묶음 단위';
COMMENT ON COLUMN suspicious_case.trigger_type IS 'RISK_THRESHOLD / RULE / MODEL / ADMIN / 어떻게 열렸는지';
COMMENT ON COLUMN suspicious_case.trigger_detail IS '예: 같은 CI 4계정 동시 좌석 선점 / 첫 화면에서 이유 확인';
COMMENT ON COLUMN suspicious_case.risk_score_at_open IS '생성 시점 점수';
COMMENT ON COLUMN suspicious_case.window_from IS '되돌아볼 시작 시각 / 재생 범위 기본값';
COMMENT ON COLUMN suspicious_case.window_to IS '되돌아볼 끝 시각';
COMMENT ON COLUMN suspicious_case.status IS 'OPEN / REVIEWING / CONFIRMED / DISMISSED';
COMMENT ON COLUMN suspicious_case.assignee_id IS '담당 관리자';
COMMENT ON COLUMN suspicious_case.verdict IS 'RESELLER / MACRO / CANCEL_ABUSE / NORMAL / synthetic_label과 비교해 오탐률 측정';
COMMENT ON COLUMN suspicious_case.admin_action_id IS '최종 조치';
COMMENT ON COLUMN suspicious_case.evidence_hash IS '증거 조각 해시를 이어 붙인 SHA-256 / 증거 묶음 전체 무결성. Oracle에 따로 둬서 Mongo 쪽 변조와 분리';
COMMENT ON COLUMN suspicious_case.closed_at IS '처리 소요 시간';
COMMENT ON COLUMN suspicious_case.created_at IS '생성 시각';
COMMENT ON COLUMN suspicious_case.updated_at IS '수정 시각';

CREATE TABLE case_session (
  case_id                    NUMBER NOT NULL,
  session_id                 VARCHAR2(36) NOT NULL,
  member_id                  NUMBER NOT NULL,
  link_reason                VARCHAR2(20) NOT NULL,
  sync_offset_ms             NUMBER,
  created_at                 TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
  updated_at                 TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
  CONSTRAINT pk_case_session PRIMARY KEY (case_id, session_id),
  CONSTRAINT ck_case_session_link_reason CHECK (link_reason IN ('TRIGGER', 'SAME_CI', 'SAME_DEVICE', 'SAME_PAYMENT', 'SAME_IP'))
);
COMMENT ON TABLE case_session IS '케이스-세션 연결 - 한 케이스에 묶인 여러 세션. 같은 CI·기기의 다계정 세션을 나란히 재생.';
COMMENT ON COLUMN case_session.session_id IS '한 케이스에 여러 세션';
COMMENT ON COLUMN case_session.member_id IS '세션 계정';
COMMENT ON COLUMN case_session.link_reason IS 'TRIGGER / SAME_CI / SAME_DEVICE / SAME_PAYMENT / SAME_IP / 다계정을 나란히 재생하는 근거';
COMMENT ON COLUMN case_session.sync_offset_ms IS '동시 재생 시간 보정 / 기기 시계 오차 보정';
COMMENT ON COLUMN case_session.created_at IS '생성 시각';
COMMENT ON COLUMN case_session.updated_at IS '수정 시각';

CREATE TABLE case_marker (
  marker_id                  NUMBER NOT NULL,
  case_id                    NUMBER NOT NULL,
  session_id                 VARCHAR2(36) NOT NULL,
  at_ts                      TIMESTAMP NOT NULL,
  marker_type                VARCHAR2(10) NOT NULL,
  rule_code                  VARCHAR2(30) NOT NULL,
  label                      VARCHAR2(200) NOT NULL,
  severity                   VARCHAR2(6) NOT NULL,
  created_by                 NUMBER,
  created_at                 TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
  updated_at                 TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
  CONSTRAINT pk_case_marker PRIMARY KEY (marker_id),
  CONSTRAINT ck_case_marker_marker_type CHECK (marker_type IN ('AUTO', 'MANUAL')),
  CONSTRAINT ck_case_marker_rule_code CHECK (rule_code IN ('FAST_CLICK', 'SAME_SEAT_RETRY', 'CANCEL_AFTER_PAY', 'MULTI_ACCOUNT_SYNC', 'LINEAR_MOUSE')),
  CONSTRAINT ck_case_marker_severity CHECK (severity IN ('LOW', 'MID', 'HIGH'))
);
COMMENT ON TABLE case_marker IS '타임라인 마커 - 재생 타임라인의 북마크. 시스템이 자동으로 찍고 관리자가 메모를 더한다.';
COMMENT ON COLUMN case_marker.session_id IS '표시할 세션';
COMMENT ON COLUMN case_marker.at_ts IS '타임라인 위치 / 누르면 그 시점으로 이동';
COMMENT ON COLUMN case_marker.marker_type IS 'AUTO / MANUAL / 시스템 탐지와 관리자 메모 구분';
COMMENT ON COLUMN case_marker.rule_code IS 'FAST_CLICK / SAME_SEAT_RETRY / CANCEL_AFTER_PAY / MULTI_ACCOUNT_SYNC / LINEAR_MOUSE / 어떤 규칙이 잡았는지';
COMMENT ON COLUMN case_marker.label IS '예: 0.1초 간격 좌석 클릭 28회';
COMMENT ON COLUMN case_marker.severity IS 'LOW / MID / HIGH';
COMMENT ON COLUMN case_marker.created_by IS '작성 관리자 (AUTO는 null)';
COMMENT ON COLUMN case_marker.created_at IS '생성 시각';
COMMENT ON COLUMN case_marker.updated_at IS '수정 시각';

CREATE TABLE replay_access_log (
  access_id                  NUMBER NOT NULL,
  admin_id                   NUMBER NOT NULL,
  case_id                    NUMBER NOT NULL,
  session_id                 VARCHAR2(36) NOT NULL,
  action                     VARCHAR2(10) NOT NULL,
  purpose                    VARCHAR2(200) NOT NULL,
  accessed_at                TIMESTAMP NOT NULL,
  created_at                 TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
  updated_at                 TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
  CONSTRAINT pk_replay_access_log PRIMARY KEY (access_id),
  CONSTRAINT ck_replay_access_log_action CHECK (action IN ('VIEW', 'UNMASK', 'EXPORT'))
);
COMMENT ON TABLE replay_access_log IS '녹화 열람 기록 - 누가 언제 왜 녹화를 봤는지. 녹화 열람 자체가 개인정보 처리이므로 감사 기록.';
COMMENT ON COLUMN replay_access_log.admin_id IS '열람자';
COMMENT ON COLUMN replay_access_log.case_id IS '케이스 없이 임의 열람 불가';
COMMENT ON COLUMN replay_access_log.action IS 'VIEW / UNMASK / EXPORT / 마스킹 해제는 별도 기록';
COMMENT ON COLUMN replay_access_log.purpose IS '열람 사유 (필수) / 개인정보 처리 감사';
COMMENT ON COLUMN replay_access_log.created_at IS '생성 시각';
COMMENT ON COLUMN replay_access_log.updated_at IS '수정 시각';

CREATE TABLE model_run (
  model_version              VARCHAR2(20) NOT NULL,
  algorithm                  VARCHAR2(20) NOT NULL,
  params                     CLOB,
  train_source               VARCHAR2(100),
  trained_at                 TIMESTAMP NOT NULL,
  precision_score            NUMBER(4,3),
  recall_score               NUMBER(4,3),
  f1_score                   NUMBER(4,3),
  threshold                  NUMBER(5,2),
  decay_half_life_days       NUMBER(4),
  is_active                  CHAR(1) NOT NULL,
  created_at                 TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
  updated_at                 TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
  CONSTRAINT pk_model_run PRIMARY KEY (model_version),
  CONSTRAINT ck_model_run_algorithm CHECK (algorithm IN ('RULE', 'IFOREST')),
  CONSTRAINT ck_model_run_is_active CHECK (is_active IN ('Y', 'N'))
);
COMMENT ON TABLE model_run IS '모델 학습 기록 - 규칙·Isolation Forest 모델 버전별 파라미터와 성능. 발표용 수치의 원천.';
COMMENT ON COLUMN model_run.model_version IS '예: iforest-2026.11-01 / risk_score.model_version이 참조';
COMMENT ON COLUMN model_run.algorithm IS 'RULE / IFOREST / 두 방식 비교';
COMMENT ON COLUMN model_run.params IS 'contamination, n_estimators 등 (JSON) / 재현';
COMMENT ON COLUMN model_run.train_source IS '학습 데이터 범위';
COMMENT ON COLUMN model_run.precision_score IS '정밀도 / 발표용 성능 수치';
COMMENT ON COLUMN model_run.recall_score IS '재현율';
COMMENT ON COLUMN model_run.f1_score IS 'F1';
COMMENT ON COLUMN model_run.threshold IS '케이스 자동 생성 임계값 / suspicious_case 트리거 기준';
COMMENT ON COLUMN model_run.decay_half_life_days IS '점수 반감기 (일) / 기간 경과 시 점수 감소 파라미터';
COMMENT ON COLUMN model_run.is_active IS '운영 적용 여부';
COMMENT ON COLUMN model_run.created_at IS '생성 시각';
COMMENT ON COLUMN model_run.updated_at IS '수정 시각';

CREATE TABLE admin_user (
  admin_id                   NUMBER NOT NULL,
  login_id                   VARCHAR2(50) NOT NULL,
  password_hash              VARCHAR2(255) NOT NULL,
  role                       VARCHAR2(20) NOT NULL,
  mfa_secret_enc             VARCHAR2(200),
  status                     VARCHAR2(10) NOT NULL,
  last_login_at              TIMESTAMP,
  created_at                 TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
  updated_at                 TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
  CONSTRAINT pk_admin_user PRIMARY KEY (admin_id),
  CONSTRAINT uq_admin_user_login_id UNIQUE (login_id),
  CONSTRAINT ck_admin_user_role CHECK (role IN ('VIEWER', 'REVIEWER', 'SUPERVISOR')),
  CONSTRAINT ck_admin_user_status CHECK (status IN ('ACTIVE', 'DISABLED'))
);
COMMENT ON TABLE admin_user IS '관리자 - 관리자 계정과 역할. 녹화 마스킹 해제·내보내기는 SUPERVISOR만.';
COMMENT ON COLUMN admin_user.admin_id IS '관리자 ID / admin_action, suspicious_case, case_marker, replay_access_log, evidence_snapshot이 참조';
COMMENT ON COLUMN admin_user.login_id IS '로그인 ID';
COMMENT ON COLUMN admin_user.password_hash IS 'Argon2id PHC 문자열 / 회원과 같은 정책';
COMMENT ON COLUMN admin_user.role IS 'VIEWER / REVIEWER / SUPERVISOR / 마스킹 해제·내보내기는 SUPERVISOR만';
COMMENT ON COLUMN admin_user.mfa_secret_enc IS 'TOTP 비밀키 암호문 / 녹화·개인정보 접근 계정이라 2단계 인증 자리 확보 (구현은 확장)';
COMMENT ON COLUMN admin_user.status IS 'ACTIVE / DISABLED';
COMMENT ON COLUMN admin_user.last_login_at IS '마지막 로그인';
COMMENT ON COLUMN admin_user.created_at IS '생성 시각';
COMMENT ON COLUMN admin_user.updated_at IS '수정 시각';

CREATE TABLE sale_event (
  sale_event_id              NUMBER NOT NULL,
  name                       VARCHAR2(50) NOT NULL,
  holiday_from               DATE NOT NULL,
  holiday_to                 DATE NOT NULL,
  sale_open_at               TIMESTAMP NOT NULL,
  priority_open_at           TIMESTAMP,
  status                     VARCHAR2(10) NOT NULL,
  created_at                 TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
  updated_at                 TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
  CONSTRAINT pk_sale_event PRIMARY KEY (sale_event_id),
  CONSTRAINT ck_sale_event_status CHECK (status IN ('PLANNED', 'OPEN', 'CLOSED'))
);
COMMENT ON TABLE sale_event IS '명절 예매 행사 - 설·추석 등 예매 행사. 연휴 기간과 오픈 일정을 묶어 매수 제한·수수료 정책의 범위가 된다.';
COMMENT ON COLUMN sale_event.name IS '예: 2026 추석';
COMMENT ON COLUMN sale_event.holiday_from IS '연휴 시작 / PER_HOLIDAY 매수 제한의 기간 정의';
COMMENT ON COLUMN sale_event.holiday_to IS '연휴 끝';
COMMENT ON COLUMN sale_event.sale_open_at IS '일반 예매 오픈 / 부하 테스트 시나리오 기준';
COMMENT ON COLUMN sale_event.priority_open_at IS '교통약자 사전 예매 오픈 / 확장 시 사용';
COMMENT ON COLUMN sale_event.status IS 'PLANNED / OPEN / CLOSED';
COMMENT ON COLUMN sale_event.created_at IS '생성 시각';
COMMENT ON COLUMN sale_event.updated_at IS '수정 시각';

CREATE TABLE cancel_fee_policy (
  fee_policy_id              NUMBER NOT NULL,
  sale_event_id              NUMBER,
  min_minutes_before         NUMBER,
  max_minutes_before         NUMBER,
  fee_rate                   NUMBER(4,3),
  after_departure            CHAR(1) NOT NULL,
  created_at                 TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
  updated_at                 TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
  CONSTRAINT pk_cancel_fee_policy PRIMARY KEY (fee_policy_id),
  CONSTRAINT ck_cancel_fee_policy_q3nz7a CHECK (after_departure IN ('Y', 'N'))
);
COMMENT ON TABLE cancel_fee_policy IS '취소 수수료 정책 - 출발 전 남은 시간 구간별 수수료율. 기획 배경의 노쇼 증가에 대한 정책 수단.';
COMMENT ON COLUMN cancel_fee_policy.sale_event_id IS '적용 행사 (null이면 상시) / 명절만 수수료 강화 가능';
COMMENT ON COLUMN cancel_fee_policy.min_minutes_before IS '출발 전 구간 시작(분)';
COMMENT ON COLUMN cancel_fee_policy.max_minutes_before IS '출발 전 구간 끝(분)';
COMMENT ON COLUMN cancel_fee_policy.fee_rate IS '수수료율 / 노쇼 억제';
COMMENT ON COLUMN cancel_fee_policy.after_departure IS '출발 후 반환 여부 / 출발 후 반환은 재판매 불가 구간';
COMMENT ON COLUMN cancel_fee_policy.created_at IS '생성 시각';
COMMENT ON COLUMN cancel_fee_policy.updated_at IS '수정 시각';

CREATE TABLE ext_dataset (
  dataset_id                 VARCHAR2(40) NOT NULL,
  name                       VARCHAR2(100) NOT NULL,
  source_url                 VARCHAR2(300) NOT NULL,
  license                    VARCHAR2(50) NOT NULL,
  license_checked_at         DATE,
  row_count                  NUMBER,
  checksum_sha256            VARCHAR2(64),
  ingested_at                TIMESTAMP,
  caveat                     VARCHAR2(300),
  created_at                 TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
  updated_at                 TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
  CONSTRAINT pk_ext_dataset PRIMARY KEY (dataset_id)
);
COMMENT ON TABLE ext_dataset IS '외부 데이터셋 카탈로그 - 적재한 외부 데이터셋의 출처·라이선스·건수·해시. 기획서의 "사용 전 라이선스 확인" 원칙 기록.';
COMMENT ON COLUMN ext_dataset.dataset_id IS '예: hotel_booking@v1 / 모든 ext_* 문서의 dataset_id가 참조';
COMMENT ON COLUMN ext_dataset.name IS '데이터셋 이름';
COMMENT ON COLUMN ext_dataset.source_url IS '원본 주소 / 발표 출처';
COMMENT ON COLUMN ext_dataset.license IS '확인한 라이선스 / 사용 전 라이선스 확인 기록';
COMMENT ON COLUMN ext_dataset.license_checked_at IS '확인일';
COMMENT ON COLUMN ext_dataset.row_count IS '적재 건수 / 빅데이터 규모 수치';
COMMENT ON COLUMN ext_dataset.checksum_sha256 IS '원본 파일 해시 / 같은 파일로 재현했는지 확인';
COMMENT ON COLUMN ext_dataset.ingested_at IS '적재 시각';
COMMENT ON COLUMN ext_dataset.caveat IS '도메인 차이 등 유의사항 / 호텔 데이터·검색 크롤러 봇 등 한계 명시';
COMMENT ON COLUMN ext_dataset.created_at IS '생성 시각';
COMMENT ON COLUMN ext_dataset.updated_at IS '수정 시각';

CREATE TABLE app_policy (
  policy_key                 VARCHAR2(60) NOT NULL,
  policy_value               VARCHAR2(200) NOT NULL,
  version                    NUMBER NOT NULL,
  value_type                 VARCHAR2(10) NOT NULL,
  description                VARCHAR2(300),
  updated_by                 NUMBER,
  created_at                 TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
  updated_at                 TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
  CONSTRAINT pk_app_policy PRIMARY KEY (policy_key),
  CONSTRAINT ck_app_policy_value_type CHECK (value_type IN ('NUMBER', 'STRING', 'BOOL'))
);
COMMENT ON TABLE app_policy IS '운영 설정 - 팀이 정하는 운영 값(샘플링 비율, 보관 기간, 대기열 처리량 등)을 코드 수정 없이 바꾸는 키-값 설정. 현재 값은 모두 예시.';
COMMENT ON COLUMN app_policy.policy_key IS '설정 키 (예: replay.full_record_ratio) / 점(.)으로 영역 구분';
COMMENT ON COLUMN app_policy.policy_value IS '설정 값 (문자열로 저장)';
COMMENT ON COLUMN app_policy.version IS '변경할 때마다 1 증가 / 캐시 무효화 기준 (policy:cache의 version과 다르면 다시 로딩)';
COMMENT ON COLUMN app_policy.value_type IS 'NUMBER / STRING / BOOL / 읽을 때 형 변환';
COMMENT ON COLUMN app_policy.description IS '설정 설명';
COMMENT ON COLUMN app_policy.updated_by IS '마지막 변경 관리자 / 변경 책임 추적';
COMMENT ON COLUMN app_policy.created_at IS '생성 시각';
COMMENT ON COLUMN app_policy.updated_at IS '수정 시각';

CREATE TABLE purchase_counter (
  scope                      VARCHAR2(20) NOT NULL,
  scope_ref_id               NUMBER NOT NULL,
  ci_hash                    VARCHAR2(64) NOT NULL,
  seat_count                 NUMBER(3) NOT NULL,
  created_at                 TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
  updated_at                 TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
  CONSTRAINT pk_purchase_counter PRIMARY KEY (scope, scope_ref_id, ci_hash),
  CONSTRAINT ck_purchase_counter_scope CHECK (scope IN ('PER_RUN', 'PER_HOLIDAY'))
);
COMMENT ON TABLE purchase_counter IS '매수 카운터 - CI별 보유 매수. 매수 제한의 최종 판정을 조건부 UPDATE 한 번으로 원자적으로 처리하고, Redis 카운터가 사라지면 여기서 복원한다.';
COMMENT ON COLUMN purchase_counter.scope IS 'PER_RUN / PER_HOLIDAY / 열차별·명절 전체 제한을 한 테이블에서';
COMMENT ON COLUMN purchase_counter.scope_ref_id IS 'run_id 또는 sale_event_id / scope에 따라 가리키는 대상이 달라 FK 미설정';
COMMENT ON COLUMN purchase_counter.ci_hash IS 'CI 해시 / 계정이 아닌 사람 단위 합산';
COMMENT ON COLUMN purchase_counter.seat_count IS '현재 보유 매수 / 조건부 UPDATE로 한도 초과 차단';
COMMENT ON COLUMN purchase_counter.created_at IS '생성 시각';
COMMENT ON COLUMN purchase_counter.updated_at IS '수정 시각';

CREATE TABLE app_policy_history (
  history_id                 NUMBER NOT NULL,
  policy_key                 VARCHAR2(60) NOT NULL,
  old_value                  VARCHAR2(200),
  new_value                  VARCHAR2(200) NOT NULL,
  version                    NUMBER NOT NULL,
  changed_by                 NUMBER,
  changed_at                 TIMESTAMP NOT NULL,
  created_at                 TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
  CONSTRAINT pk_app_policy_history PRIMARY KEY (history_id)
);
COMMENT ON TABLE app_policy_history IS '운영 설정 이력 - app_policy 값이 바뀔 때마다 한 행. 누가 언제 무엇을 바꿨는지와 캐시 버전을 추적한다.';
COMMENT ON COLUMN app_policy_history.policy_key IS '설정 키';
COMMENT ON COLUMN app_policy_history.old_value IS '변경 전 값 / 처음 생성이면 null';
COMMENT ON COLUMN app_policy_history.new_value IS '변경 후 값';
COMMENT ON COLUMN app_policy_history.version IS '변경 후 버전 / app_policy.version과 같은 값';
COMMENT ON COLUMN app_policy_history.changed_by IS '변경한 관리자 / 시스템 변경이면 null';
COMMENT ON COLUMN app_policy_history.changed_at IS '변경 시각';
COMMENT ON COLUMN app_policy_history.created_at IS '생성 시각';

-- 외래키와 외래키 인덱스 (Oracle은 FK에 인덱스를 자동으로 만들지 않음)
ALTER TABLE route ADD CONSTRAINT fk_route_origin_station_id FOREIGN KEY (origin_station_id) REFERENCES station (station_id);
CREATE INDEX ix_route_origin_station_id ON route (origin_station_id);
ALTER TABLE route ADD CONSTRAINT fk_route_dest_station_id FOREIGN KEY (dest_station_id) REFERENCES station (station_id);
CREATE INDEX ix_route_dest_station_id ON route (dest_station_id);
ALTER TABLE route_station ADD CONSTRAINT fk_route_station_route_id FOREIGN KEY (route_id) REFERENCES route (route_id);
ALTER TABLE route_station ADD CONSTRAINT fk_route_station_station_id FOREIGN KEY (station_id) REFERENCES station (station_id);
CREATE INDEX ix_route_station_station_id ON route_station (station_id);
ALTER TABLE train ADD CONSTRAINT fk_train_route_id FOREIGN KEY (route_id) REFERENCES route (route_id);
CREATE INDEX ix_train_route_id ON train (route_id);
ALTER TABLE train_car ADD CONSTRAINT fk_train_car_train_id FOREIGN KEY (train_id) REFERENCES train (train_id);
ALTER TABLE train_car ADD CONSTRAINT fk_train_car_car_type_code FOREIGN KEY (car_type_code) REFERENCES car_type (car_type_code);
CREATE INDEX ix_train_car_car_type_code ON train_car (car_type_code);
ALTER TABLE seat ADD CONSTRAINT fk_seat_train_id FOREIGN KEY (train_id) REFERENCES train (train_id);
ALTER TABLE train_run ADD CONSTRAINT fk_train_run_train_id FOREIGN KEY (train_id) REFERENCES train (train_id);
ALTER TABLE train_run ADD CONSTRAINT fk_train_run_sale_event_id FOREIGN KEY (sale_event_id) REFERENCES sale_event (sale_event_id);
CREATE INDEX ix_train_run_sale_event_id ON train_run (sale_event_id);
ALTER TABLE train_stop ADD CONSTRAINT fk_train_stop_run_id FOREIGN KEY (run_id) REFERENCES train_run (run_id);
ALTER TABLE train_stop ADD CONSTRAINT fk_train_stop_station_id FOREIGN KEY (station_id) REFERENCES station (station_id);
CREATE INDEX ix_train_stop_station_id ON train_stop (station_id);
ALTER TABLE fare ADD CONSTRAINT fk_fare_from_station_id FOREIGN KEY (from_station_id) REFERENCES station (station_id);
CREATE INDEX ix_fare_from_station_id ON fare (from_station_id);
ALTER TABLE fare ADD CONSTRAINT fk_fare_to_station_id FOREIGN KEY (to_station_id) REFERENCES station (station_id);
CREATE INDEX ix_fare_to_station_id ON fare (to_station_id);
ALTER TABLE purchase_limit_policy ADD CONSTRAINT fk_purchase_limit_polic_88n0fo FOREIGN KEY (sale_event_id) REFERENCES sale_event (sale_event_id);
CREATE INDEX ix_purchase_limit_polic_k3jmve ON purchase_limit_policy (sale_event_id);
ALTER TABLE payment_method ADD CONSTRAINT fk_payment_method_member_id FOREIGN KEY (member_id) REFERENCES member (member_id);
CREATE INDEX ix_payment_method_member_id ON payment_method (member_id);
ALTER TABLE member_device ADD CONSTRAINT fk_member_device_member_id FOREIGN KEY (member_id) REFERENCES member (member_id);
CREATE INDEX ix_member_device_member_id ON member_device (member_id);
ALTER TABLE seat_inventory ADD CONSTRAINT fk_seat_inventory_xu9xs0 FOREIGN KEY (train_id, seat_id) REFERENCES seat (train_id, seat_id);
CREATE INDEX ix_seat_inventory_16tmgw ON seat_inventory (train_id, seat_id);
ALTER TABLE seat_inventory ADD CONSTRAINT fk_seat_inventory_1n43pk FOREIGN KEY (run_id, train_id) REFERENCES train_run (run_id, train_id);
CREATE INDEX ix_seat_inventory_ohrs5u ON seat_inventory (run_id, train_id);
ALTER TABLE seat_inventory ADD CONSTRAINT fk_seat_inventory_ol9n8k FOREIGN KEY (reservation_id) REFERENCES reservation (reservation_id);
CREATE INDEX ix_seat_inventory_1fqp55 ON seat_inventory (reservation_id);
ALTER TABLE reservation ADD CONSTRAINT fk_reservation_member_id FOREIGN KEY (member_id) REFERENCES member (member_id);
ALTER TABLE reservation ADD CONSTRAINT fk_reservation_run_id FOREIGN KEY (run_id) REFERENCES train_run (run_id);
CREATE INDEX ix_reservation_run_id ON reservation (run_id);
ALTER TABLE reservation ADD CONSTRAINT fk_reservation_from_station_id FOREIGN KEY (from_station_id) REFERENCES station (station_id);
CREATE INDEX ix_reservation_from_station_id ON reservation (from_station_id);
ALTER TABLE reservation ADD CONSTRAINT fk_reservation_to_station_id FOREIGN KEY (to_station_id) REFERENCES station (station_id);
CREATE INDEX ix_reservation_to_station_id ON reservation (to_station_id);
ALTER TABLE reservation_seat ADD CONSTRAINT fk_reservation_seat_kj4yk8 FOREIGN KEY (reservation_id) REFERENCES reservation (reservation_id);
ALTER TABLE reservation_seat ADD CONSTRAINT fk_reservation_seat_seat_id FOREIGN KEY (seat_id) REFERENCES seat (seat_id);
CREATE INDEX ix_reservation_seat_seat_id ON reservation_seat (seat_id);
ALTER TABLE reservation_history ADD CONSTRAINT fk_reservation_history_307xcj FOREIGN KEY (reservation_id) REFERENCES reservation (reservation_id);
CREATE INDEX ix_reservation_history_ygab9l ON reservation_history (reservation_id);
ALTER TABLE payment ADD CONSTRAINT fk_payment_reservation_id FOREIGN KEY (reservation_id) REFERENCES reservation (reservation_id);
ALTER TABLE payment ADD CONSTRAINT fk_payment_method_id FOREIGN KEY (method_id) REFERENCES payment_method (method_id);
CREATE INDEX ix_payment_method_id ON payment (method_id);
ALTER TABLE cancellation ADD CONSTRAINT fk_cancellation_reservation_id FOREIGN KEY (reservation_id) REFERENCES reservation (reservation_id);
CREATE INDEX ix_cancellation_reservation_id ON cancellation (reservation_id);
ALTER TABLE cancellation ADD CONSTRAINT fk_cancellation_fee_policy_id FOREIGN KEY (fee_policy_id) REFERENCES cancel_fee_policy (fee_policy_id);
CREATE INDEX ix_cancellation_fee_policy_id ON cancellation (fee_policy_id);
ALTER TABLE saga_instance ADD CONSTRAINT fk_saga_instance_2406qq FOREIGN KEY (reservation_id) REFERENCES reservation (reservation_id);
CREATE INDEX ix_saga_instance_19l8re ON saga_instance (reservation_id);
ALTER TABLE waitlist ADD CONSTRAINT fk_waitlist_member_id FOREIGN KEY (member_id) REFERENCES member (member_id);
CREATE INDEX ix_waitlist_member_id ON waitlist (member_id);
ALTER TABLE waitlist ADD CONSTRAINT fk_waitlist_run_id FOREIGN KEY (run_id) REFERENCES train_run (run_id);
ALTER TABLE waitlist ADD CONSTRAINT fk_waitlist_from_station_id FOREIGN KEY (from_station_id) REFERENCES station (station_id);
CREATE INDEX ix_waitlist_from_station_id ON waitlist (from_station_id);
ALTER TABLE waitlist ADD CONSTRAINT fk_waitlist_to_station_id FOREIGN KEY (to_station_id) REFERENCES station (station_id);
CREATE INDEX ix_waitlist_to_station_id ON waitlist (to_station_id);
ALTER TABLE waitlist ADD CONSTRAINT fk_waitlist_16o3t9 FOREIGN KEY (offered_reservation_id) REFERENCES reservation (reservation_id);
CREATE INDEX ix_waitlist_10yqnf ON waitlist (offered_reservation_id);
ALTER TABLE notification ADD CONSTRAINT fk_notification_member_id FOREIGN KEY (member_id) REFERENCES member (member_id);
CREATE INDEX ix_notification_member_id ON notification (member_id);
ALTER TABLE risk_score ADD CONSTRAINT fk_risk_score_model_version FOREIGN KEY (model_version) REFERENCES model_run (model_version);
CREATE INDEX ix_risk_score_model_version ON risk_score (model_version);
ALTER TABLE admin_action ADD CONSTRAINT fk_admin_action_admin_id FOREIGN KEY (admin_id) REFERENCES admin_user (admin_id);
CREATE INDEX ix_admin_action_admin_id ON admin_action (admin_id);
ALTER TABLE synthetic_label ADD CONSTRAINT fk_synthetic_label_member_id FOREIGN KEY (member_id) REFERENCES member (member_id);
ALTER TABLE member_credential ADD CONSTRAINT fk_member_credential_member_id FOREIGN KEY (member_id) REFERENCES member (member_id);
ALTER TABLE identity_verification ADD CONSTRAINT fk_identity_verificatio_10kec1 FOREIGN KEY (member_id) REFERENCES member (member_id);
CREATE INDEX ix_identity_verificatio_1qtho3 ON identity_verification (member_id);
ALTER TABLE auth_session ADD CONSTRAINT fk_auth_session_member_id FOREIGN KEY (member_id) REFERENCES member (member_id);
CREATE INDEX ix_auth_session_member_id ON auth_session (member_id);
ALTER TABLE auth_session ADD CONSTRAINT fk_auth_session_admin_id FOREIGN KEY (admin_id) REFERENCES admin_user (admin_id);
CREATE INDEX ix_auth_session_admin_id ON auth_session (admin_id);
ALTER TABLE suspicious_case ADD CONSTRAINT fk_suspicious_case_assignee_id FOREIGN KEY (assignee_id) REFERENCES admin_user (admin_id);
CREATE INDEX ix_suspicious_case_assignee_id ON suspicious_case (assignee_id);
ALTER TABLE suspicious_case ADD CONSTRAINT fk_suspicious_case_znmpak FOREIGN KEY (admin_action_id) REFERENCES admin_action (action_id);
CREATE INDEX ix_suspicious_case_v12erm ON suspicious_case (admin_action_id);
ALTER TABLE case_session ADD CONSTRAINT fk_case_session_case_id FOREIGN KEY (case_id) REFERENCES suspicious_case (case_id);
ALTER TABLE case_session ADD CONSTRAINT fk_case_session_session_id FOREIGN KEY (session_id) REFERENCES auth_session (session_id);
CREATE INDEX ix_case_session_session_id ON case_session (session_id);
ALTER TABLE case_session ADD CONSTRAINT fk_case_session_member_id FOREIGN KEY (member_id) REFERENCES member (member_id);
CREATE INDEX ix_case_session_member_id ON case_session (member_id);
ALTER TABLE case_marker ADD CONSTRAINT fk_case_marker_case_id FOREIGN KEY (case_id) REFERENCES suspicious_case (case_id);
CREATE INDEX ix_case_marker_case_id ON case_marker (case_id);
ALTER TABLE case_marker ADD CONSTRAINT fk_case_marker_session_id FOREIGN KEY (session_id) REFERENCES auth_session (session_id);
CREATE INDEX ix_case_marker_session_id ON case_marker (session_id);
ALTER TABLE case_marker ADD CONSTRAINT fk_case_marker_created_by FOREIGN KEY (created_by) REFERENCES admin_user (admin_id);
CREATE INDEX ix_case_marker_created_by ON case_marker (created_by);
ALTER TABLE replay_access_log ADD CONSTRAINT fk_replay_access_log_admin_id FOREIGN KEY (admin_id) REFERENCES admin_user (admin_id);
CREATE INDEX ix_replay_access_log_admin_id ON replay_access_log (admin_id);
ALTER TABLE replay_access_log ADD CONSTRAINT fk_replay_access_log_case_id FOREIGN KEY (case_id) REFERENCES suspicious_case (case_id);
CREATE INDEX ix_replay_access_log_case_id ON replay_access_log (case_id);
ALTER TABLE replay_access_log ADD CONSTRAINT fk_replay_access_log_mw9lo7 FOREIGN KEY (session_id) REFERENCES auth_session (session_id);
CREATE INDEX ix_replay_access_log_1waknh ON replay_access_log (session_id);
ALTER TABLE cancel_fee_policy ADD CONSTRAINT fk_cancel_fee_policy_14or9c FOREIGN KEY (sale_event_id) REFERENCES sale_event (sale_event_id);
CREATE INDEX ix_cancel_fee_policy_psonp8 ON cancel_fee_policy (sale_event_id);
ALTER TABLE app_policy ADD CONSTRAINT fk_app_policy_updated_by FOREIGN KEY (updated_by) REFERENCES admin_user (admin_id);
CREATE INDEX ix_app_policy_updated_by ON app_policy (updated_by);
ALTER TABLE app_policy_history ADD CONSTRAINT fk_app_policy_history_1to7gd FOREIGN KEY (policy_key) REFERENCES app_policy (policy_key);
CREATE INDEX ix_app_policy_history_1vuo6y ON app_policy_history (policy_key);
ALTER TABLE app_policy_history ADD CONSTRAINT fk_app_policy_history_1k33d7 FOREIGN KEY (changed_by) REFERENCES admin_user (admin_id);
CREATE INDEX ix_app_policy_history_1jzu2w ON app_policy_history (changed_by);

-- 예시 데이터 (팀 확정 전 예시값)
INSERT INTO model_run (model_version, algorithm, params, train_source, trained_at, threshold, decay_half_life_days, is_active) VALUES ('rule-2026.11-01', 'RULE', '{"weights":"risk_score 신호별 가중치"}', 'synthetic v1', TIMESTAMP '2026-11-18 10:00:00', 80, 30, 'Y');
INSERT INTO model_run (model_version, algorithm, params, train_source, trained_at, threshold, decay_half_life_days, is_active) VALUES ('iforest-2026.11-01', 'IFOREST', '{"n_estimators":200,"contamination":0.05}', 'synthetic v1 + ext_web_access_log', TIMESTAMP '2026-11-18 10:00:00', 80, 30, 'N');
INSERT INTO sale_event (sale_event_id, name, holiday_from, holiday_to, sale_open_at, priority_open_at, status) VALUES (1, '2026 추석 (예시)', DATE '2026-09-24', DATE '2026-09-27', TIMESTAMP '2026-09-08 07:00:00', TIMESTAMP '2026-09-07 07:00:00', 'PLANNED');
INSERT INTO app_policy (policy_key, policy_value, version, value_type, description) VALUES ('inventory.segment_mode', 'OFF', 1, 'STRING', '구간 재고 사용 여부 (OFF면 segment_no=0). 2주차 말 결정');
INSERT INTO app_policy (policy_key, policy_value, version, value_type, description) VALUES ('queue.admit_per_sec', '200', 1, 'NUMBER', '초당 대기열 입장 허용 인원');
INSERT INTO app_policy (policy_key, policy_value, version, value_type, description) VALUES ('queue.pass_ttl_sec', '300', 1, 'NUMBER', '입장 토큰 유효 시간');
INSERT INTO app_policy (policy_key, policy_value, version, value_type, description) VALUES ('reservation.pay_deadline_min', '10', 1, 'NUMBER', '좌석 선점 후 결제 기한(분). seat_inventory.hold_expires_at 계산 기준');
INSERT INTO app_policy (policy_key, policy_value, version, value_type, description) VALUES ('risk.member_penalty_rule', 'MAX', 1, 'STRING', '회원 패널티 = 연결된 CI·결제수단·기기 점수 중 최댓값');
INSERT INTO app_policy (policy_key, policy_value, version, value_type, description) VALUES ('risk.penalty_ms_per_point', '1000', 1, 'NUMBER', '위험 점수 1점당 대기열 score에 더하는 ms');
INSERT INTO app_policy (policy_key, policy_value, version, value_type, description) VALUES ('replay.full_record_ratio', '0.10', 1, 'NUMBER', '전체 녹화 비율 (위험 상위)');
INSERT INTO app_policy (policy_key, policy_value, version, value_type, description) VALUES ('replay.full_record_score', '70', 1, 'NUMBER', '이 점수 이상이면 무조건 전체 녹화');
INSERT INTO app_policy (policy_key, policy_value, version, value_type, description) VALUES ('replay.retention_days', '90', 1, 'NUMBER', '녹화 보관 기간');
INSERT INTO app_policy (policy_key, policy_value, version, value_type, description) VALUES ('replay.max_path_points', '50', 1, 'NUMBER', '이벤트 하나의 마우스 궤적 최대 점 수');
INSERT INTO app_policy (policy_key, policy_value, version, value_type, description) VALUES ('replay.batch_sec', '5', 1, 'NUMBER', '클라이언트가 녹화 이벤트를 묶어 보내는 간격(초)');
INSERT INTO app_policy (policy_key, policy_value, version, value_type, description) VALUES ('replay.max_events_per_session', '5000', 1, 'NUMBER', '세션당 녹화 이벤트 상한');
INSERT INTO app_policy (policy_key, policy_value, version, value_type, description) VALUES ('behavior.batch_size', '1000', 1, 'NUMBER', 'behavior_log 적재 컨슈머의 insertMany 묶음 크기');
INSERT INTO app_policy (policy_key, policy_value, version, value_type, description) VALUES ('outbox.retention_hours', '24', 1, 'NUMBER', '발행 완료 outbox 행 보관 시간');
INSERT INTO app_policy (policy_key, policy_value, version, value_type, description) VALUES ('outbox.relay_batch', '500', 1, 'NUMBER', '릴레이가 한 번에 가져오는 행 수');
INSERT INTO app_policy (policy_key, policy_value, version, value_type, description) VALUES ('auth.argon2_params', 'm=19456,t=2,p=1', 1, 'STRING', 'Argon2id 파라미터 (OWASP 권장값 중 하나)');
INSERT INTO app_policy (policy_key, policy_value, version, value_type, description) VALUES ('auth.max_concurrent_hash', '32', 1, 'NUMBER', '동시 Argon2 검증 수 (해시 1회 약 19MiB)');
INSERT INTO app_policy (policy_key, policy_value, version, value_type, description) VALUES ('auth.lock_after_failures', '5', 1, 'NUMBER', '연속 실패 시 잠금 기준');
INSERT INTO app_policy (policy_key, policy_value, version, value_type, description) VALUES ('auth.lock_minutes', '15', 1, 'NUMBER', '잠금 시간(분)');
INSERT INTO purchase_limit_policy (policy_id, sale_event_id, scope, max_seats, valid_from, valid_to) VALUES (1, 1, 'PER_RESERVATION', 4, TIMESTAMP '2026-09-07 00:00:00', TIMESTAMP '2026-09-27 23:59:00');
INSERT INTO purchase_limit_policy (policy_id, sale_event_id, scope, max_seats, valid_from, valid_to) VALUES (2, 1, 'PER_RUN', 4, TIMESTAMP '2026-09-07 00:00:00', TIMESTAMP '2026-09-27 23:59:00');
INSERT INTO purchase_limit_policy (policy_id, sale_event_id, scope, max_seats, valid_from, valid_to) VALUES (3, 1, 'PER_HOLIDAY', 8, TIMESTAMP '2026-09-07 00:00:00', TIMESTAMP '2026-09-27 23:59:00');
INSERT INTO cancel_fee_policy (fee_policy_id, sale_event_id, min_minutes_before, max_minutes_before, fee_rate, after_departure) VALUES (1, 1, 4320, NULL, 0, 'N');
INSERT INTO cancel_fee_policy (fee_policy_id, sale_event_id, min_minutes_before, max_minutes_before, fee_rate, after_departure) VALUES (2, 1, 1440, 4320, 0.05, 'N');
INSERT INTO cancel_fee_policy (fee_policy_id, sale_event_id, min_minutes_before, max_minutes_before, fee_rate, after_departure) VALUES (3, 1, 180, 1440, 0.1, 'N');
INSERT INTO cancel_fee_policy (fee_policy_id, sale_event_id, min_minutes_before, max_minutes_before, fee_rate, after_departure) VALUES (4, 1, 0, 180, 0.2, 'N');
INSERT INTO cancel_fee_policy (fee_policy_id, sale_event_id, min_minutes_before, max_minutes_before, fee_rate, after_departure) VALUES (5, 1, NULL, NULL, 0.4, 'Y');
COMMIT;