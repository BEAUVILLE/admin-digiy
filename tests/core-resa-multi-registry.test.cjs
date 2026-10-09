'use strict';
const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const root=path.resolve(__dirname,'..');
const home=fs.readFileSync(path.join(root,'index.html'),'utf8');
const multi=fs.readFileSync(path.join(root,'suivi-resa-multi.html'),'utf8');
const resto=fs.readFileSync(path.join(root,'suivi-resto.html'),'utf8');

test('lien RÉSA MULTI ajouté au cockpit sans supprimer RESTO ni les autres rubriques',()=>{
 assert.match(home,/href="\.\/suivi-resa-multi\.html"[^>]*>🗓️ RÉSA MULTI · SUIVI<\/a>/);
 for(const href of ['./suivi-resto.html','./partenaires-terrain.html','./bonne-affaire.html','./finances-v2.html','./carnet-wave.html']){
  assert.ok(home.includes('href="'+href+'"'),'navigation conservée '+href);
 }
 assert.match(home,/admin-cockpit-v2\.js\?v=20261006-handoff-v1/);
 assert.match(home,/admin-registers\.js\?v=20260923-renewal-quarantine-v2/);
});

test('RÉSA MULTI : état daté distinguant preuve GitHub et déploiement réel',()=>{
 assert.match(multi,/9 octobre 2026/);
 assert.match(multi,/PR fusionnée prouve le code présent/);
 assert.match(multi,/pas un service déjà déployé/);
 assert.match(multi,/ne consulte ni ne modifie Supabase/);
 assert.match(multi,/0 % commission/);
});

test('seize PR vérifiées et caractéristiques réelles portées correctement',()=>{
 for(const n of [1,6,8,9,11,12,13,14,15,16]){
  assert.ok(multi.includes('https://github.com/BEAUVILLE/digiy-resa-table-resto/pull/'+n),'PR #'+n);
 }
 assert.match(multi,/>16<\/strong>/);
 assert.match(multi,/>3<\/strong>/);
 assert.match(multi,/>7<\/strong>/);
 assert.match(multi,/DEMO/);
 assert.match(multi,/REAL/);
});

test('frontières RESTO / RÉSA MULTI / LOC, moteur BEAUTY et libre confirmation',()=>{
 assert.match(multi,/TEST BEAUTY SALY/);
 assert.match(multi,/Confirmer \/ Refuser/);
 assert.match(multi,/🍽️ RESTO : MANGER/);
 assert.match(multi,/🗓️ RÉSA MULTI : RÉSERVER \/ RDV/);
 assert.match(multi,/🏠 LOC : DORMIR \/ LOUER/);
 assert.match(multi,/demande de rendez-vous n'est pas une confirmation automatique/);
 assert.match(multi,/7 entrées/);
 assert.ok(resto.includes('Rien sous le tapis'));
});

test('registre est purement documentaire et ne collecte rien',()=>{
 assert.match(multi,/noindex,nofollow,noarchive,nosnippet/);
 assert.doesNotMatch(multi,/<script\b|<form\b|<iframe\b|<input\b|onclick=|sessionStorage|localStorage|service_role|sb_publishable_|Bearer |auth\.getUser|fetch\s*\(/i);
 assert.doesNotMatch(multi,/@gmail\.|@yahoo\.|@outlook\./);
});
