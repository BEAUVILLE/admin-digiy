// supabaseClient.js — UNIQUE pour tout le backoffice
onst SUPABASE_URL = "https://wesqmwjjtsefyjnluosj.supabase.co";
const SUPABASE_ANON_KEY = "sb_publishable_tGHItRgeWDmGjnd0CK1DVQ_BIep4Ug3"
window.sb = window.supabase.createClient(SUPABASE_URL, SUPABASE_ANON, {
  auth: {
    persistSession: true,
    autoRefreshToken: true,
    detectSessionInUrl: true,
    storageKey: "digiy-admin-auth" // IMPORTANT: même partout
  }
});
