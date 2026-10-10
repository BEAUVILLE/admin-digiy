# DIGIY RESTO — preuve de sauvegarde restaurable dans Docker privé

**10 octobre 2026.** On n'assimile pas une restauration LOC réussie à une vérification
du moteur métier **RÉSA RESTO**. Cette étape contrôle les restaurants présents dans
le même **dump chiffré DIGIY CORE**, sans restaurer sur la base de production.

## État vérifié en lecture seule

Projet `digiy-core` (`wesqmwjjtsefyjnluosj`), état relevé le 10/10/2026 :

| Indicateur | Nombre |
| --- | ---: |
| Restaurants `digiy_resa_resto_sites` | 4 |
| Restaurants actifs | 2 |
| Restaurants avec `owner_id` réel renseigné | 2 |
| Zones | 7 |
| Tables | 10 |
| Plages de service | 8 |
| Réservations V31 `digiy_resa_resto_bookings` | 0 |
| Associations réservation–tables | 0 |
| Réservations `resa_resto_reservations` historiques | 2 |

Dernières dates `updated_at` des 4 tables de paramétrage :
**2026-09-30** (avant le snapshot chiffré du **2026-10-09 09:13 UTC**).
Ce sont les **agrégats du snapshot de référence** ; ne jamais recopier
une valeur si la source ou l'archive change.

Six tables RÉSA RESTO avaient RLS activé. Dans la base de production, trois RPC
propriétaires ont **EXECUTE anon révoqué**, et deux RPC client
(`public_book_v1` / `public_availability_v1`) sont autorisées à `anon`.
La restauration du dump du 09/10 à 09:13 **peut restaurer des droits antérieurs
à la correction d'accès exécutée plus tard le 09/10**. Le script affiche donc
les droits du *snapshot* séparément et exige une nouvelle sauvegarde postérieure
à cette correction avant de prétendre pouvoir restaurer les permissions actuelles.

## Nouvelle preuve RESTO avec le même ZIP privé

Seul le Mac de l'opérateur autorisé possède le secret, saisi localement dans
le Terminal et jamais copié dans ChatGPT, GitHub ou l'environnement du runner.
Docker Desktop doit être démarré, FileVault activé, dépôt
`BEAUVILLE/admin-digiy` à jour (après fusion de cette PR).
Conserver le ZIP chiffré original du run `37909800559`,
`digiy-supabase-2026-10-09T09-13-01Z.zip`.

Depuis `admin-digiy` :

```bash
git switch main
git pull --ff-only origin main
fdesetup status
docker info >/dev/null && echo "DOCKER OK"
DIGIY_EXPECTED_MASTER_BLOCKED_DAYS=82 \
DIGIY_EXPECTED_RESTO_COUNTS='4|2|2|7|10|8|0|0|2' \
DIGIY_ENCRYPTED_STORAGE_CONFIRMED=YES \
  bash scripts/restore-from-downloaded-artifact-local.sh \
  "$HOME/Downloads/digiy-supabase-2026-10-09T09-13-01Z.zip"
```

`DIGIY_ENCRYPTED_STORAGE_CONFIRMED=YES` n'est autorisé que si le
disque local est réellement chiffré.

### PASS attendu

- `ISOLATED_RESTORE_SQL_OK`
- `ISOLATED_RESTORE_PROOF_OK: 82/82` — contrôle LOC existant
- `RESTO_ISOLATED_RESTORE_PROOF_OK: sites=4 active=2 owner_bound=2 zones=7 tables=10 windows=8 bookings=0 links=0 legacy=2`
- `RESTO_ISOLATED_RLS_OK: 6/6` ; `RESTO_ISOLATED_RPC_OK: 5/5`, `RESTO_ISOLATED_PUBLIC_RPC_OK: 2/2`, `RESTO_ISOLATED_ORPHANS_OK: 0`
- `RESTO_ARCHIVED_OWNER_RPC_ANON_EXECUTE: n/3` — **simple constat des grants de l'archive historique**, pas assertion des droits de production
- `ISOLATED_RESTORE_PRODUCTION_UNTOUCHED`
- `RESTORE_LOCAL_ISOLATED_SUCCESS`

Le script refuse tout écart de nombre, table manquante, RLS incomplète,
RPC manquante, appel public indisponible ou lien orphelin. Les seuls résultats
exposés sont des **agrégats**, jamais un nom, un téléphone, un email ou un UUID.
L'archive est restaurée dans un conteneur Docker sans réseau, puis effacée.

**ATTENTION :** Ceci prouve restauration logique RESTO du snapshot chiffré
et cohérence minimale des données. Ce n'est PAS un test d'accès véritable via
deux sessions Auth propriétaires, ni un test UX sur iPhone/Android, ni la preuve
des octets Storage ou des fonctions Edge.

## Suite RESTO de production (indépendante de RÉSA universel)

1. Sauvegarde chiffrée récente **postérieure** aux dernières modifications des
   fonctions RÉSA RESTO, puis restauration privée séparée pour prouver les droits
   actuels. Ne pas réutiliser aveuglément le snapshot du 09/10 pour une migration
   ultérieure.
2. Deux vrais propriétaires A/B : connexion, rattachement autorisé, refus d'accès
   croisé aux 6 tables et 3 RPC propriétaires, création/confirma­tion/annulation
   de réservation sans recette PAY fictive, vérification des limites de capacité
   par service et du délai de 15 minutes.
3. Validation de la fiche professionnelle (Le Malraux / L'Entre 2 / restaurant
   pilote réel) et des horaires midi/soir sans créer de fausses réservations.
4. **À emporter sans caisse** : module distinct, propriétaire et produits réels,
   aucune collecte par DIGIYLYFE, pas de commande fictive annoncée comme réelle.
5. `CARNET PRO` reste indépendant, facultatif et lié seulement aux paiements
   réellement reçus sur place.

## Test automatisé de cette nouvelle preuve

`.github/workflows/resto-isolated-restore-proof.yml` crée un PostgreSQL 17
**synthétique et sans réseau**, exécute exactement
`scripts/verify-resto-restored-snapshot.sh` en lecture seule et confirme le
rejet d'un mauvais nombre de tables, d'une table sans RLS et d'une RPC
manquante. Le test CI **ne déchiffre aucune archive réelle**. Les données
test sont entièrement fictives et détruites. Ce n'est pas une preuve de
restauration de l'archive réelle tant que l'opérateur n'a pas lancé la
commande ci-dessus.
