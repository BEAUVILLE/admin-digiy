'use strict';
const test=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const os=require('node:os');
const path=require('node:path');
const cp=require('node:child_process');
const helper=path.resolve(__dirname,'verify-resa-v9-restored-snapshot.sh');
const restore=fs.readFileSync(path.resolve(__dirname,'restore-supabase-github-isolated.sh'),'utf8');
const GOOD='false|false|false|true|true|true|true|false|true|true|5';
const COUNTS='7|0|1|1|0|0|0|1|0';
function run({data=COUNTS,acl=GOOD,expected=COUNTS}={}){
 const tmp=fs.mkdtempSync(path.join(os.tmpdir(),'digiy-v9-test-'));
 try{
  const bin=path.join(tmp,'bin');fs.mkdirSync(bin);
  const docker=path.join(bin,'docker');
  const script='#'+'!/usr/bin/env bash\n'
    +'if [[ "$*" == *has_function_privilege* ]]; then printf "%s\\n" "$FAKE_ACL";'
    +' else printf "%s\\n" "$FAKE_COUNTS"; fi\n';
  fs.writeFileSync(docker,script,{mode:0o700});
  return cp.spawnSync('bash',[helper,'fake-offline-container',expected,tmp],{
    encoding:'utf8',
    env:{PATH:bin+':'+process.env.PATH,FAKE_COUNTS:data,FAKE_ACL:acl}
  });
 }finally{fs.rmSync(tmp,{recursive:true,force:true})}
}
test('helper/parent have valid bash syntax and opt-in isolated execution',()=>{
 for(const f of [helper,path.resolve(__dirname,'restore-supabase-github-isolated.sh')]){
  const x=cp.spawnSync('bash',['-n',f],{encoding:'utf8'});
  assert.equal(x.status,0,x.stderr);
 }
 assert.match(restore,/DIGIY_EXPECTED_RESA_V9_COUNTS/);
 assert.match(restore,/verify-resa-v9-restored-snapshot\.sh/);
 assert.ok(restore.indexOf('verify-resa-v9-restored-snapshot.sh') <
   restore.indexOf('ISOLATED_RESTORE_PRODUCTION_UNTOUCHED'));
});
test('matching real aggregate and targeted ACL succeed without remote DB',()=>{
 const x=run();
 assert.equal(x.status,0,x.stderr);
 assert.match(x.stdout,/RESA_V9_ISOLATED_RESTORE_PROOF_OK/);
 assert.match(x.stdout,/RESA_V9_ISOLATED_ACL_OK/);
 assert.doesNotMatch(x.stdout,/phone|email|secret|client_name/i);
});
test('wrong historical count or missing pilot link refuses success',()=>{
 for(const data of ['6|0|1|1|0|0|0|1|0','7|0|1|1|0|0|0|0|0']){
  const x=run({data});
  assert.notEqual(x.status,0);
  assert.match(x.stderr,/SNAPSHOT_COUNTS_MISMATCH/);
  assert.doesNotMatch(x.stdout,/PROOF_OK/);
 }
});
test('default PUBLIC EXECUTE leak after restore is a hard failure',()=>{
 const x=run({acl:'true|false|true|true|true|true|true|false|true|true|5'});
 assert.notEqual(x.status,0);
 assert.match(x.stderr,/ACL_NOT_RESTORED/);
 assert.doesNotMatch(x.stdout,/PROOF_OK/);
});
test('V9 missing, wrong role, PAY trigger or overlap guard is a hard failure',()=>{
 for(const acl of [
  'false|false|false|true|true|true|true|false|true|true|4',
  'false|false|false|true|true|true|true|false|false|true|5',
  'false|false|false|true|true|true|true|false|true|false|5',
  'false|false|false|true|true|true|true|true|true|true|5'
 ]){
  const x=run({acl});assert.notEqual(x.status,0);
  assert.match(x.stderr,/ACL_NOT_RESTORED/);
 }
});
test('never accepts invalid expected aggregates',()=>{
 for(const expected of ['','7','7|1|2|3|4|5|6','7|0|1|1|0|0|0|1|secret']){
  const x=run({expected});
  assert.notEqual(x.status,0);
  assert.match(x.stderr,/EXPECTED_COUNTS_INVALID/);
 }
});
