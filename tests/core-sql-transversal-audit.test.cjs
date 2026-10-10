'use strict';
const test=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const base=path.resolve(__dirname,'..');
const sql=fs.readFileSync(path.join(base,'audits/core-sql/V1_CROSS_MODULE_READONLY.sql'),'utf8');
const report=fs.readFileSync(path.join(base,'docs/CORE_SQL_TRANSVERSAL_V1_20261010.md'),'utf8');
const stripped=sql.replace(/--[^\n]*/g,'').trim();
test('CORE SQL V1 contains only SELECT audit statements',()=>{
 const statements=stripped.split(';').map(x=>x.trim()).filter(Boolean);
 assert.equal(statements.length,7,'each section must contain one read-only SELECT');
 for(const statement of statements){
  assert.match(statement,/^SELECT\b/i);
  assert.doesNotMatch(statement,/\b(?:INSERT|UPDATE|DELETE|TRUNCATE|DROP|ALTER|CREATE|GRANT|REVOKE|CALL|EXECUTE|COPY|DO|SET|COMMIT|ROLLBACK)\b/i);
 }
});
test('audits real EXPLORE, RÉSA, LOC and TRUST links without customer PII',()=>{
 for(const path of ['public.digiy_explore_places','public.digiy_explore_calendar','public.digiy_resa_profiles',
   'public.digiy_resa_services','public.digiy_resa_slots','public.digiy_resa_bookings',
   'digiy_trust_private.voluntary_feedback','pg_constraint','pg_class']){
  assert.ok(stripped.includes(path),'missing '+path);
 }
 assert.match(stripped,/client_request_id IS NULL/);
 assert.match(stripped,/auth_user_id<>e\.auth_user_id/);
 assert.match(stripped,/pilot_enabled/);
 assert.match(stripped,/relrowsecurity/);
 assert.doesNotMatch(stripped,/\b(?:customer_phone|customer_name|owner_phone)\b/i);
});
test('report keeps pilot closed, legacy untouched, TRUST independent and SQL rollout gated',()=>{
 for(const marker of ['7 réservations','8/9 prestations','0 réservation','enabled=false',
    'rapport qualité-prix','aucune migration','lecture seule','rollback']){
  assert.ok(report.toLowerCase().includes(marker.toLowerCase()),'missing report marker '+marker);
 }
 assert.match(report,/\bdone\b/);
 assert.match(report,/digiy_trust_server/);
 assert.match(report,/sources?\s+de\s+v[ée]rit[ée]/i);
});
