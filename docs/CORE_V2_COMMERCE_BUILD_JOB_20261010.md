# DIGIY CORE V2 — Registre privé + feuille de route COMMERCE / BUILD / JOB

**Date : 10 octobre 2026 · Projet Supabase : digiy-core**  
**Décision :** garder PostgreSQL comme source de vérité. Les interfaces ne créent pas une identité parallèle. Cette V2 n'active ni réservation, ni avis TRUST, ni caisse, ni paiement intermédiaire.

## Registre CORE : contrat SQL

Candidat : `audits/core-sql/candidates/CORE_V2_PRIVATE_REGISTRY_CANDIDATE.sql`.

Deux nouvelles tables **vides**, dans un schéma `digiy_core_private` hors `public` :
- `professionals` : UUID stable du professionnel, distinct de ses fiches et espaces métiers.
- `module_links` : relation explicite, unique par `(module,source_key)`, vers une seule identité CORE. Un même professionnel peut posséder plusieurs modules. L'auth propriétaire observée et la vérification de cette relation sont enregistrées par un circuit administratif contrôlé, non par le visiteur.

Modules autorisés : EXPLORE, RESA, LOC, RESTO, DRIVER, COMMERCE, BUILD, JOB. **Aucun rapprochement implicite** par slug, numéro de téléphone, adresse, nom ou `owner_id` de type texte.

**Sécurité :** schéma privé, RLS + FORCE RLS, zéro policy, aucun droit API pour `anon`, `authenticated`, `authenticator` ou `service_role`, aucune RPC, aucun seed. Le niveau `verified` exige identité propriétaire observée, validateur et date de vérification ; une future vérification serveur devra être ajoutée avant de remplir le registre. Le SQL est actuellement un **candidat versionné**, non un mécanisme de publication.

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

**Livrable immédiat :** socle structurel CORE sécurisé candidat, documentation métier et tests isolés. Les corrections COMMERCE/BUILD/JOB restent des chantiers distincts après validation du rail CORE.
