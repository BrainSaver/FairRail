#!/usr/bin/env node
/*
 * 편집기에서 내보낸 JSON과 HTML 안의 기본 스키마를 비교해 다음 버전 패치 코드를 만든다.
 * 사용법: node tools/erd-diff.js docs/erd/fairrail-erd.html docs/erd/erd-export.json > patch.txt
 * 출력된 V{n}_TABLES / V{n}_OPS를 HTML의 PATCHES 바로 위에 붙이고
 * PATCHES 배열에 {v:n, tables:V{n}_TABLES, ops:V{n}_OPS}를 추가한다. (자세한 절차는 CLAUDE.md)
 */
const fs = require('fs');
const [, , htmlPath, jsonPath] = process.argv;
if (!htmlPath || !jsonPath) { console.error('사용법: node tools/erd-diff.js <fairrail-erd.html> <erd-export.json>'); process.exit(2); }
const html = fs.readFileSync(htmlPath, 'utf8');
const src = html.slice(html.indexOf('<script>') + 8, html.lastIndexOf('</script>'));
const cut = (a, b) => { const i = src.indexOf(a), j = src.indexOf(b, i); return src.slice(i, j); };
const api = new Function(`const document={querySelector:()=>null};
${cut('const GROUPS', 'function autoLayout')}${cut('function enumOf', 'function uniqueGroups')}
return {fromSeed, SEED_VERSION, DECISIONS_SEED, LAYOUT};`)();

const exp = JSON.parse(fs.readFileSync(jsonPath, 'utf8'));
const E = Array.isArray(exp) ? exp : exp.tables;
const B = api.fromSeed();
const v = api.SEED_VERSION + 1;
const byB = Object.fromEntries(B.map(t => [t.id, t])), byE = Object.fromEntries(E.map(t => [t.id, t]));
const tuple = c => { const a = [c.name, c.type || '', c.keys || '', c.src || '', c.desc || '', c.reason || '']; if (c.fk) a.push(c.fk); return a; };
const newTables = [], ops = [], notes = [];
const J = x => JSON.stringify(x);

E.forEach(t => {
  const b = byB[t.id];
  if (!b) {
    const o = { id: t.id, ko: t.ko || '', g: t.g, desc: t.desc || '', notes: t.notes || '', cols: t.cols.map(tuple) };
    if (t.db) o.db = t.db; if (t.big) o.big = true; if (t.planned) o.planned = true; if (t.noUpdatedAt) o.noUpdatedAt = true; if (t.refOnly) o.refOnly = true; if ((t.samples || []).length) o.samples = t.samples;
    newTables.push(o); return;
  }
  const prop = {};
  ['ko', 'g', 'db', 'big', 'planned', 'noUpdatedAt', 'refOnly'].forEach(k => { const a = b[k] ?? (k === 'db' ? '' : k === 'ko' ? '' : false), c = t[k] ?? (k === 'db' ? '' : k === 'ko' ? '' : false); if (J(a) !== J(c)) prop[k] = c; });
  if (J(b.samples || []) !== J(t.samples || [])) prop.samples = t.samples || [];
  if (Object.keys(prop).length) ops.push(['prop', t.id, prop]);
  if ((b.desc || '') !== (t.desc || '')) ops.push(['desc', t.id, t.desc || '']);
  if ((b.notes || '') !== (t.notes || '')) ops.push(['notes', t.id, t.notes || '']);
  const bn = new Set(b.cols.map(c => c.name)), en = new Set(t.cols.map(c => c.name));
  b.cols.filter(c => !en.has(c.name)).forEach(c => ops.push(['del', t.id, c.name]));
  let prev = null, pending = [], pendingAfter = null;
  const flush = () => { if (pending.length) { ops.push(['add', t.id, pendingAfter, pending]); pending = []; } };
  t.cols.forEach(c => {
    if (!bn.has(c.name)) { if (!pending.length) pendingAfter = prev; pending.push(tuple(c)); }
    else {
      flush();
      const bc = b.cols.find(x => x.name === c.name), ch = {};
      ['type', 'keys', 'src', 'desc', 'reason', 'fk'].forEach(k => { if ((bc[k] || '') !== (c[k] || '')) ch[k] = c[k] || ''; });
      if (Object.keys(ch).length) ops.push(['set', t.id, c.name, ch]);
    }
    prev = c.name;
  });
  flush();
  const order = t.cols.map(c => c.name).filter(n => bn.has(n)), border = b.cols.map(c => c.name).filter(n => en.has(n));
  if (J(order) !== J(border)) notes.push(`${t.id}: 기존 컬럼 순서가 바뀜 (패치는 순서를 옮기지 않음. 필요하면 del 후 add로 처리)`);
});
B.filter(t => !byE[t.id]).forEach(t => ops.push(['droptable', t.id]));
const renamed = ops.filter(o => o[0] === 'del').map(o => `${o[1]}.${o[2]}`);
if (renamed.length) notes.push(`삭제로 잡힌 컬럼 (이름 변경이었다면 그 컬럼의 기존 데이터·FK 확인): ${renamed.join(', ')}`);
if (exp.decisions && J(exp.decisions) !== J(api.DECISIONS_SEED)) notes.push('결정 사항이 기본값과 다름 → 팀이 확정한 값이면 DECISIONS_SEED를 이 JSON의 decisions로 교체');
const lay = new Set(api.LAYOUT.flat());
newTables.forEach(t => { if (!lay.has(t.id)) notes.push(`새 테이블 ${t.id}: LAYOUT의 알맞은 열에 추가`); });

if (!newTables.length && !ops.length) { console.log('// 차이 없음: 편집기 JSON과 HTML 기본 스키마가 같습니다.'); notes.forEach(n => console.log('// 참고: ' + n)); process.exit(0); }
const fmt = x => JSON.stringify(x).replace(/"([a-z_]+)":/g, '$1:');
console.log(`// ===== 스키마 v${v} 패치 (tools/erd-diff.js 생성: ${new Date().toISOString().slice(0, 10)}) =====`);
console.log(`const V${v}_TABLES = [\n${newTables.map(t => ' ' + fmt(t)).join(',\n')}\n];`);
console.log(`const V${v}_OPS = [\n${ops.map(o => ' ' + JSON.stringify(o)).join(',\n')}\n];`);
console.log(`// PATCHES 배열에 추가: {v:${v},tables:V${v}_TABLES,ops:V${v}_OPS}`);
console.log(`// DOCS.history에 v${v} 변경 요약 한 줄 추가`);
notes.forEach(n => console.log('// 확인 필요: ' + n));
