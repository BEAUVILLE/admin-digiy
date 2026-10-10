# Incident P0 — restauration #77 : privilèges RESTO non conservés

**Détecté le 10 octobre 2026 par la restauration Mac privée de la sauvegarde
chiffrée #77 (run 38018152366, archive 11657661114).**

## Preuves

- CORE actuel, lecture seule : `anon EXECUTE` sur les trois RPC
  propriétaires RESTO = **0/3** ; `authenticated` et `service_role` = 3/3.
- Nouvelle archive #77 restaurée en PostgreSQL 17 Docker sans réseau :
  **3/3** RPC propriétaires exécutables par `anon`.
- Les données restaurées restent cohérentes : LOC 82/82 jours bloqués,
  RESTO 4/4 sites, 7 zones, 10 tables, 8 plages, 2 réservations legacy,
  RLS 6/6, RPC présentes 5/5 et 0 lien orphelin.
- Le problème concerne la **reconstitution des privilèges PostgreSQL** ;
  réussir `supabase db dump` et la restauration SQL ne signifie pas
  préserver les `REVOKE` historiques. Les droits implicites `PUBLIC EXECUTE`
  sont réappliqués quand la fonction est recréée. Les ACL ne sont pas
  suffisamment restaurées par la procédure existante.
- Conséquence : l'archive #77 reste un filet de récupération **des données**,
  pas une preuve complète des permissions propriétaires RESTO ; il ne faut
  jamais la restaurer en PROD sans revue des droits.

## Correction de sauvegarde

`scripts/export-resto-owner-rpc-acl.sql` examine le catalogue **en lecture
seule** avant chaque sauvegarde. Il attend les signatures exactes de :

1. `digiy_resa_resto_claim_site_by_email_v1(text)`
2. `digiy_resa_resto_owner_refresh_no_shows_v1(uuid)`
3. `digiy_resa_resto_owner_set_booking_status_v1(uuid,text)`

Il refuse un objet absent, non `SECURITY DEFINER` ou un droit EXECUTE
incorrect (`anon` doit être refusé ; `authenticated` et `service_role`
autorisés). Il produit exclusivement les `REVOKE`/`GRANT` spécifiques à
**ces trois fonctions**, en conservant leurs signatures exactes.
Le fichier `resto-owner-rpc-acl.sql` rejoint le même tar chiffré AES-256
que `roles.sql`, `schema.sql`, `data.sql`, est couvert par `SHA256SUMS`
et jamais affiché en clair dans un artefact.

`backup-status.txt` contient le marqueur
`resto_owner_rpc_acl=verified_v1` si, et seulement si, l'export a réussi.
La sauvegarde échoue avant archivage si un privilège diverge.
**Cette correction ne change aucun grant dans DIGIY CORE en production.**

## Correction de restauration

`scripts/restore-supabase-github-isolated.sh` vérifie la présence et
l'intégrité du fichier ACL lorsque le marqueur existe et le rejoue dans
**la même transaction** que les rôles, le schéma et les données sur un
PostgreSQL Docker **sans réseau**. Ensuite, il vérifie les permissions
effectives via `has_function_privilege` :

```text
ISOLATED_RESTO_OWNER_RPC_ACL_OK: anon=0/3 authenticated=3/3 service_role=3/3.
RESTO_ARCHIVED_OWNER_RPC_ANON_EXECUTE: 0/3
RESTORE_LOCAL_ISOLATED_SUCCESS
```

S'il manque le fichier ou si `anon` peut exécuter l'une de ces fonctions,
la restauration **échoue**. Pour les archives historiques #76 et #77,
l'absence de fichier est annoncée explicitement :
`ISOLATED_RESTO_OWNER_RPC_ACL_NOT_CAPTURED`. Le succès des données reste
valable, mais **pas les permissions** de ce périmètre.

## Validation et limites

La CI restaure dans une base **PG17 fictive sans réseau** un scénario
où les ACL se perdent, applique le fichier exporté et exige le retour de
`anon` à 0/3 ; elle teste aussi l'échec de sauvegarde si `anon` retrouve
EXECUTE dans la source. Elle ne reçoit aucun dump réel ni secret.

**Ce correctif est ciblé sur trois RPC propriétaires RESTO.** Il ne
prétend pas exporter/rejouer tous les ACL de toute la base (tableaux,
autres fonctions, séquences, autres rôles). Un inventaire global des
permissions et la récupération des octets Storage doivent être traités
séparément.

## Runbook après fusion et CI verte

1. Dans GitHub Actions du dépôt `BEAUVILLE/admin-digiy`, lancer la nouvelle
   exécution du workflow `supabase-backup.yml` sur `main`. Attendre
   `success` et l'artefact chiffré ; elle sera **postérieure à #77**.
2. Sur le Mac chiffré FileVault, télécharger **uniquement** ce nouvel
   artefact ZIP chiffré, ne pas fournir la phrase secrète.
3. Depuis `~/admin-digiy` à jour, réutiliser :
   ```bash
   DIGIY_EXPECTED_MASTER_BLOCKED_DAYS=82 \
   DIGIY_EXPECTED_RESTO_COUNTS='4|2|2|7|10|8|0|0|2' \
   DIGIY_ENCRYPTED_STORAGE_CONFIRMED=YES \
   bash scripts/restore-from-downloaded-artifact-local.sh \
     "$HOME/Downloads/NOM_DU_ZIP_TELECHARGE.zip"
   ```
4. Exiger simultanément `ISOLATED_RESTO_OWNER_RPC_ACL_OK`,
   `RESTO_ARCHIVED_OWNER_RPC_ANON_EXECUTE: 0/3`,
   `ISOLATED_RESTORE_PROOF_OK: 82/82`,
   `RESTO_ISOLATED_RESTORE_PROOF_OK`,
   `ISOLATED_RESTORE_PRODUCTION_UNTOUCHED`.
5. **Ne pas confondre** cette preuve avec le test de deux vraies sessions
   Auth propriétaires RESTO A/B (non encore effectué).

Zéro service / migration ajouté au CORE ; 0 % commission ;
aucun logiciel de caisse introduit.
