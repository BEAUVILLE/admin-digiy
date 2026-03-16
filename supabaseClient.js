// supabaseClient.js — UNIQUE pour tout le backoffice DIGIY
// Rôle :
// - créer un seul client Supabase partagé
// - garder une session admin stable
// - éviter les doublons de createClient dans tout le backoffice

(() => {
  "use strict";

  if (!window.supabase || typeof window.supabase.createClient !== "function") {
    console.error("[DIGIY] Supabase JS n'est pas chargé.");
    return;
  }

  const SUPABASE_URL = "https://wesqmwjjtsefyjnluosj.supabase.co";
  const SUPABASE_ANON_KEY = "sb_publishable_tGHItRgeWDmGjnd0CK1DVQ_BIep4Ug3";

  // Évite de recréer le client si le script est injecté plusieurs fois
  if (window.sb) {
    console.info("[DIGIY] Client Supabase déjà initialisé.");
    return;
  }

  window.sb = window.supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    auth: {
      persistSession: true,
      autoRefreshToken: true,
      detectSessionInUrl: true,
      storageKey: "digiy-admin-auth"
    }
  });

  // Alias optionnel si certains anciens fichiers lisent encore window.SB
  window.SB = window.sb;

  console.info("[DIGIY] Supabase client prêt.");
})();
