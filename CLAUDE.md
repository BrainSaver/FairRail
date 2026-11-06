# FairRail — Claude 작업 안내

명절 열차 공정 예매 시스템 팀 프로젝트(5명, 3주). Spring Boot · Kafka · Redis · MongoDB · Oracle · Python.
이 문서는 Claude가 ERD 편집기(`fairrail-erd.html`)를 읽고, 고치고, 팀원이 편집기에서 바꾼 내용을 반영할 때 따르는 규칙입니다.

## 저장소 구조

```
docs/erd/fairrail-erd.html      ERD 편집기 = 스키마의 단일 원본
docs/erd/fairrail-erd.ddl.sql   check-erd.js가 생성하는 Oracle DDL (직접 고치지 않음)
docs/erd/exports/*.json         팀원이 편집기에서 내보낸 JSON (이름-날짜.json)
docs/spec/*.md                  v1~v4 명세·점검 보고서 (변경 이력, 읽기 전용)
tools/check-erd.js              스키마 검사 + DDL 생성
tools/erd-diff.js               내보낸 JSON → 다음 버전 패치 코드
tools/erd-md.js                 HTML → 종합 ERD 문서 생성
docs/FairRail_ERD.md            종합 ERD 문서 (erd-md.js가 생성, 직접 고치지 않음)
docs/concurrency.md             동시성 절차의 원천 (트랜잭션 순서·SQL·Redis Lua·락 순서·테스트 목록)
docs/작업안내.md                팀원용 안내
docs/templates/                 트러블슈팅·개인 기여 문서 틀
docs/{이름}/                    팀원별 contribution.md, features/(기능 문서), troubleshooting/
.github/pull_request_template.md  PR 틀
CONTRIBUTING.md                 깃 규칙
```

- 스키마를 바꾼 뒤에는 종합 문서도 다시 만듭니다: `node tools/erd-md.js docs/erd/fairrail-erd.html > docs/FairRail_ERD.md`

- **원천은 두 개**입니다. 스키마(테이블·컬럼·제약·인덱스)는 HTML, 절차(트랜잭션 순서·SQL·Redis 명령)는 `docs/concurrency.md`. 테이블 비고에는 절차를 쓰지 않고 `concurrency.md §n`처럼 절 번호만 적습니다. 검사 스크립트가 § 번호가 실제로 있는지 확인합니다.
- 스키마 쪽은 HTML 하나가 원본입니다. `docs/spec`의 md는 과거 기록이라 최신과 다를 수 있습니다 (예: v2 md의 replay_event 시계열 설계는 v3에서 바뀜). 최신 명세가 필요하면 HTML의 데이터 블록을 읽거나 편집기 "내보내기 → Markdown 명세"를 쓰세요.
- 스키마를 바꾼 커밋에는 항상 `node tools/check-erd.js docs/erd/fairrail-erd.html` 결과가 **FAIL 0**이어야 합니다. 이 명령이 `fairrail-erd.ddl.sql`도 다시 만듭니다.

## 깃 규칙 (자세한 건 CONTRIBUTING.md)

- 커밋 메시지: `타입(범위): 제목` 한국어. 타입은 feat, fix, perf, refactor, test, db, docs, build, ci, chore
- 커밋·PR에 `Co-Authored-By`, `Claude-Session`, `Generated with Claude Code` 등 Claude 흔적을 넣지 않습니다 (`.claude/settings.json`으로도 꺼 둠)
- 작업은 각자 이름 브랜치(`SeongWon`, `DongGyun`, `DongHyeon`, `DaIn`, `YoungJun`)에서 하고 PR로 main에 합칩니다. 새 브랜치를 만들지 않습니다
- ERD HTML 패치는 ERD 반영 담당자(강동균)의 요청일 때만 씁니다. 다른 팀원이 스키마 변경을 요청하면 편집기에서 JSON을 내보내 `docs/erd/exports/`에 올리라고 안내합니다
- **팀원이 자기 기능을 이해하게 돕습니다** (CONTRIBUTING.md 4장). 코드를 작성하거나 고친 뒤에는 핵심 원리와 이렇게 한 이유를 쉽고 짧게 설명합니다. 기능을 main에 합칠 때 `docs/{이름}/features/`에 짧은 기능 문서를 남기자고 안내하고, 다른 팀원이 1~2분 안에 이해할 수 있는 수준으로 씁니다
- 버그를 고쳤으면 `docs/templates/troubleshooting.md` 형식으로 `docs/{이름}/troubleshooting/`에 문서 초안을 같이 만들자고 제안합니다

## HTML 안의 구조

`<script>` 안에 다음 순서로 있습니다. 위쪽은 데이터, 아래쪽은 편집기 코드입니다.

| 블록 | 내용 | 수정 |
|---|---|---|
| `GROUPS` | 영역(색·저장소) 정의 | 새 영역이 필요할 때만. 색 토큰 `--g-{키}`를 CSS 세 곳(밝은 `:root`, 어두운 두 블록)에 함께 추가 |
| `SEED` | v1 테이블 | **고치지 않음** |
| `SEED_V2` | v2 테이블 (보안·CCTV·빅데이터) | **고치지 않음** |
| `V3_TABLES`, `V3_OPS` | v3 점검 패치 | **고치지 않음** |
| `V4_TABLES`, `V4_OPS` | v4 패치 (app_policy, 확장 예정, NOT NULL 등) | **고치지 않음** |
| `V5_TABLES`, `V5_OPS` | v5 패치 (팀 검토 12건: 복합 FK, HOLD 만료, purchase_counter, 인덱스, 이력 등) | **고치지 않음** |
| `V6_TABLES`, `V6_OPS` | v6 패치 (2차 검토: 결제 마감 연장, outbox 샤드, 흐름 순서, 참조 전용, expire_at 등) | **고치지 않음** |
| `V7_TABLES`, `V7_OPS`, `DECISION_REFRESH` | v7 패치 (3차 검토 + 비고를 concurrency.md 참조로 축약) | **고치지 않음** |
| `DECISIONS_SEED` | 팀 결정 사항 기본값 | 팀이 값을 확정하면 수정 가능 |
| `DOCS` | 편집기 "문서" 창 내용 (공통 규칙·흐름·추적표·시나리오·생성 규칙·확장·이력) | 자유롭게 수정 |
| `PATCHES` | `[{v:3,…},…,{v:7,…}]` 패치 목록. `SEED_VERSION`은 여기서 자동 계산 | 새 패치를 **끝에** 추가 |
| `LAYOUT` | "자동 정렬" 시 열 배치 | 새 테이블을 알맞은 열에 추가 |
| 그 아래 | 패치 엔진, 렌더링, 패널, 문서 창, DDL·Markdown 내보내기, 시작 코드 | UI 작업 때만 |

### 데이터 형식

```js
// 테이블
{id:'reservation', ko:'예약', g:'resv', db:'MongoDB'(생략 시 영역 기본값), big:true(빅데이터), planned:true(확장 예정),
 noUpdatedAt:true(INSERT만 하는 테이블, DDL에서 updated_at 생략), refOnly:true(행을 지우지 않는 참조 테이블, 이 테이블을 가리키는 FK에 인덱스 생략),
 desc:'설명', notes:'제약·인덱스·비고', samples:[{컬럼:값,…}], cols:[컬럼튜플,…]}
// 컬럼 튜플
['컬럼명','타입','키','출처','설명','이유','FK대상테이블(선택)']
//  키: 'PK','FK','UQ','NN'을 쉼표로 (예: 'PK,FK' / 'FK,NN')
//  출처: '공공' | '생성' | '시스템' | '공공/생성' | '외부'
```

### 패치 op

| op | 형식 | 동작 |
|---|---|---|
| add | `['add', 표, 뒤에올컬럼 또는 null(맨 앞), [튜플,…]]` | 컬럼 추가 (같은 이름이 있으면 건너뜀) |
| set | `['set', 표, 컬럼, {type, keys, src, desc, reason, fk}]` | 컬럼 속성 변경 |
| del | `['del', 표, 컬럼]` | 컬럼 삭제 |
| prop | `['prop', 표, {ko, g, db, big, planned, noUpdatedAt, refOnly, samples}]` | 테이블 속성 변경 (samples는 통째로 교체) |
| samples+ | `['samples+', 표, [행,…]]` | PK 값이 없는 예시 행만 추가 (기존 행과 팀원 수정은 유지) |
| samples= | `['samples=', 표, [행,…]]` | PK로 찾아 적은 필드만 덮어쓰기, 없으면 추가 (예시값을 바꿀 때) |
| desc / notes / notes+ | `['notes+', 표, '문자열']` | 설명 교체 / 비고 교체 / 비고 덧붙이기 |
| nn | `['nn', 표, ['컬럼',…]]` | NOT NULL 지정 |
| nn-auto | `['nn-auto', null, {except:['표.컬럼',…]}]` | 그 패치 시점까지 있던 Oracle 테이블의 FK·상태 코드 컬럼에 NOT NULL 일괄 지정 (v4에서 한 번 사용. 새 패치에선 `nn`을 쓰세요) |
| droptable | `['droptable', 표]` | 테이블 삭제 + 그 테이블을 가리키던 FK 해제 |

모든 op는 **두 번 적용해도 결과가 같아야** 합니다. 검사 스크립트가 확인합니다. 예: 기존 컬럼의 설명을 `A / B` 형식으로 바꾸면 v4 `nn-auto`가 다시 돌 때 NOT NULL이 붙으므로, NULL을 허용해야 하는 코드 컬럼은 설명 대신 비고에 `CHECK(…)`로 허용값을 적습니다 (v5의 `reservation_history.from_status`). 컬럼 이름 변경 op는 없습니다. 이름을 바꾸려면 `del` 후 `add`를 쓰고, 그 컬럼을 참조하던 비고·문서·예시 행도 같이 고치세요.

## 스키마를 바꾸는 규칙

1. **이미 배포된 블록(`SEED`, `SEED_V2`, `V3_*` ~ `V7_*`)은 고치지 않습니다.** 팀원 브라우저에는 스키마가 저장돼 있고, 편집기는 저장된 버전(`seedVersion`) 이후의 패치만 적용합니다. 기존 블록을 고치면 새로 연 사람과 원래 쓰던 사람의 스키마가 달라집니다.
2. 바꿀 내용은 새 패치로 만듭니다.
   ```js
   const V8_TABLES = [ /* 새 테이블 */ ];
   const V8_OPS = [ ['add','member','ci_hash',[['birth_year','NUMBER(4)','','생성','출생 연도','연령대 통계']]] ];
   const PATCHES = [ …기존…, {v:8,tables:V8_TABLES,ops:V8_OPS} ];
   ```
   `V8_*`는 `PATCHES` 바로 위에 둡니다.
3. 새 테이블은 `LAYOUT`의 알맞은 열에 넣습니다 (빠지면 검사에서 WARN).
4. `DOCS.history`에 `['v8','변경 요약']` 한 줄을 추가합니다. 기능이나 실패 시나리오가 바뀌면 `DOCS.trace`, `DOCS.scenarios`도 고칩니다.
5. `node tools/check-erd.js docs/erd/fairrail-erd.html` → FAIL 0 확인. WARN은 읽고 의도한 것인지 판단합니다 (FK를 일부러 걸지 않는 ID 컬럼은 스크립트의 `NO_FK_OK`에 추가).
6. 저장소 키 `STORE = 'fairrail-erd-v1'`은 **바꾸지 않습니다.** 바꾸면 모든 팀원의 편집 내용이 사라집니다.

## 테이블 설계 규칙

| 항목 | 규칙 |
|---|---|
| 이름 | 소문자 snake_case. Oracle 테이블·컬럼은 30자 이내, Oracle 예약어 금지 (검사 스크립트가 확인) |
| 공통 컬럼 | Oracle 테이블의 `created_at`, `updated_at`은 DDL이 자동 추가하므로 컬럼 목록에 넣지 않음 (의미가 다른 시각만 넣음) |
| PK | Oracle 테이블은 반드시 PK. ID는 `NUMBER`(시퀀스·Snowflake), 이벤트·세션은 `VARCHAR2(36)` UUID |
| FK | FK 컬럼 타입은 대상 PK와 같게. MongoDB 쪽 참조는 점선(논리 참조)이고 DB 제약은 없음 |
| NOT NULL | 필수값은 키에 `NN`. FK·상태 코드는 v4의 `nn-auto`가 자동 지정했으니 새 컬럼은 직접 지정 |
| 상태 코드 | 컬럼 설명을 `A / B / C` (대문자, 공백-슬래시-공백) 형식으로 쓰면 DDL에 CHECK 제약이 자동 생성됨. Java enum 값도 같게 |
| 여부 | `CHAR(1)` + 설명에 `Y/N` 또는 `여부` → CHECK ('Y','N') |
| 금액 | `NUMBER(10)` 원 단위 |
| 시간 | `TIMESTAMP`, Asia/Seoul. 서버·DB·JVM 시간대 고정 |
| 비밀번호 | Argon2id PHC 문자열 `VARCHAR2(255)` (member_credential, admin_user). 파라미터는 app_policy `auth.argon2_params` |
| 토큰 | 리프레시·재설정 토큰은 SHA-256 해시만 저장 |
| 식별 해시 | `*_hash`는 HMAC-SHA256. 키는 프로젝트 기간 고정 |
| 복호화가 필요한 개인정보 | AES-256-GCM 암호문 + 키 버전 컬럼 (`phone_enc` + `enc_key_id`) |
| 예시 데이터 | `samples`에는 가짜 값만. 실제 개인정보·키·토큰 금지. **NOT NULL 컬럼은 모든 예시 행에 값이 있어야 함** (없으면 DDL INSERT 실패, 검사 FAIL). 확정 전 값은 결정 사항 상태를 "예시"로 |
| 수정 없는 테이블 | INSERT만 하는 테이블은 `noUpdatedAt:true` (processed_event, reservation_history, app_policy_history) |
| updated_at | DDL 기본값은 INSERT 시각뿐. JPA Auditing(`@LastModifiedDate`)으로 세팅하고, **비고의 네이티브 조건부 UPDATE에는 반드시 `updated_at = SYSTIMESTAMP`** |
| 마감 시각 | `reservation.pay_deadline_at`이 원천. `seat_inventory.hold_expires_at`, Redis `seat:hold` TTL, `saga_instance.timeout_at`, `waitlist.offer_deadline_at`은 같은 값을 복사하고 바꿀 때도 함께 |
| 참조 전용 | 행을 지우지 않는 참조 테이블은 `refOnly:true` (station, route, car_type). 삭제가 생기면 플래그를 풀어 FK 인덱스를 되살림 |
| 인덱스 | 쓰기 폭주 테이블(reservation, seat_inventory, outbox_event)에 인덱스를 추가할 땐 쓰는 쿼리를 비고에 같이 적음. 배치 전용이면 오프피크 풀스캔을 먼저 검토 |
| 빅데이터 | 대량 적재 컬렉션은 `big:true` (편집기 "빅데이터" 버튼이 흐리게 처리) |
| 확장 예정 | 지금 구현하지 않는 테이블은 `planned:true` (점선 표시, DDL 제외) |

### 비고(notes)에 쓰면 DDL에 반영되는 형식

편집기는 단일 컬럼 FK만 선으로 그립니다. 복합 제약과 인덱스는 비고에 아래 형식으로 적으면 DDL 생성기와 검사 스크립트가 읽습니다. 여러 개는 ` · `로 구분합니다.

| 형식 | 예 | DDL |
|---|---|---|
| `UNIQUE(a, b)` | `UNIQUE(member_id, idempotency_key)` | 테이블 UNIQUE 제약 |
| `CHECK(조건)` | `CHECK((status = 'HOLD' AND hold_expires_at IS NOT NULL) OR …)` | 테이블 CHECK 제약 (괄호 짝 맞춤) |
| `FK(a, b) → 표(c, d)` | `FK(train_id, seat_id) → seat(train_id, seat_id)` | 복합 FK + 인덱스. 대상 표에 같은 컬럼·순서의 PK나 `UNIQUE(c, d)`가 있어야 함. 같은 대상을 가리키는 단일 FK는 DDL에서 생략 |
| `CREATE SEQUENCE 이름 …;` | `CREATE SEQUENCE outbox_seq CACHE 1000;` | DDL 맨 앞에 출력 |
| `CREATE [UNIQUE] INDEX 이름 ON 표 (…);` | `CREATE INDEX ix_resv_deadline ON reservation (CASE WHEN … END);` | 그대로 출력. **끝에 `;`** 를 붙여야 뒤 설명과 구분됨. 이름 30자 이내 |

상태 코드 컬럼(`status`, `*_type` 등)에 CHECK가 없으면 검사 스크립트가 WARN을 냅니다. 값이 열려 있는 컬럼은 스크립트의 `NO_CHECK_OK`에 추가합니다.

## 팀원이 편집기에서 고친 내용 반영하기

팀원은 편집기(브라우저)에서 직접 고치고 JSON을 내보냅니다. Claude는 그 JSON을 패치로 바꿔 HTML에 반영합니다.

1. 팀원: 편집기 → "내보내기" → "JSON 내보내기" → 복사 → `docs/erd/exports/{이름}-{YYYYMMDD}.json`으로 저장해 커밋.
2. Claude:
   ```bash
   node tools/erd-diff.js docs/erd/fairrail-erd.html docs/erd/exports/kim-20261110.json
   ```
3. 출력된 `V{n}_TABLES`, `V{n}_OPS`를 읽고 사람에게 요약해 확인받습니다. 특히 다음은 반드시 짚습니다.
   - `del`·`droptable`: 의도한 삭제인지, 이름 변경이었는지
   - `// 확인 필요:` 줄 전부
   - 다른 사람의 최근 변경을 되돌리는 op (그 팀원 JSON이 최신 HTML보다 오래됐을 때 생김)
4. 확인된 패치를 `PATCHES` 위에 붙이고 `PATCHES`에 등록, `LAYOUT`·`DOCS.history` 갱신.
5. 검사 후 같은 JSON으로 `erd-diff.js`를 다시 돌려 `// 차이 없음`이 나오는지 확인합니다.
6. 여러 명의 JSON은 **한 번에 하나씩**, 내보낸 시각 순서대로 반영합니다.
7. 결정 사항(`decisions`)이 바뀌어 있으면 스크립트가 알려줍니다. 팀이 확정한 값이면 `DECISIONS_SEED`를 그 값으로 바꾸고, 연결된 예시 행(app_policy 등)은 `prop` op로 맞춥니다.

## 코드로 옮길 때

- **Oracle**: `docs/erd/fairrail-erd.ddl.sql`을 그대로 실행 (CREATE → COMMENT → FK·인덱스 → 예시 INSERT 순). 직접 고치지 말고 HTML을 고친 뒤 다시 생성합니다.
- **JPA**: 복합 PK 테이블(route_station, train_car, train_stop, member_device, seat_inventory, reservation_seat, processed_event, risk_score, case_session, purchase_counter)은 `@IdClass` 또는 `@EmbeddedId`. 상태 코드는 `@Enumerated(EnumType.STRING)`, `CHAR(1)` Y/N은 `AttributeConverter<Boolean,String>`.
- **MongoDB**: 테이블 비고(notes)에 적힌 인덱스·TTL·유니크를 `mongo-init.js`로 만듭니다 (편집기 DDL은 Oracle만 생성).
- **Redis**: `redis_keys` 테이블의 키 패턴을 그대로 쓰고, TTL·임계값은 하드코딩하지 말고 `app_policy`에서 읽습니다. 매수 제한은 Redis가 1차, `purchase_counter` 조건부 UPDATE가 최종 판정입니다.
- **동시성 절차**: `docs/concurrency.md`를 그대로 구현합니다. 절차를 바꿔야 하면 그 문서를 먼저 고치고, 스키마 변경이 따르면 같은 커밋에서 HTML 패치도 만듭니다. §16 테스트 목록은 통합 테스트로 옮깁니다.
- **Kafka**: 메시지 키는 `outbox_event.partition_key`. 예약 흐름 이벤트는 모두 reservation_id. 릴레이는 `shard_no`로 담당 샤드를 고정하고 샤드 안에서 순서대로, 멱등 프로듀서로 발행합니다.
- **Redis**: 단일 노드 전제. 클러스터로 바꾸면 `redis_keys` 비고의 해시 태그 규칙으로 키를 바꿔야 Lua 다중 키가 동작합니다.

## 편집기 UI를 고칠 때

- 파일을 브라우저로 바로 열어도 동작해야 합니다: 맨 위 `<meta charset="utf-8">`, CSS의 `[hidden]{display:none!important}` 유지.
- 색은 CSS 토큰(`--bg`, `--fg`, `--g-*` 등)만 쓰고 밝은·어두운 테마 블록 세 곳을 함께 고칩니다.
- `localStorage` 읽기·쓰기는 try/catch 안에서만.
- 외부 스크립트를 추가하지 않습니다 (claude.ai 아티팩트로 배포할 때 CDN 제한이 있음). 글꼴만 Google Fonts.
- 폭 390px(모바일)에서도 패널이 하단 시트로 동작하는지 확인합니다.
- `alert`·`confirm`·`prompt`를 쓰지 않습니다. 삭제는 "한 번 더 누르면 삭제" 두 단계 버튼 방식.

## 하지 말 것

- 테이블 비고에 SQL 절차를 다시 길게 쓰기 (concurrency.md에 쓰고 § 번호만 참조)
- 배포된 패치 블록 수정, `STORE` 키 변경
- `fairrail-erd.ddl.sql`이나 `docs/spec/*.md`를 원본처럼 직접 수정
- 검사 FAIL이 남은 상태로 커밋
- 예시 데이터에 실제 개인정보·비밀값 넣기
