import { createClient } from "npm:@supabase/supabase-js@2.116.0";

// Staged serverless replacement for PIN + backend JWT. Not deployed by this PR.
// Requires a real Supabase Auth session with confirmed email and an active
// digiy_admins membership BEFORE checking the existing PIN.
const ALLOWED_ORIGINS = new Set(["https://backoffice.digiylyfe.com"]);
const headersFor = (origin: string | null) => ({
  "Access-Control-Allow-Origin": origin && ALLOWED_ORIGINS.has(origin) ? origin : "https://backoffice.digiylyfe.com",
  "Access-Control-Allow-Headers": "authorization,apikey,content-type,x-client-info",
  "Access-Control-Allow-Methods": "POST,OPTIONS",
  "Cache-Control": "no-store",
  "Vary": "Origin",
});
const reply = (origin: string | null, status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers: { ...headersFor(origin), "Content-Type": "application/json;charset=utf-8" } });

function publicKey(): string {
  const keys = Deno.env.get("SUPABASE_PUBLISHABLE_KEYS");
  try {
    const parsed = JSON.parse(keys || "{}");
    if (parsed.default) return String(parsed.default);
  } catch { /* fallback */ }
  return Deno.env.get("SUPABASE_ANON_KEY") || "";
}
function serviceKey(): string {
  const keys = Deno.env.get("SUPABASE_SECRET_KEYS");
  try {
    const parsed = JSON.parse(keys || "{}");
    if (parsed.default) return String(parsed.default);
  } catch { /* fallback */ }
  return Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "";
}
Deno.serve(async (req: Request) => {
  const origin = req.headers.get("Origin");
  if (req.method === "OPTIONS")
    return new Response("ok", { headers: headersFor(origin) });
  if (origin && !ALLOWED_ORIGINS.has(origin)) return reply(origin, 403, { ok:false, error:"origin_forbidden" });
  if (req.method !== "POST") return reply(origin, 405, { ok:false, error:"method_not_allowed" });
  const url = Deno.env.get("SUPABASE_URL") || "";
  const anon = publicKey(), service = serviceKey();
  if (!url || !anon || !service) return reply(origin, 503, { ok:false, error:"server_config" });
  const jwt = (req.headers.get("Authorization") || "").replace(/^Bearer\s+/i, "").trim();
  if (!jwt || jwt.length > 8192) return reply(origin, 401, { ok:false, error:"auth_required" });
  try {
    const authClient = createClient(url, anon, { auth:{ persistSession:false,autoRefreshToken:false } });
    const { data:{user},error:ue } = await authClient.auth.getUser(jwt);
    if (ue || !user || user.is_anonymous || !user.email_confirmed_at)
      return reply(origin, 401, { ok:false, error:"auth_required" });
    const admin = createClient(url, service, {auth:{persistSession:false,autoRefreshToken:false}});
    const {data:allowed,error:ae} = await admin.from("digiy_admins")
      .select("user_id,label").eq("user_id",user.id).eq("is_active",true).maybeSingle();
    if (ae || !allowed) return reply(origin, 403, {ok:false,error:"admin_forbidden"});
    const raw = await req.text();
    if (raw.length > 1800) return reply(origin,413,{ok:false,error:"payload_too_large"});
    const body = JSON.parse(raw || "{}");
    const action = String(body?.action || "check");
    if (action === "login") {
      const pin = String(body?.pin || "");
      if (pin.length < 4 || pin.length > 32) return reply(origin,400,{ok:false,error:"invalid_credentials"});
      const {data,error} = await admin.rpc("digiy_admin_login_for_user",{p_user_id:user.id,p_pin:pin});
      if (error) return reply(origin,500,{ok:false,error:"login_unavailable"});
      if (!data?.ok) return reply(origin,data?.error==="temporarily_locked"?429:401,{ok:false,error:data?.error||"invalid_credentials"});
      return reply(origin,200,{ok:true,token:data.token,exp:Number(data.exp),role:data.role,label:data.label});
    }
    const token = String(body?.token || "");
    if (!/^[0-9a-f]{64}$/.test(token)) return reply(origin,401,{ok:false,error:"invalid_session"});
    const {data:valid,error:ce} = await admin.rpc("digiy_admin_check_for_user",{p_user_id:user.id,p_token:token});
    if (ce || valid !== true) return reply(origin,401,{ok:false,error:"invalid_session"});
    if (action === "check") return reply(origin,200,{ok:true,role:"OPS",label:allowed.label||"Admin"});
    if (action === "logout") {
      const {error:le} = await admin.from("digiy_admin_tokens")
        .update({revoked:true}).eq("user_id",user.id).eq("token",token).eq("revoked",false);
      if (le) return reply(origin,500,{ok:false,error:"logout_unavailable"});
      return reply(origin,200,{ok:true});
    }
    return reply(origin,400,{ok:false,error:"unknown_action"});
  } catch {
    return reply(origin,400,{ok:false,error:"request_rejected"});
  }
});