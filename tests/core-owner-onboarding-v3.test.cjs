'use strict';
const test=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const root=path.resolve(__dirname,'..');
const sql=fs.readFileSync(path.join(root,'audits/core-sql/V3_OWNER_ACCESS_PREFLIGHT_READONLY.sql'),'utf8');
const ops=fs.readFileSync(path.join(root,'activations.html'),'utf8');
const doc=fs.readFileSync(path.join(root,'docs/CORE_OWNER_ONBOARDING_V3_20261010.md'),'utf8');
const stripped=sql.replace(/--[^\n]*/g,'').trim();
test('V3 onboarding audit is SELECT-only, without any mutation or live owner data',()=>{
 const stmts=stripped.split(';').map(x=>x.trim()).filter(Boolean);
 assert.equal(stmts.length,4);
 for(const statement of stmts){
   assert.match(statement,/^(?:SELECT|WITH)\b/i);
   assert.doesNotMatch(statement,/\b(?:INSERT|UPDATE|DELETE|TRUNCATE|DROP|ALTER|CREATE|GRANT|REVOKE|COPY|CALL|EXECUTE|COMMIT|ROLLBACK|DO)\b/i);
 }
 assert.doesNotMatch(stripped,/\b(?:u\.email\s*(?:,|AS|FROM)|phone_e164|customer_phone|customer_name|raw_user_meta_data)\b/i);
});
test('V3 audit detects unassigned and orphan owner across all three modules',()=>{
 for(const name of ['digiy_commerce_sites','digiy_build_public_profiles','digiy_jobs_owner_workspaces','auth.users',
  'owner_uid IS NULL','NOT auth_exists','email_confirmed_at','pg_constraint','relrowsecurity']){
  assert.ok(stripped.includes(name),'missing '+name);
 }
 assert.match(stripped,/fiches_publiques_sans_acces_pro/);
 assert.match(stripped,/LEFT JOIN auth\.users u ON u\.id=/);
});
test('OPS activation is not falsely reported as finished owner login',()=>{
 assert.match(ops,/id="owner-access-preflight"/);
 assert.match(ops,/Accès propriétaire non encore vérifié/);
 assert.match(ops,/Abonnement activé dans le backend/);
 assert.match(ops,/ne crée pas le compte Auth/);
 assert.match(ops,/api\/admin\/activate/);
 assert.doesNotMatch(ops,/auth\.signUp\(/);
});
test('runbook refuses auto-association and defines actual new-member gates',()=>{
 for(const term of ['7','4','5 sur 6','jb-baptiste-build','pilote-jobs-baptiste-digiy',
  'shouldCreateUser:false','auth.users.id','navigation privée','refus','RLS','transaction',
  'une MFA fictive','POST /api/admin/activate']){
  assert.ok(doc.includes(term),'missing '+term);
 }
 assert.match(doc,/Ne pas attribuer/);
 assert.match(doc,/dossier validé/);
});
