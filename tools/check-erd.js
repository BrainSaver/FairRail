#!/usr/bin/env node
/*
 * FairRail ERD 검사 스크립트
 * 사용법: node tools/check-erd.js docs/erd/fairrail-erd.html [비교할 명세.md ...]
 *  - FAIL이 하나라도 있으면 종료 코드 1
 *  - md 파일을 주면 "### `테이블명`" 아래 표의 첫 열(컬럼명)을 편집기 스키마와 비교
 */
const fs = require('fs');
const [, , htmlPath, ...mdPaths] = process.argv;
if (!htmlPath) { console.error('사용법: node tools/check-erd.js <fairrail-erd.html> [spec.md ...]'); process.exit(2); }
const html = fs.readFileSync(htmlPath, 'utf8');
const src = html.slice(html.indexOf('<script>') + 8, html.lastIndexOf('</script>'));
const cut = (a, b) => { const i = src.indexOf(a), j = src.indexOf(b, i); if (i < 0 || j < 0) throw new Error(`구간을 찾을 수 없음: ${a} ~ ${b}`); return src.slice(i, j); };

// 편집기 스크립트에서 DOM과 무관한 부분만 잘라 실행
const core = cut('const GROUPS', 'function autoLayout') +
  cut('function targetRowIndex', 'const visible') +
  cut('function sqlStr', 'function exportDDL') + cut('function exportDDL', 'function mdEsc');
const api = new Function(`const document={querySelector:()=>null};
${core}
return {GROUPS,SEED,PATCHES,SEED_VERSION,LAYOUT,DOCS,DECISIONS_SEED,convTable,fromSeedBase,applyPatch,applyPatches,fromSeed,
  setTables:v=>{tables=v}, exportDDL, enumOf, cname, compositeFks, notesIndexes, uniqueGroups};`)();

const res = { FAIL: [], WARN: [], PASS: [] };
const fail = m => res.FAIL.push(m), warn = m => res.WARN.push(m), pass = m => res.PASS.push(m);
const T = api.fromSeed(); const by = Object.fromEntries(T.map(t => [t.id, t]));
const dbOf = t => t.db || api.GROUPS[t.g]?.db || 'Oracle';
const hasK = (c, k) => c.keys.split(',').includes(k);
const base = s => (s || '').replace(/\(.*$/, '').trim();
const RESERVED = new Set('ACCESS ADD ALL ALTER AND ANY AS ASC AUDIT BETWEEN BY CHAR CHECK CLUSTER COLUMN COMMENT COMPRESS CONNECT CREATE CURRENT DATE DECIMAL DEFAULT DELETE DESC DISTINCT DROP ELSE EXCLUSIVE EXISTS FILE FLOAT FOR FROM GRANT GROUP HAVING IDENTIFIED IMMEDIATE IN INCREMENT INDEX INITIAL INSERT INTEGER INTERSECT INTO IS LEVEL LIKE LOCK LONG MAXEXTENTS MINUS MLSLABEL MODE MODIFY NOAUDIT NOCOMPRESS NOT NOWAIT NULL NUMBER OF OFFLINE ON ONLINE OPTION OR ORDER PCTFREE PRIOR PUBLIC RAW RENAME RESOURCE REVOKE ROW ROWID ROWNUM ROWS SELECT SESSION SET SHARE SIZE SMALLINT START SUCCESSFUL SYNONYM SYSDATE TABLE THEN TO TRIGGER UID UNION UNIQUE UPDATE USER VALIDATE VALUES VARCHAR VARCHAR2 VIEW WHENEVER WHERE WITH'.split(' '));
// FK를 일부러 걸지 않는 ID 컬럼 (외부 값, 다형 참조, 묶음 번호)
const NO_FK_OK = new Set(['reservation_history.event_id', 'payment.pg_tx_id', 'cancellation.refund_pg_tx_id', 'outbox_event.aggregate_id',
  'notification.ref_id', 'synthetic_label.group_id', 'member_credential.pepper_key_id', 'auth_session.token_family_id',
  'ext_bot_detection.session_id', 'admin_user.login_id', 'member.enc_key_id', 'purchase_counter.scope_ref_id']);
// 값이 열려 있어 CHECK를 걸지 않는 코드성 컬럼
const NO_CHECK_OK = new Set(['outbox_event.event_type', 'notification.type', 'ext_dataset.license', 'reservation_history.event_id', 'model_run.train_source', 'reservation_history.from_status' /* 비고의 CHECK로 처리 */]);
const STATUSY = /(^|_)(status|type|result|role|scope|action|channel|source|severity|verdict|step|mode|algorithm|provider|platform)$/;

// 1. 테이블·컬럼 구조
const ids = new Set();
T.forEach(t => {
  if (ids.has(t.id)) fail(`테이블 이름 중복: ${t.id}`); ids.add(t.id);
  if (!api.GROUPS[t.g]) fail(`${t.id}: 없는 영역 ${t.g}`);
  const ora = dbOf(t) === 'Oracle';
  if (ora && !t.cols.some(c => hasK(c, 'PK'))) fail(`${t.id}: Oracle 테이블인데 PK 없음`);
  if (ora && t.id.length > 30) warn(`${t.id}: 테이블 이름 30자 초과`);
  if (ora && RESERVED.has(t.id.toUpperCase())) fail(`${t.id}: Oracle 예약어 테이블 이름`);
  const names = new Set();
  const compCols = new Set(api.compositeFks(t).flatMap(f => f.cols));
  t.cols.forEach(c => {
    const key = `${t.id}.${c.name}`;
    if (ora && !t.planned && STATUSY.test(c.name) && !api.enumOf(c) && !NO_CHECK_OK.has(key)) warn(`코드 컬럼인데 CHECK가 없음 (설명을 "A / B" 형식으로 쓰거나 NO_CHECK_OK에 추가): ${key}`);
    if (names.has(c.name)) fail(`컬럼 중복: ${key}`); names.add(c.name);
    if (ora && RESERVED.has(c.name.toUpperCase())) fail(`Oracle 예약어 컬럼: ${key}`);
    if (ora && c.name.length > 30) fail(`Oracle 컬럼 이름 30자 초과: ${key}`);
    if (!c.type) warn(`타입 없음: ${key}`);
    if (c.fk) {
      const tg = by[c.fk];
      if (!tg) { fail(`FK 대상 없음: ${key} → ${c.fk}`); return; }
      if (!hasK(c, 'FK')) fail(`FK 대상은 있는데 FK 키 표시 없음: ${key}`);
      const tc = tg.cols.find(x => hasK(x, 'PK') && x.name === c.name) || tg.cols.find(x => hasK(x, 'PK'));
      if (!tc) fail(`FK 대상 테이블에 PK 없음: ${key} → ${tg.id}`);
      else if (ora && dbOf(tg) === 'Oracle' && base(tc.type) !== base(c.type)) fail(`FK 타입 불일치: ${key} ${c.type} → ${tg.id}.${tc.name} ${tc.type}`);
      if (tg.planned && !t.planned) warn(`운영 테이블이 확장 예정 테이블을 참조: ${key} → ${tg.id}`);
    } else if (hasK(c, 'FK')) fail(`FK 표시만 있고 대상 없음: ${key}`);
    else if (/(_id|_by)$/.test(c.name) && !hasK(c, 'PK') && !NO_FK_OK.has(key) && !compCols.has(c.name)) warn(`FK 없는 ID 컬럼 (의도라면 NO_FK_OK에 추가): ${key}`);
  });
  // 예시 데이터
  (t.samples || []).forEach((r, i) => Object.entries(r).forEach(([k, v]) => {
    const c = t.cols.find(x => x.name === k);
    if (!c) { fail(`${t.id} 예시 ${i + 1}행: 없는 컬럼 ${k}`); return; }
    const e = api.enumOf(c); if (e && v != null && !e.includes(String(v))) fail(`${t.id} 예시 ${i + 1}행: ${k}=${v} 는 허용값(${e.join('/')}) 밖`);
    if (c.fk && v != null && by[c.fk]?.samples?.length) {
      const tc = by[c.fk].cols.find(x => hasK(x, 'PK'));
      if (!by[c.fk].samples.some(s => s[tc.name] === v)) fail(`${t.id} 예시 ${i + 1}행: ${k}=${v} 가 ${c.fk} 예시에 없음`);
    }
    if (hasK(c, 'PK') && v == null) fail(`${t.id} 예시 ${i + 1}행: PK ${k}가 null`);
  }));
  // NOT NULL 컬럼이 예시 행에 빠지면 DDL의 INSERT가 실패함
  if (ora && !t.planned) (t.samples || []).forEach((r, i) => t.cols.forEach(c => {
    if ((hasK(c, 'NN') || hasK(c, 'PK')) && r[c.name] == null) fail(`${t.id} 예시 ${i + 1}행: NOT NULL 컬럼 ${c.name} 값 없음 (INSERT 실패)`);
  }));
});
// 비고의 복합 FK: 컬럼 존재, 타입 일치, 참조 대상에 같은 조합의 PK/UNIQUE
T.forEach(t => api.compositeFks(t).forEach(f => {
  const tag = `${t.id} FK(${f.cols.join(', ')}) → ${f.ref}(${f.refCols.join(', ')})`;
  const tg = by[f.ref]; if (!tg) { fail(`${tag}: 대상 테이블 없음`); return; }
  if (f.cols.length !== f.refCols.length) { fail(`${tag}: 컬럼 수가 다름`); return; }
  f.cols.forEach((n, i) => { const a = t.cols.find(c => c.name === n), b = tg.cols.find(c => c.name === f.refCols[i]);
    if (!a) fail(`${tag}: 없는 컬럼 ${n}`); else if (!b) fail(`${tag}: 대상에 없는 컬럼 ${f.refCols[i]}`);
    else if (base(a.type) !== base(b.type)) fail(`${tag}: 타입 불일치 ${n} ${a.type} vs ${b.type}`); });
  const pk = tg.cols.filter(c => hasK(c, 'PK')).map(c => c.name), groups = [pk, ...api.uniqueGroups(tg)];
  if (!groups.some(g => g.join(',') === f.refCols.join(','))) fail(`${tag}: 대상에 같은 컬럼·순서의 PK/UNIQUE가 없음 (Oracle 복합 FK 조건)`);
}));
// 비고의 CREATE INDEX: 대상 테이블과 컬럼 확인
T.forEach(t => api.notesIndexes(t).forEach(x => {
  const m = x.match(/^CREATE (?:UNIQUE )?INDEX (\w+) ON (\w+) \((.+)\)$/); if (!m) { fail(`${t.id} 비고 인덱스 형식 오류: ${x}`); return; }
  if (m[2] !== t.id) fail(`${t.id} 비고 인덱스가 다른 테이블을 가리킴: ${x}`);
  (m[3].match(/\b[a-z_][a-z0-9_]*\b/g) || []).filter(w => !/^(case|when|then|end|in|and|or|null|is|not)$/.test(w)).forEach(w => { if (!t.cols.some(c => c.name === w) && !['created_at', 'updated_at'].includes(w)) fail(`${t.id} 비고 인덱스에 없는 컬럼 ${w}`); });
}));
// notes의 UNIQUE(...) 컬럼 존재 확인
T.forEach(t => (t.notes || '').replace(/UNIQUE\(([^)]+)\)/g, (m, g) => {
  g.split(',').map(s => s.trim()).forEach(n => { if (!t.cols.some(c => c.name === n)) fail(`${t.id} 비고 ${m}: 없는 컬럼 ${n}`); });
}));
if (!res.FAIL.length) pass(`구조: 테이블 ${T.length}, 컬럼 ${T.reduce((s, t) => s + t.cols.length, 0)}, 관계 ${T.reduce((s, t) => s + t.cols.filter(c => c.fk).length, 0)}`);

// 2. 배치
const lay = api.LAYOUT.flat();
lay.forEach(id => { if (!by[id]) fail(`LAYOUT에 없는 테이블: ${id}`); });
T.forEach(t => { if (!lay.includes(t.id)) warn(`LAYOUT에 빠진 테이블 (오른쪽 끝에 배치됨): ${t.id}`); });
if (new Set(lay).size !== lay.length) fail('LAYOUT에 같은 테이블이 두 번 있음');

// 3. 패치 멱등성·마이그레이션
const strip = list => JSON.stringify(list.map(t => ({ ...t, x: 0, y: 0 })).sort((a, b) => a.id.localeCompare(b.id)));
const fresh = strip(api.fromSeed());
if (strip(api.applyPatches(api.fromSeed(), 2)) !== fresh) fail('패치가 멱등이 아님 (두 번 적용하면 결과가 달라짐)');
else pass('패치 멱등성');
api.PATCHES.forEach(p => {
  const at = api.fromSeedBase(); api.PATCHES.filter(x => x.v <= p.v).forEach(x => api.applyPatch(at, x));
  if (strip(api.applyPatches(at, p.v)) !== fresh) fail(`v${p.v}에 저장된 브라우저가 최신과 다르게 마이그레이션됨`);
});
if (!res.FAIL.some(m => m.includes('마이그레이션'))) pass(`마이그레이션 v2~v${api.SEED_VERSION-1} → v${api.SEED_VERSION} 결과가 새로 연 편집기와 동일`);
const vers = api.PATCHES.map(p => p.v); if (vers.some((v, i) => i && v <= vers[i - 1])) fail('PATCHES 버전이 오름차순이 아님');

// 4. DDL
api.setTables(api.fromSeed());
const ddl = api.exportDDL();
if (/undefined/.test(ddl)) fail('DDL에 undefined가 들어감');
const cons = [...ddl.matchAll(/(?:CONSTRAINT|INDEX) (\w+)/g)].map(m => m[1]);
cons.filter(n => n.length > 30).forEach(n => fail(`제약·인덱스 이름 30자 초과: ${n}`));
const dupC = cons.filter((n, i) => cons.indexOf(n) !== i); if (dupC.length) fail(`제약·인덱스 이름 중복: ${[...new Set(dupC)].join(', ')}`);
if (/^-- 경고/m.test(ddl)) fail(ddl.split('\n').find(l => l.startsWith('-- 경고')));
fs.writeFileSync(htmlPath.replace(/\.html$/, '') + '.ddl.sql', ddl);
pass(`DDL: CREATE TABLE ${(ddl.match(/CREATE TABLE/g) || []).length}, FK ${(ddl.match(/FOREIGN KEY/g) || []).length}, CHECK ${(ddl.match(/CHECK \(/g) || []).length}, 인덱스 ${(ddl.match(/CREATE (UNIQUE )?INDEX/g) || []).length}, INSERT ${(ddl.match(/INSERT INTO/g) || []).length} → ${htmlPath.replace(/\.html$/, '')}.ddl.sql`);

// 5. 문서 참조
const allCols = new Set(T.flatMap(t => t.cols.map(c => c.name)));
const docText = Object.values(api.DOCS).flatMap(d => d.rows.flat()).concat(api.DECISIONS_SEED.map(d => d.where)).join(' ');
const unknown = [...new Set((docText.match(/\b[a-z][a-z0-9]*(?:_[a-z0-9]+)+\b/g) || []))].filter(w => !by[w] && !allCols.has(w) && !/^(ext|ci|ip)$/.test(w));
const knownWords = new Set((by.app_policy?.samples || []).flatMap(r => String(r.policy_key).split('.')));
unknown.filter(w => !knownWords.has(w)).forEach(w => warn(`문서에 나오지만 테이블·컬럼이 아닌 이름: ${w}`));
api.DECISIONS_SEED.forEach(d => { const m = d.where.match(/^([a-z_]+)/); if (m && m[1].includes('_') && !by[m[1]]) fail(`결정 사항 반영 위치의 테이블 없음: ${d.where}`); });

// 6. md 명세 비교
mdPaths.forEach(mp => {
  const md = fs.readFileSync(mp, 'utf8').split('\n'); let cur = null; const found = {};
  md.forEach(line => {
    const h = line.match(/^#{2,4} .*?`([a-z0-9_]+)`/); if (h) { cur = h[1]; found[cur] = found[cur] || []; return; }
    if (/^#{1,4} /.test(line)) { cur = null; return; }
    if (cur && /^\| /.test(line) && !/^\| (컬럼|필드|키|---)/.test(line)) {
      const cell = line.split('|')[1].trim().replace(/`/g, '');
      if (!cell || /^-+$/.test(cell)) return;
      cell.split(/\s*\/\s*|\s*,\s*/).forEach(part => {
        const nm = part.trim();
        if (/^[a-z_][a-z0-9_]*$/.test(nm)) found[cur].push(nm);
        else if (/^[a-z_]+:/.test(nm) && cur === 'redis_keys') found[cur].push(nm);
      });
    }
  });
  const missT = [], missC = [];
  Object.entries(found).forEach(([tid, cols]) => {
    if (!by[tid]) { missT.push(tid); return; }
    const have = new Set(by[tid].cols.map(c => c.name));
    const prefix = cols.length && cols.every(c => /^(arrival_date_year|month|day_of_month)$/.test(c)) ? [] : cols;
    prefix.forEach(c => {
      if (have.has(c)) return;
      if (/^(month|day_of_month)$/.test(c) && have.has('arrival_date_' + c)) return; // arrival_date_year / month / day_of_month 표기
      missC.push(`${tid}.${c}`);
    });
  });
  const name = mp.split('/').pop();
  if (missT.length) warn(`[${name}] 편집기에 없는 테이블: ${missT.join(', ')}`);
  if (missC.length) warn(`[${name}] 편집기에 없는 컬럼: ${missC.join(', ')}`);
  pass(`[${name}] 테이블 ${Object.keys(found).length}개 비교, 차이 테이블 ${missT.length} · 컬럼 ${missC.length}`);
});

['FAIL', 'WARN', 'PASS'].forEach(k => { if (res[k].length) { console.log(`\n${k} (${res[k].length})`); res[k].forEach(m => console.log('  - ' + m)); } });
process.exit(res.FAIL.length ? 1 : 0);
