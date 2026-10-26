const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const read = p => fs.readFileSync(path.resolve(__dirname,'..',p),'utf8');
const sql=read('audits/core-sql/candidates/20261026_admin_native_supabase_AUTH_PIN_HOLD.sql');
const edge=read('supabase/functions/digiy-admin-session-v1/index.ts');
const page=read('admin-sans-vps.html');

test('Only server role can execute new privileged RPCs',()=>{
  for(const name of ['digiy_admin_login_for_user','digiy_admin_check_for_user']){
    assert.match(sql,new RegExp('revoke execute on function public\\.'+name+'\\([^)]+\\) from public, anon, authenticated','i'));
    assert.match(sql,new RegExp('grant execute on function public\\.'+name+'\\([^)]+\\) to service_role','i'));
  }
});
test('Admin PIN is checked only after authenticated identity & membership',()=>{
  assert.ok(edge.indexOf('.auth.getUser(jwt)')>=0);
  assert.ok(edge.indexOf('.auth.getUser(jwt)')<edge.indexOf('admin.rpc("digiy_admin_login_for_user"'));
  assert.ok(edge.indexOf('.from("digiy_admins")')<edge.indexOf('admin.rpc("digiy_admin_login_for_user"'));
  assert.match(sql,/attempts\+1 >= 5/);
});
test('Beta route is distinct from the current cockpit',()=>{
  assert.match(page,/admin-sans-vps\.html/);
  assert.match(page,/shouldCreateUser:false/);
  assert.match(page,/digiy-admin-session-v1/);
  assert.match(page,/sessionStorage/);
});
