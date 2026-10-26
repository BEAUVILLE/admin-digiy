# DIGIY admin_login — P0 service-only gate · 2026-10-26

## Why
Live production still grants PUBLIC, anon and authenticated access to public.admin_login(text,text,text), a SECURITY DEFINER function that validates the admin PIN and issues a database token. The currently tracked backend calls this function using the anon key, so revoking anon permission **before updating the actual deployed backend** would block founder login.

## Two-stage deployment (mandatory)
1. Inspect live deployment of admin.digiylyfe.com and confirm it uses the source file `backend · TS`. Back up the deployed file/config, without revealing secrets.
2. Deploy the small backend change in this PR (admin_login RPC via existing server-only service key). Confirm key is available only in backend environment, never the browser or GitHub.
3. Founder performs one ordinary admin login to confirm working path; verify admin dashboard and logout. No automated PIN test or test user creation.
4. **Only after success**, apply candidate SQL at `audits/core-sql/candidates/20261026_admin_login_service_only_AFTER_DEPLOY.sql` in DIGIY CORE `wesqmwjjtsefyjnluosj`.
5. Verify anon=false, authenticated=false, service_role=true using the read-only post-check. Test one normal founder login; monitor 401/403 and errors. Do not inspect PIN/token values.
6. If service-only login is not deployed/verified, **stop** before SQL. Keep existing function grants temporarily and prioritize deployment.

## Risks and follow-ups
- Current backend uses in-memory per-IP throttling and may trust forwarded IP headers; verify trusted proxy handling and add durable, centralized rate limiting in a separate focused change. The new server-only gate removes the ability to bypass backend controls via direct Supabase RPC.
- Because the user intentionally retains a PIN-based admin flow, consider a longer PIN or an additional factor (without forcing a PIN reset in this PR).
- Restricting SQL execution does not repair other unrelated SECURITY DEFINER functions.
- Repo merge **does not prove the VPS has been updated**. This PR does not deploy or alter live grants.

## Emergency rollback
If a verified access regression occurs, restore the previous backend version or temporarily regrant `EXECUTE` to `anon` only after assessing the exposure, then reattempt the gated rollout. Preserve logs and timestamps; no blanket grants to PUBLIC.
