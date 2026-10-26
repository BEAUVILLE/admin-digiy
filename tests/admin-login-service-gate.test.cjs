const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const source = fs.readFileSync(path.resolve(__dirname, '..', 'backend · TS'), 'utf8');
const candidate = fs.readFileSync(path.resolve(__dirname, '..', 'audits/core-sql/candidates/20261026_admin_login_service_only_AFTER_DEPLOY.sql'), 'utf8');

test('admin_login RPC in backend uses server-only service key', () => {
  assert.match(source, /callSupabaseRPC\("admin_login",\s*\{[\s\S]*?p_pin:\s*pin,[\s\S]*?p_ip:\s*ip,\s*\},\s*true\)/);
});

test('delayed SQL closes direct public grants but preserves service_role', () => {
  assert.match(candidate, /REVOKE EXECUTE ON FUNCTION public\.admin_login\(text, text, text\)[\s\S]*?FROM PUBLIC, anon, authenticated;/);
  assert.match(candidate, /GRANT EXECUTE ON FUNCTION public\.admin_login\(text, text, text\)[\s\S]*?TO service_role;/);
  assert.match(candidate, /P0 HOLD: APPLY ONLY AFTER/);
});
