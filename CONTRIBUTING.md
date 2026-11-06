# FairRail 깃 규칙

커밋 메시지 틀을 쓰려면 한 번만 실행: `git config commit.template .gitmessage`
한글 경로가 `\352\270...`처럼 보이면: `git config core.quotepath false`

## 1. 커밋 메시지 형식

```
<타입>(<범위>): <제목>

<본문: 왜 바꿨는지, 무엇이 달라지는지. 수치가 있으면 수치>

<꼬리말: Refs: #이슈번호 / 트러블슈팅: docs/본인이름/troubleshooting/파일.md>
```

예시

```
feat(seat): Redis 분산락으로 좌석 선점 처리

비관적 락 대비 TPS 비교용. 락 대기 3초 초과 시 선점 실패로 응답.

Refs: #14
```

```
fix(payment): PG 콜백 중복 수신 시 결제가 두 번 승인되는 문제 수정

processed_event에 event_id UNIQUE를 걸고 INSERT 실패 시 건너뛰도록 변경.
동시 콜백 1,000건 테스트에서 중복 승인 37건 → 0건.

Refs: #21
트러블슈팅: docs/길동현/troubleshooting/20261118-결제-콜백-중복.md
```

### 제목 규칙

- 한국어, 50자 이내, 끝에 마침표 없음
- "~추가", "~수정", "~제거"처럼 무엇을 했는지로 끝냄 ("수정함", "했습니다" X)
- 커밋 하나에 목적 하나. 제목에 "및", "그리고"가 들어가면 나눌 것

### 타입

| 타입 | 언제 |
|---|---|
| `feat` | 새 기능 |
| `fix` | 버그 수정 |
| `perf` | 성능 개선 (본문에 전후 수치 필수) |
| `refactor` | 동작은 같고 구조만 변경 |
| `test` | 테스트 추가·수정 (k6 시나리오 포함) |
| `db` | 스키마 변경 (ERD 편집기 패치, DDL, Mongo 인덱스) |
| `docs` | 문서만 변경 (트러블슈팅·기여 문서 포함) |
| `build` | Gradle, 의존성 |
| `ci` | GitHub Actions 등 CI/CD |
| `chore` | 그 외 잡일 (.gitignore, 설정 파일 등) |

### 범위 (담당 파트 기준)

| 범위 | 내용 | 주 담당 |
|---|---|---|
| `queue` | 대기열·번호표·입장 토큰 | A 김성원 |
| `hmac` | 식별정보 가명처리 | A 김성원 |
| `seat` | 좌석 선점·락·매수 제한·자동 반환 | B 강동균 |
| `train` | 열차·노선·좌석 도메인, 공공데이터 적재 | B 강동균 |
| `event` | Kafka 이벤트·토픽 설계 | C 길동현 |
| `payment` | 결제(PG 테스트 모드) | C 길동현 |
| `saga` / `outbox` | Saga, Outbox 릴레이, 멱등성 | C 길동현 |
| `notify` | 재배정 알림 | C 길동현 |
| `log` / `risk` | 행동 로그, 위험 점수 | D 강다인 |
| `timeline` | 의심 구간 타임라인 | D 강다인 |
| `cancel` | 취소·환불·재배정 대기 | D 강다인 |
| `member` | 회원·모의 본인인증·암호화 | D 강다인 |
| `admin` | 관리자 화면 | B·D |
| `infra` | Docker Compose, Prometheus·Grafana | E 조영준 |
| `auth` | Spring Security·JWT | E 조영준 |
| `k6` | 부하·봇 시나리오 | E 조영준 |
| `erd` | ERD 프로그램(편집기·도구) | 반영은 ERD 담당자 B 강동균 |

범위가 둘 이상에 걸치면 더 핵심인 쪽 하나만 씁니다. 전체에 걸치면 생략 가능: `chore: .gitignore 추가`.

## 2. 커밋할 때 지킬 것

1. **원칙은 내 브랜치 → PR**. main 직접 push는 막혀 있지 않지만 쓰지 않습니다 (3장).
2. **`git push --force` 금지**. 내 브랜치를 최신 main에 맞출 때도 rebase 대신 `git pull origin main`(merge)을 씁니다.
3. **비밀값 금지**: `.env`, PG 테스트 키, JWT 시크릿, HMAC·AES 키는 커밋하지 않습니다. `.env.example`에 키 이름만 둡니다.
4. **빌드가 깨진 상태로 push 금지**: 최소한 `./gradlew build`(또는 해당 모듈 테스트) 통과 후 push.
5. **AI 도구 흔적 금지**: `Co-Authored-By: Claude`, `Claude-Session`, `Generated with Claude Code` 같은 줄을 넣지 않습니다. 작성자는 본인 GitHub 계정. 레포의 `.claude/settings.json`이 Claude Code의 커밋·PR 서명을 자동으로 끕니다 (지우지 말 것).
6. **ERD 반영은 담당자 1명만**: 다른 팀원은 ERD 프로그램에서 내보낸 JSON을 `docs/erd/exports/이름-YYYYMMDD.json`으로 올리기만 하고, HTML 패치·DDL·종합 문서 반영은 ERD 담당자(강동균)가 내보낸 순서대로 합니다.
7. **스키마 변경(`db`)은 한 커밋에 묶음**: `fairrail-erd.html` + 재생성된 `fairrail-erd.ddl.sql` + `docs/FairRail_ERD.md`를 같은 커밋에. `node tools/check-erd.js` FAIL 0 확인 후 커밋.
8. **트러블슈팅은 고친 커밋과 같이**: 버그를 잡았으면 그 커밋(또는 바로 다음 `docs` 커밋)에 `docs/본인이름/troubleshooting/` 문서를 추가하고 꼬리말에 경로를 적습니다. 수치가 아직 없으면 "수치" 칸을 `측정 예정`으로 두고 나중에 채웁니다.

## 3. 브랜치

각자 자기 이름 브랜치에서 작업하고 PR로 main에 합치는 것이 원칙입니다. GitHub에서 main 직접 push를 막아 두지는 않으므로, 규칙으로 지킵니다.

| 브랜치 | 주인 |
|---|---|
| `main` | 합쳐진 결과 |
| `SeongWon` | A 김성원 |
| `DongGyun` | B 강동균 |
| `DongHyeon` | C 길동현 |
| `DaIn` | D 강다인 |
| `YoungJun` | E 조영준 |

브랜치 이름은 성을 뺀 이름만 영문 대소문자로 씁니다. (표기는 각자 평소 쓰는 영문 이름으로 확인 후 확정)

1. 브랜치는 **사람당 하나**만 쓰고 계속 재사용합니다. 기능별 브랜치를 따로 만들지 않습니다.
2. 작업 시작 전 최신 main을 내 브랜치로 가져옵니다: `git pull origin main`
3. 합칠 때는 내 브랜치 → main으로 PR을 열고, 팀원 1명 이상 확인 후 머지합니다 (CI가 생기면 CI 통과도 조건).
4. 머지 방식은 두 가지를 같이 씁니다.
   - **Squash**: PR 안 커밋이 `wip`, `오타 수정`처럼 자잘하면 하나로 합쳐서 머지. PR 제목을 커밋 규칙 형식으로 맞출 것
   - **일반 Merge**: 커밋 하나하나가 의미 있을 때 (트러블슈팅 문서에서 커밋을 링크했거나, 락 방식 비교처럼 단계별 기록을 남겨야 할 때)
   - 헷갈리면 Squash
5. 오래 안 합치면 충돌이 커지므로 **최소 2~3일에 한 번**은 main에 합칩니다.
6. 남의 브랜치에는 push하지 않습니다.
