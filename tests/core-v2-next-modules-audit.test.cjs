'use strict';
const test=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const root=path.join(__dirname,'..');
const audit=fs.readFileSync(path.join(root,'audits/core-sql/V2_COMMERCE_BUILD_JOB_READONLY.sql'),'utf8');
const report=fs.readFileSync(path.join(root,'docs/CORE_V2_COMMERCE_BUILD_JOB_20261010.md'),'utf8');
test('the next-modules audit is strictly SELECT only',()=>{
 const clean=audit.replace(/--[^\n]*/g,'');
 const statements=clean.split(';').map(x=>x.trim()).filter(Boolean);
 assert.equal(statements.length,4);
 for(const s of statements){
  assert.match(s,/^SELECT\b/i);
  assert.doesNotMatch(s,/\b(INSERT|UPDATE|DELETE|CREATE|ALTER|DROP|TRUNCATE|REVOKE|GRANT|COPY|CALL|DO)\s+/i);
 }
});
test('every next module is inventoried without PII',()=>{
 for(const s of ['digiy_commerce_sites','digiy_commerce_products','digiy_commerce_orders','digiy_build_artisans','digiy_build_pros','digiy_jobs_offers_pro','digiy_jobs_owner_workspaces','pg_policies']){
  assert.ok(audit.includes(s),'missing '+s);
 }
 assert.doesNotMatch(audit,/\b(customer_phone|customer_name|email|description|cv|client_token|client_name)\b/i);
 assert.match(audit,/job_offers_without_current_workspace/);
 assert.match(audit,/legacy_build_artisans_owner_id_uuid_like/);
});
test('production register was recorded without claiming professional links verified',()=>{
 assert.match(report,/20261010065702/);
 assert.match(report,/RLS et FORCE RLS/);
 assert.match(report,/aucun rapprochement implicite/i);
 assert.match(report,/Aucun lien individuel ajouté/);
 assert.match(report,/réservation/i);
});
