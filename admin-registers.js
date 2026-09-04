(()=>{
'use strict';
const root=document.getElementById('permanentRegistry');
if(!root)return;
const dept=root.dataset.dept||'';
const TOKEN_KEY='digiy_admin_jwt';
const APIS={
  adherents:'https://wesqmwjjtsefyjnluosj.supabase.co/functions/v1/digiy-adhesion-cockpit',
  partners:'https://wesqmwjjtsefyjnluosj.supabase.co/functions/v1/digiy-partner-cockpit',
  bonne:'https://wesqmwjjtsefyjnluosj.supabase.co/functions/v1/digiy-bonne-affaire-cockpit'
};
const $=id=>document.getElementById(id);
const list=$('registryList'),count=$('registryCount'),search=$('registrySearch'),refresh=$('registryRefresh'),status=$('registryStatus');
let rows=[],lastToken='';

if(!document.getElementById('digiyRegistryStyle')){
  const st=document.createElement('style');st.id='digiyRegistryStyle';st.textContent=`
  .registry-head{display:flex;justify-content:space-between;gap:10px;align-items:flex-start;flex-wrap:wrap}.registry-title{margin:0;font-size:22px}.registry-sub{margin:5px 0 0;color:var(--muted,#aac0b2);font-size:13px}.registry-tools{display:flex;gap:8px;flex-wrap:wrap;align-items:center}.registry-search{min-width:240px;width:min(360px,70vw);background:#07140f;border:1px solid rgba(255,255,255,.12);border-radius:12px;padding:11px;color:#fff}.registry-count{display:inline-flex;align-items:center;justify-content:center;min-width:42px;padding:8px 10px;border-radius:999px;background:rgba(250,204,21,.1);border:1px solid rgba(250,204,21,.28);color:#fde68a;font-weight:950}.registry-list{display:grid;gap:8px;margin-top:12px}.registry-row{display:grid;grid-template-columns:minmax(150px,1.35fr) minmax(110px,.8fr) minmax(110px,.8fr) minmax(130px,1fr) auto;gap:10px;align-items:center;padding:11px 12px;border:1px solid rgba(255,255,255,.1);border-radius:14px;background:rgba(255,255,255,.025)}.registry-name{font-weight:950}.registry-meta{font-size:11px;color:var(--muted,#aac0b2);margin-top:3px}.registry-status{display:inline-flex;width:max-content;max-width:100%;padding:5px 8px;border-radius:999px;border:1px solid rgba(255,255,255,.12);font-size:11px;font-weight:900}.registry-status.ok{color:#bbf7d0;border-color:rgba(34,197,94,.35)}.registry-status.bad{color:#fecaca;border-color:rgba(239,68,68,.35)}.registry-status.warn{color:#fde68a;border-color:rgba(245,158,11,.35)}.registry-wa{text-decoration:none;font-weight:900;font-size:12px}.registry-empty{padding:18px;text-align:center;border:1px dashed rgba(255,255,255,.12);border-radius:14px;color:var(--muted,#aac0b2)}@media(max-width:760px){.registry-row{grid-template-columns:1fr 1fr}.registry-row>div:first-child{grid-column:1/-1}.registry-wa{justify-self:end}}`;
  document.head.appendChild(st);
}

function esc(v){return String(v??'').replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;')}
function norm(v){return String(v||'').toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g,'')}
function phoneDigits(v){return String(v||'').replace(/\D/g,'')}
function alpha(a,b){return String(a.name||'').localeCompare(String(b.name||''),'fr',{sensitivity:'base',ignorePunctuation:true})}
function labelStatus(raw){const s=String(raw||'').toLowerCase();if(['valide','valid','active','accepted','approved','publiee','published'].includes(s))return['Validé','ok'];if(['refuse','refused','rejected','terminated','archived'].includes(s))return['Refusé','bad'];if(['fabrication','review','submitted','pending','a_confirmer','confirme','paused','test'].includes(s))return[s==='fabrication'?'En fabrication':s==='review'?'En examen':s==='submitted'?'Nouvelle':s==='pending'?'En attente':s==='confirme'?'Paiement confirmé':s==='paused'?'En pause':s==='test'?'Test':'À traiter','warn'];return[raw||'À traiter','warn']}
function adhStatus(d){if(String(d.status)==='refuse'||String(d.payment_status)==='refuse')return'refuse';if(String(d.status)==='valide')return'valide';if(String(d.payment_status)==='confirme'&&!['validee','publiee'].includes(String(d.card_status)))return'fabrication';return d.status||d.payment_status||'À traiter'}
function baStatus(a){if(String(a.payment_status)==='refuse'||String(a.statut)==='refused')return'refuse';if(String(a.statut)==='active')return'active';if(String(a.payment_status)==='confirme'&&String(a.statut)==='pending')return'review';return a.payment_status||a.statut||'À traiter'}
function coalesce(...vals){for(const v of vals)if(v!==undefined&&v!==null&&String(v).trim())return String(v).trim();return''}

async function api(action='list'){
  const token=localStorage.getItem(TOKEN_KEY)||'';
  if(!token)throw new Error('session_required');
  const res=await fetch(APIS[dept],{method:'POST',headers:{'Content-Type':'application/json','Authorization':'Bearer '+token},body:JSON.stringify({action,limit:1000}),cache:'no-store'});
  let data={};try{data=await res.json()}catch{}
  if(!res.ok||!data?.ok)throw new Error(data?.detail||data?.error||('HTTP '+res.status));
  return data;
}

function build(data){
  if(dept==='adherents')return (Array.isArray(data.dossiers)?data.dossiers:[]).map(d=>({name:coalesce(d.pro_name,d.name,d.full_name,'Sans nom'),kind:'Adhérent',city:coalesce(d.city,d.ville,d.city_zone),contact:coalesce(d.phone,d.telephone,d.whatsapp,d.email),status:adhStatus(d),detail:coalesce(d.plan_code,d.card_status)}));
  if(dept==='bonne')return (Array.isArray(data.annonces)?data.annonces:[]).map(a=>({name:coalesce(a.contact_nom,a.titre,'Sans nom'),kind:'Bonne Affaire',city:coalesce(a.ville,a.pays),contact:coalesce(a.whatsapp,a.telephone),status:baStatus(a),detail:coalesce(a.titre,a.categorie)}));
  const apps=(Array.isArray(data.applications)?data.applications:[]).map(a=>({name:coalesce(a.full_name,a.name,'Sans nom'),kind:'Candidature',city:coalesce(a.city_zone,a.city,a.ville),contact:coalesce(a.phone,a.telephone,a.whatsapp,a.email),status:a.status||'submitted',detail:coalesce(a.current_activity,a.languages)}));
  const partners=(Array.isArray(data.partners)?data.partners:[]).map(p=>({name:coalesce(p.full_name,p.name,p.partner_name,'Sans nom'),kind:'Partenaire',city:coalesce(p.city_zone,p.city,p.ville),contact:coalesce(p.phone,p.telephone,p.whatsapp,p.email),status:p.status||'active',detail:coalesce(p.partner_code,p.code)}));
  const map=new Map();for(const r of apps){const k=norm(r.name)+'|'+phoneDigits(r.contact);map.set(k,r)}for(const r of partners){const k=norm(r.name)+'|'+phoneDigits(r.contact);map.set(k,r)}return Array.from(map.values());
}

function render(){
  const q=norm(search?.value||'');
  const filtered=rows.filter(r=>!q||norm([r.name,r.kind,r.city,r.contact,r.status,r.detail].join(' ')).includes(q)).sort(alpha);
  count.textContent=String(filtered.length);
  list.innerHTML='';
  if(!filtered.length){list.innerHTML='<div class="registry-empty">'+(q?'Aucun résultat.':'Aucun dossier enregistré pour le moment.')+'</div>';return}
  list.innerHTML=filtered.map(r=>{const [lab,cls]=labelStatus(r.status);const num=phoneDigits(r.contact);return `<div class="registry-row"><div><div class="registry-name">${esc(r.name)}</div><div class="registry-meta">${esc(r.kind)}${r.detail?' · '+esc(r.detail):''}</div></div><div><span class="registry-status ${cls}">${esc(lab)}</span></div><div>${esc(r.city||'—')}</div><div>${esc(r.contact||'—')}</div><div>${num?`<a class="registry-wa" href="https://wa.me/${num}" target="_blank" rel="noreferrer">WhatsApp</a>`:'—'}</div></div>`}).join('');
}

async function load(){
  const token=localStorage.getItem(TOKEN_KEY)||'';
  if(!token){rows=[];count.textContent='0';list.innerHTML='<div class="registry-empty">Connecte-toi pour charger le registre permanent.</div>';status.textContent='';return}
  refresh.disabled=true;status.textContent='Chargement du registre…';
  try{const data=await api('list');rows=build(data).sort(alpha);render();status.textContent=`${rows.length} dossier${rows.length>1?'s':''} · classement A → Z`;}
  catch(e){list.innerHTML='<div class="registry-empty">Impossible de charger le registre. Vérifie la session puis actualise.</div>';status.textContent='';}
  finally{refresh.disabled=false}
}

refresh?.addEventListener('click',load);search?.addEventListener('input',render);
window.addEventListener('focus',()=>{if(localStorage.getItem(TOKEN_KEY))load()});
lastToken=localStorage.getItem(TOKEN_KEY)||'';setInterval(()=>{const t=localStorage.getItem(TOKEN_KEY)||'';if(t!==lastToken){lastToken=t;load()}},1500);
load();
})();
