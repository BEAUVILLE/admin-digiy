const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname,'..');
const home = fs.readFileSync(path.join(root,'index.html'),'utf8');
assert.match(home,/DIGIY PRO \(DRIVER compris, hors LOC\)/);
for(const amount of ['29 € HT / mois','250 € HT une fois','598 € HT','480 € HT','800 € HT','75 € HT / mois','765 € HT / an']){
 assert.ok(home.includes(amount), 'Référence ADMIN manquante : '+amount);
}
for(const page of ['finances-v2.html','finances.html']){
 const html=fs.readFileSync(path.join(root,page),'utf8');
 assert.ok(html.includes('29 € HT/mois'),'Prix commercial nouveau manquant : '+page);
 assert.ok(!html.includes('FR_ANNUAL_EUR=450'),'Ancienne constante interdite : '+page);
 assert.ok(!html.includes('eur.length*FR_ANNUAL_EUR'),'Historique projeté au mauvais tarif : '+page);
 assert.ok(html.includes('Exemple de 1re adhésion : 1 015 € HT'),'Exemple LOC HT manquant');
 assert.ok(html.includes('765 € HT')&&html.includes('250 € HT'),'LOC sous-comptes manquants');
 const match=html.match(/function recurringEurMonthly\(d\)\{[\s\S]*?\n\}\nfunction activePaid/);
 assert.ok(match,'Fonction d'évaluation MRR EUR manquante');
 const src=match[0].replace(/\nfunction activePaid$/,'');
 const price=d=>Number(d.price_eur??0);
 const calc=Function('price',src+'\nreturn recurringEurMonthly;')(price);
 assert.equal(calc({product_code:'membership-card',plan_code:'adherent-19900',billing:'monthly',price_eur:29}),29);
 assert.equal(calc({product_code:'membership-card',plan_code:'adherent-19900',billing:'annual',price_eur:450}),37.5);
 assert.equal(calc({product_code:'membership-card',plan_code:'adherent-19900',price_eur:45}),null);
 assert.equal(calc({product_code:'loc-pro',plan_code:'loc-1-3',billing:'annual',price_eur:765}),null);
 assert.equal(calc({product_code:'membership-card',plan_code:'adherent-19900',billing:'monthly',price_eur:0}),null);
}
console.log('OK · tarifs France et MRR EUR : règles et historique protégés');
