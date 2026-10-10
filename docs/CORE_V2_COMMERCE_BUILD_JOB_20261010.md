# DIGIY CORE V2 — Registre privé + feuille de route COMMERCE / BUILD / JOB

**Date : 10 octobre 2026 · Projet Supabase : digiy-core**  
**Décision :** garder PostgreSQL comme source de vérité. Les interfaces ne créent pas une identité parallèle. Cette V2 n'active ni réservation, ni avis TRUST, ni caisse, ni paiement intermédiaire.

## Application SQL en production — réalisée et contrôlée

Migration Supabase enregistrée : `20261010065702 digiy_core_v2_private_professional_registry_20261010`. Tests PostgreSQL 17 et CI <https://github.com/BEAUVILLE/admin-digiy/pull/34> verts ; première archive chiffrée de sécurité réalisée avant DDL via <https://github.com/BEAUVILLE/admin-digiy/actions/runs/38025910667> (tentative 2, nouvelle archive 06:49 UTC).

**Preuves post-application en lecture seule :** schéma `digiy_core_private` réellement créé ; tables `professionals` et `module_links`, **RLS et FORCE RLS activées**, zéro policy, zéro ligne, aucune permission d'usage ou SELECT/INSERT pour `anon`, `authenticated`, `authenticator`, `service_role`. Index UNIQUE `(module,source_key)` et FK `module_links.professional_id` vérifiés. Pilote Baptiste `enabled=false`, aucune réservation créée. L'advisor Supabase signale `rls_enabled_no_policy` sur les nouvelles tables : **c'est le verrou volontaire du registre privé** (<https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy>), pas une demande d'ouvrir des policies.

**Important :** la création des deux tables est terminée, pas leur remplissage. Le rail de rapprochement des propriétaires et son workflow de validation indépendante doivent encore être réalisés avant tout `module_links.verification_status='verified'`.

## Sauvegarde post-migration et passages de relais

La **sauvegarde après** application du schéma CORE V2 est réussie. Workflow :
<https://github.com/BEAUVILLE/admin-digiy/actions/runs/38025910667>, tentative 3,
terminée le **10 octobre 2026 à 07:03 UTC**, artefact chiffré
`digiy-supabase-2026-10-10T06-57-55Z` (1 426 621 octets).
Avant migration, la tentative 2 du même workflow avait produit
`digiy-supabase-2026-10-10T06-49-47Z` (1 424 893 octets).
Les deux artefacts existent, non expirés au contrôle.
**Limite :** réussite des exports/chiffrement/stockage GitHub, mais pas de
restauration de cette archive récente ; copie S3/hors site non configurée.
Rétention GitHub : 30 jours. Conserver une copie chiffrée et son SHA256 hors du dépôt.

Missions suivantes, liées au vrai schéma actuel :
- **COMMERCE** : <https://github.com/BEAUVILLE/mon-commerce/issues/19> — 1 site, 1 commande ; pas de caisse.
- **BUILD** : <https://github.com/BEAUVILLE/digiy-build/issues/21> — préserver 3 artisans historiques, vérifier les comptes.
- **JOB** : <https://github.com/BEAUVILLE/digiy-jobs/issues/22> — conserver 4 offres et établir le véritable propriétaire.

Ces tickets ne constituent **pas** une activation de module ni une autorisation de
copier des données personnelles. Les registres CORE restent volontairement vides
jusqu'à validation de l'identité/provenance des professionnels.

## Registre CORE : contrat SQL

Candidat : `audits/core-sql/candidates/CORE_V2_PRIVATE_REGISTRY_CANDIDATE.sql`.

Deux nouvelles tables **vides**, dans un schéma `digiy_core_private` hors `public` :
- `professionals` : UUID stable du professionnel, distinct de ses fiches et espaces métiers.
- `module_links` : relation explicite, unique par `(module,source_key)`, vers une seule identité CORE. Un même professionnel peut posséder plusieurs modules. L'auth propriétaire observée et la vérification de cette relation sont enregistrées par un circuit administratif contrôlé, non par le visiteur.

Modules autorisés : EXPLORE, RESA, LOC, RESTO, DRIVER, COMMERCE, BUILD, JOB. **Aucun rapprochement implicite** par slug, numéro de téléphone, adresse, nom ou `owner_id` de type texte.

**Sécurité :** schéma privé, RLS + FORCE RLS, zéro policy, aucun droit API pour `anon`, `authenticated`, `authenticator` ou `service_role`, aucune RPC, aucun seed. Le niveau `verified` exige identité propriétaire observée, validateur et date de vérification ; une future vérification serveur devra être ajoutée avant de remplir le registre. Le SQL est **versionné et appliqué en production** ; les deux tables restent vides, privées et sans droit d'API. Ce n'est pas un mécanisme de publication.

**Lot A n'autorise pas TRUST :** la table privée existante `digiy_trust_private.voluntary_feedback` demeure LOC-spécifique et le rôle serveur TRUST n'existe pas. Aucun transfert vers RÉSA ou ces trois modules sans attestation indépendante.

## Inventaire réel préalable — 10 octobre 2026

| Module | Tables/état | Remarque de réconciliation |
|---|---|---|
| COMMERCE | `digiy_commerce_sites` : 1 ; `digiy_commerce_products` : 0 ; `digiy_commerce_orders` : 1 | Commande historique conservée ; sites avec `auth_user_id uuid` ; produits reliés au site par FK ; ordre/client jamais inventés |
| BUILD | `digiy_build_artisans` : 3 ; `digiy_build_pros` : 0 ; `digiy_build_requests` : 0 ; `digiy_build_jobs` : 0 | Ancien `artisans.owner_id` est `text`, nouveau `pros.owner_id` est `uuid`. 0/3 ancien `owner_id` respecte un format UUID ; **aucune conversion automatique** |
| JOB | `digiy_jobs_offers_pro` : 4 ; `digiy_jobs_owner_workspaces` : 0 ; `digiy_jobs_missions_pro` : 0 | Les 4 offres ne correspondent pas à un workspace moderne. Les laisser telles quelles avant classification et inspection des clients historiques |

Ces chiffres ne suffisent pas à conclure qu'une ligne est fausse ou qu'elle doit être supprimée. Aucun téléphone, identité client, CV ou message privé ne figure dans le rapport.

### Ordre de déploiement métier

**1. COMMERCE** — Première candidate au CORE : identifier avec `auth_user_id` réel du site, valider owner + MFA, préserver commandes et produits, catalogue public de produits réellement actifs et demandes de commande. **Paiement/contact directs, zéro commission, aucune caisse/POS**. Vérifier les droits de demande anonyme, les doublons de commande et la séparation lecture publique/gestion privée. Pas de produit fictif.

**2. BUILD** — Séparer les trois artisans historiques des nouveaux comptes `digiy_build_pros`; auditer les politiques publiques, devis, demandes, affectations, preuves métier et autorisations avant inscription CORE. Une demande de devis n'est pas un chantier réalisé, et un `job` BUILD n'est pas une offre JOB.

**3. JOB** — Conserver les quatre offres historiques; lier progressivement les espaces recruteurs authentifiés, jamais le `owner_id` texte à un Auth UUID par simple conversion. Protéger candidats, coordonnées, candidatures et informations privées. Les annonces publiques doivent provenir d'offres effectivement autorisées et actives. Ne pas confondre demande de recrutement et prestation attestée TRUST.

### Gates transversaux

- **Backup préalable obligatoire** avec archive chiffrée et contrôle des artefacts; copie hors site à configurer séparément si nécessaire.
- **Migration candidate** testée en PostgreSQL 17 isolé : schéma privé, anti-double liaison, refus lien vérifié sans preuve, refus d'accès `anon`, refus du replay.
- **Migration de production distincte et enregistrée**, jamais depuis la consultation de cette page. Ne rien remplir tant que la validation propriétaire par module n'existe pas.
- **RLS et permissions** : vérifier la portée des politiques historiques avant modification ; exclure tout rôle avec privilèges inattendus; ne pas contourner le blocage TRUST V26 `PUBLIC`.
- **TRUST** reste hors d'usage tant que prestation réelle + preuve indépendante client + protection anti-doublon + modération ne sont pas validées.
- **Recette réelle** sur téléphone, sans réservations, commandes, candidats ou avis fabriqués.

### Fichiers et état

- DDL : `audits/core-sql/candidates/CORE_V2_PRIVATE_REGISTRY_CANDIDATE.sql`
- Fixture / preuve PG17 : `tests/core-v2-private-registry-fixture.sql`, `tests/core-v2-private-registry-smoke.sql`
- CI : `.github/workflows/core-v2-private-registry.yml`
- **Aucun lien individuel ajouté lors de cette préparation**. Tout rapprochement devra être basé sur la propriété authentifiée et auditable, pas sur le nom du module.

**Livrable immédiat :** socle structurel CORE sécurisé **installé**, documentation métier et tests isolés. Les corrections COMMERCE/BUILD/JOB restent des chantiers distincts après validation du rail CORE.
