#!/usr/bin/env node
/*
 * ERD 편집기 HTML에서 종합 ERD 문서(Markdown)를 만든다.
 * 사용법: node tools/erd-md.js docs/erd/fairrail-erd.html > docs/FairRail_ERD.md
 * 영역별 Mermaid 관계도 + 전체 테이블 명세 + 결정 사항 + 설계 문서 + 참고 자료
 */
const fs = require('fs');
const htmlPath = process.argv[2];
if (!htmlPath) { console.error('사용법: node tools/erd-md.js <fairrail-erd.html>'); process.exit(2); }
const html = fs.readFileSync(htmlPath, 'utf8');
const src = html.slice(html.indexOf('<script>') + 8, html.lastIndexOf('</script>'));
const cut = (a, b) => { const i = src.indexOf(a); return src.slice(i, src.indexOf(b, i)); };
const api = new Function(`const document={querySelector:()=>null};
${cut('const GROUPS', 'function autoLayout')}${cut('function enumOf', 'function uniqueGroups')}
return {GROUPS, DOCS, DECISIONS_SEED, SEED_VERSION, fromSeed, enumOf};`)();

const T = api.fromSeed(), by = Object.fromEntries(T.map(t => [t.id, t]));
const dbOf = t => t.db || api.GROUPS[t.g]?.db || 'Oracle';
const hasK = (c, k) => c.keys.split(',').includes(k);
const esc = s => String(s ?? '').replace(/\|/g, '\\|').replace(/\n/g, ' ');
const table = (head, rows) => ['| ' + head.join(' | ') + ' |', '|' + head.map(() => '---').join('|') + '|', ...rows.map(r => '| ' + r.map(esc).join(' | ') + ' |')].join('\n');
const links = T.flatMap(t => t.cols.filter(c => c.fk && by[c.fk]).map(c => ({ from: t, col: c, to: by[c.fk] })));
const anchor = id => id.replace(/_/g, '-');
const tlink = id => `[\`${id}\`](#${anchor(id)})`;
const L = [];
const out = (...x) => L.push(...x);

const groups = Object.entries(api.GROUPS).filter(([k]) => T.some(t => t.g === k));
const nOra = T.filter(t => dbOf(t) === 'Oracle' && !t.planned).length, nMongo = T.filter(t => dbOf(t) === 'MongoDB').length, nRedis = T.filter(t => dbOf(t) === 'Redis').length;

out('# FairRail 종합 ERD', '',
  '명절 열차 공정 예매 시스템의 전체 데이터 구조입니다. 짧은 시간에 몰리는 예매 트래픽을 대기열로 제어하고, 좌석을 중복 없이 공정한 순서로 판매하며, 되팔이·반복 취소가 의심되는 이용자를 행동 데이터로 찾아 대기 순번을 뒤로 미루고 CCTV처럼 되돌아볼 수 있게 하는 데 필요한 테이블을 모았습니다.', '',
  `> 스키마 v${api.SEED_VERSION} · ERD 편집기(\`docs/erd/fairrail-erd.html\`)에서 생성 · 생성일 ${new Date().toISOString().slice(0, 10)}`,
  '> 이 문서는 편집기에서 자동 생성됩니다. 내용을 바꾸려면 편집기 HTML을 고친 뒤 `node tools/erd-md.js`로 다시 만드세요.', '> 예매·결제·취소·이벤트 발행의 트랜잭션 순서와 SQL은 [동시성 절차](concurrency.md)에 있습니다. 비고의 `§` 번호가 그 문서의 절입니다.', '');

out('## 목차', '', '1. [한눈에 보기](#한눈에-보기)', '2. [팀 결정 사항](#팀-결정-사항)', '3. [공통 규칙](#공통-규칙)', '4. [흐름](#흐름)', '5. [영역별 테이블](#영역별-테이블)');
groups.forEach(([k, g], i) => out(`   ${i + 1}. [${g.name}](#${anchor('g-' + k)})`));
out('6. [기능 추적표](#기능-추적표)', '7. [실패 시나리오](#실패-시나리오)', '8. [가상 데이터 생성](#가상-데이터-생성)', '9. [확장 계획](#확장-계획)', '10. [변경 이력](#변경-이력)', '11. [참고 자료](#참고-자료)', '');

out('## 한눈에 보기', '',
  table(['항목', '값'], [
    ['테이블', `${T.length}개 (운영 ${T.length - T.filter(t => t.planned).length} + 확장 예정 ${T.filter(t => t.planned).length})`],
    ['저장소', `Oracle ${nOra} · MongoDB ${nMongo} · Redis ${nRedis}${T.some(t => t.planned) ? ` · 확장 예정 ${T.filter(t => t.planned).length}` : ''}`],
    ['빅데이터 (대량 적재)', `${T.filter(t => t.big).length}개`],
    ['컬럼', `${T.reduce((s, t) => s + t.cols.length, 0)}개`],
    ['관계 (FK)', `${links.length}개 (Oracle 제약 ${links.filter(l => dbOf(l.from) === 'Oracle' && dbOf(l.to) === 'Oracle' && !l.from.planned && !l.to.planned).length} · 논리 참조 ${links.filter(l => dbOf(l.from) !== 'Oracle' || dbOf(l.to) !== 'Oracle').length})`],
  ]), '',
  table(['영역', '저장소', '테이블'], groups.map(([k, g]) => [g.name, [...new Set(T.filter(t => t.g === k).map(dbOf))].join(', '), T.filter(t => t.g === k).map(t => `\`${t.id}\`${t.planned ? '(확장)' : ''}`).join(', ')])), '',
  '표기: **PK** 기본키 · **FK** 외래키 · **UQ** 유니크 · **NN** NOT NULL · 🅱 빅데이터 · ┄ 확장 예정 (DDL 제외) · MongoDB 쪽 FK는 DB 제약이 없는 논리 참조입니다.', '');

out('## 팀 결정 사항', '', '팀이 확정하기 전까지 쓰는 **예시값**입니다. 확정되면 편집기 "문서 → 팀 결정 사항"에서 상태를 바꾸세요.', '',
  table(['항목', '값', '반영 위치', '근거', '상태'], api.DECISIONS_SEED.map(d => [d.item, d.value, d.where, d.reason, d.status])), '');
const D = api.DOCS;
out('## 공통 규칙', '', table(D.rules.head, D.rules.rows), '');
out('## 흐름', '', table(D.flows.head, D.flows.rows), '');

out('## 영역별 테이블', '');
const mType = t => (t || 'X').replace(/\(.*$/, '').replace(/[^A-Za-z0-9_]/g, '') || 'X';
groups.forEach(([k, g]) => {
  const ts = T.filter(t => t.g === k);
  out(`<a id="${anchor('g-' + k)}"></a>`, `### ${g.name}`, '');
  // Mermaid: 이 영역 테이블 + 직접 연결된 바깥 테이블
  const rel = links.filter(l => l.from.g === k || l.to.g === k);
  if (k !== 'redis' && rel.length) {
    const ext = [...new Set(rel.flatMap(l => [l.from, l.to]).filter(t => t.g !== k).map(t => t.id))];
    out('```mermaid', 'erDiagram');
    ts.forEach(t => {
      const keyCols = t.cols.filter(c => hasK(c, 'PK') || hasK(c, 'FK'));
      out(`  ${t.id} {`);
      keyCols.forEach(c => out(`    ${mType(c.type)} ${c.name} ${['PK', 'FK'].filter(x => hasK(c, x)).join(', ')}`));
      if (!keyCols.length) out(`    ${mType(t.cols[0]?.type)} ${t.cols[0]?.name || 'id'}`);
      out('  }');
    });
    ext.forEach(id => out(`  ${id} {`, `    ${mType(by[id].cols.find(c => hasK(c, 'PK'))?.type)} ${by[id].cols.find(c => hasK(c, 'PK'))?.name || by[id].cols[0].name} PK`, '  }'));
    rel.forEach(l => out(`  ${l.to.id} ${hasK(l.col, 'NN') || hasK(l.col, 'PK') ? '||' : '|o'}--o{ ${l.from.id} : "${l.col.name}"`));
    out('```', '');
  }
  ts.forEach(t => {
    const tags = [dbOf(t), t.big ? '🅱 빅데이터' : '', t.planned ? '┄ 확장 예정' : '', t.noUpdatedAt ? 'updated_at 생략' : '', t.refOnly ? '참조 전용(행 삭제 없음)' : ''].filter(Boolean).join(' · ');
    out(`<a id="${anchor(t.id)}"></a>`, `#### \`${t.id}\` ${t.ko || ''}`, '', `${tags}`, '');
    if (t.desc) out(t.desc, '');
    out(table(['컬럼', '타입', '키', '출처', '설명', '이유'], t.cols.map(c => {
      const ks = c.keys.split(',').filter(Boolean).join(', ');
      return [`\`${c.name}\``, c.type, ks + (c.fk ? ` → ${c.fk}` : ''), c.src, c.desc, c.reason];
    })), '');
    if (t.notes) out(`> **제약·비고** ${t.notes}`, '');
    const o = links.filter(l => l.from === t), i = links.filter(l => l.to === t && l.from !== t);
    if (o.length || i.length) out(`**관계** ${[...o.map(l => `${l.col.name} → ${tlink(l.to.id)}`), ...i.map(l => `${tlink(l.from.id)}.${l.col.name} → 이 테이블`)].join(' · ')}`, '');
    if ((t.samples || []).length) { const ks = [...new Set(t.samples.flatMap(r => Object.keys(r)))]; out('**예시 데이터** (팀 확정 전 예시값)', '', table(ks, t.samples.map(r => ks.map(x => r[x] == null ? 'null' : r[x]))), ''); }
  });
});

out('## 기능 추적표', '', table(D.trace.head, D.trace.rows), '');
out('## 실패 시나리오', '', table(D.scenarios.head, D.scenarios.rows), '');
out('## 가상 데이터 생성', '', '실제 예매 행동 데이터는 개인정보라 공개되지 않으므로, 공개 데이터로 패턴을 검증한 뒤 그 패턴을 반영해 가상 데이터를 생성합니다.', '', table(D.gen.head, D.gen.rows), '');
out('## 확장 계획', '', table(D.extension.head, D.extension.rows), '');
out('## 변경 이력', '', table(D.history.head, D.history.rows), '');

out('## 참고 자료', '',
  '**공공데이터포털 (기준 데이터)**',
  '- 한국철도공사_차세대예약발매_차량유형코드: https://www.data.go.kr/data/15137680/fileData.do',
  '- 한국철도공사_철도운행거리_전체: https://www.data.go.kr/data/15137040/fileData.do',
  '- 한국철도공사_KTX 노선별 역정보: https://www.data.go.kr/dcat/metadata/15127571',
  '- 한국철도공사 역간 최단 운행거리: https://www.data.go.kr/dcat/metadata/15153835',
  '- 한국철도공사 간선 철도역 위치정보: https://www.data.go.kr/dcat/metadata/15127532',
  '- 한국철도공사_공통기준 역상세 정보: https://www.data.go.kr/data/15153852/fileData.do',
  '- 한국철도공사 역별 키로정: https://www.data.go.kr/dcat/metadata/15153841',
  '- 한국철도공사 세그먼트 구간 정보: https://www.data.go.kr/dcat/metadata/15153579',
  '- 한국철도공사 역무열차종별 코드: https://www.data.go.kr/dcat/metadata/15154143', '',
  '**외부 데이터셋 (빅데이터)**',
  '- Kaggle, Hotel Booking Demand: https://www.kaggle.com/datasets/jessemostipak/hotel-booking-demand',
  '- Kaggle, Web Server Access Logs 활용 예: https://github.com/zaki1003/bot-detection-prototype',
  '- Iliou et al., Web Bot Detection Dataset, Bournemouth University (2020): https://bordar.bournemouth.ac.uk/272/',
  '- Kaggle, Spanish High Speed Rail Tickets Pricing (Renfe): https://www.kaggle.com/thegurusteam/spanish-high-speed-rail-system-ticket-pricing', '',
  '**보안**',
  '- OWASP Password Storage Cheat Sheet: https://cheatsheetseries.owasp.org/cheatsheets/Password_Storage_Cheat_Sheet.html',
  '- Argon2id 파라미터·PHC 형식: https://rubydoc.info/gems/argon2id/file/README.md',
  '- Argon2 vs bcrypt: https://mojoauth.com/security-guides/bcrypt-vs-argon2',
  '- Spring Security 비밀번호 저장: https://docs.spring.io/spring-security/reference/features/authentication/password-storage.html', '',
  '**MongoDB·CCTV 되돌아보기**',
  '- MongoDB Time Series Collections: https://www.mongodb.com/docs/current/core/timeseries-collections/',
  '- MongoDB 시계열 metaField 카디널리티: https://oneuptime.com/blog/post/2026-03-31-mongodb-time-series-metafields/view',
  '- MongoDB GridFS (문서 16MB 한도): https://www.mongodb.com/docs/upcoming/core/gridfs/',
  '- rrweb (DOM 녹화, 확장 시 참고): https://github.com/rrweb-io/rrweb/blob/main/guide.md', '',
  '**Oracle**',
  '- Oracle SQL Reserved Words (19c): https://docs.oracle.com/en/database/oracle/oracle-database/19/sqlrf/Oracle-SQL-Reserved-Words.html', '',
  '**기획 배경**',
  '- 세계일보, 「추석 기차표, 언제 예매하지?」 (2026.08.29): https://www.segye.com/newsView/20260829505201',
  '- 쿠키뉴스, 「설 승차권 암표 거래 절대 안 돼」 (2026.02.09): https://www.kukinews.com/article/view/kuk202602090043',
  '- 헤럴드경제, 「작년 명절 노쇼 기차표 5년 새 5.3배 급증」 (2026.02.11): https://www.heraldk.com/article/2026021119093519927');
console.log(L.join('\n'));
