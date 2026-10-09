'use strict';
const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const root=path.resolve(__dirname,'..');
const page=fs.readFileSync(path.join(root,'suivi-resto.html'),'utf8');
const home=fs.readFileSync(path.join(root,'index.html'),'utf8');

test('lien de suivi RESTO visible sans modifier les accès historiques',()=>{
 assert.match(home,/href="\.\/suivi-resto\.html"[^>]*>🍽️ RESTO · SUIVI<\/a>/);
 for (const link of ['./partenaires-terrain.html','./bonne-affaire.html','./carnet-wave.html','./finances-v2.html']){
  assert.ok(home.includes('href="'+link+'"'),'lien conservé '+link);
 }
 assert.match(home,/admin-cockpit-v2\.js\?v=20261006-handoff-v1/);
 assert.match(home,/admin-registers\.js\?v=20260923-renewal-quarantine-v2/);
});
test('relevé CORE est daté, vérifiable et distingue fusion du déploiement',()=>{
 assert.match(page,/9 octobre 2026/);
 assert.match(page,/Registre statique des preuves GitHub/);
 assert.match(page,/pas son déploiement sur le site/);
 assert.match(page,/non connecté aux données Supabase/);
 assert.match(page,/aucun menu ni commande client/i);
 assert.match(page,/0 % commission/);
});
test('six PR fusionnées du 9 octobre référencées dans les bonnes sections',()=>{
 for (const n of [26,29,30,31,32,33]){
  assert.ok(page.includes('https://github.com/BEAUVILLE/digiy-resto/pull/'+n),'PR fusionnée #'+n);
 }
 assert.match(page,/>6<\/strong>/);
 assert.match(page,/FUSIONNÉ · PR #32 \+ #33/);
});
test('trois PR techniques en brouillon, et PR #28 archivée sans fusion',()=>{
 for(const n of [19,21,24]) assert.match(page,new RegExp('href="https://github\\.com/BEAUVILLE/digiy-resto/pull/'+n+'"'));
 assert.match(page,/PR BROUILLON · #19/);
 assert.match(page,/PR BROUILLON · #21/);
 assert.match(page,/PR BROUILLON · #24/);
 assert.match(page,/fermé sans fusion/);
 assert.match(page,/pull\/28/);
});
test('aucune donnée privée ni action réseau dans ce relevé en lecture seule',()=>{
 assert.doesNotMatch(page,/<script\b|<form\b|<iframe\b|<input\b|contenteditable|\bonclick\s*=|service_role|supabase\.createClient|localStorage|https:\/\/.*?\/api\/admin\//i);
 assert.match(page,/noindex,nofollow,noarchive,nosnippet/);
 assert.doesNotMatch(page,/@gmail\.|Bearer |eyJ[a-zA-Z0-9_-]{18}/);
});
test('le pilote TEST SALY est explicite, jamais un formulaire de commande active',()=>{
 assert.match(page,/gestion\.html\?site=test-resa-resto-saly/);
 assert.match(page,/ma-carte\.html\?site=test-resa-resto-saly&amp;vue=carte/);
 assert.match(page,/publication bloquée/);
 assert.match(page,/restaurant libre/i);
});
