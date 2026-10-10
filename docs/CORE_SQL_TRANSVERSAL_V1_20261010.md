# DIGIY CORE SQL — Audit transversal V1 (EXPLORE × RÉSA × LOC × TRUST)

Date du contrôle : **10 octobre 2026** · Projet : `digiy-core` / `wesqmwjjtsefyjnluosj`  
Dépôt central de suivi : `BEAUVILLE/admin-digiy`.  
**Statut : audit lecture seule, aucune migration, aucune ouverture du pilote.**

## 1. Principe central

**DIGIY CORE = source de vérité des données, permissions et preuves métier.** GitHub conserve le code des interfaces et des migrations. EXPLORE, RÉSA, LOC et TRUST gardent leurs règles métier ; leur liaison ne doit jamais reposer sur une simple supposition du navigateur.

Chemin cible : `Professionnel CORE → fiche EXPLORE → prestation RÉSA → créneau → réservation client réelle → preuve indépendante de réalisation → éligibilité TRUST → avis étoiles validé`.

La réservation, son statut `done`, le paiement direct ou la déclaration du professionnel **ne prouvent jamais indépendamment** qu'un service a été exécuté.

## 2. Résultats SQL réels, agrégés (aucune donnée privée sortie)

| Objet | Lignes |
| --- | ---: |
| `digiy_explore_places` | 1 |
| `digiy_explore_calendar` | 4 |
| `digiy_resa_profiles` | 1 |
| `digiy_resa_services` | 9 |
| `digiy_resa_slots` | 3 |
| `digiy_resa_bookings` | 7 |
| `digiy_resa_universal_launch_controls` | 1 |
| `digiy_trust_private.voluntary_feedback` | 0 |

Huit services historiques actifs ne sont pas rattachés aux profils RÉSA modernes. Leur lecture publique est actuellement autorisée et a été observée ; aucun service Baptiste n'est visible de cette manière. Toute modification de cette règle exige une revue de compatibilité des anciens clients et ne doit pas être appliquée directement.

**Classification legacy indispensable :** les 7 réservations ont `client_request_id IS NULL` (toutes historiques). 7/7 n'ont pas de profil moderne lié au même slug. 8/9 prestations n'ont pas de profil RÉSA moderne. Six réservations portant un `service_id` ne retrouvent pas un service correspondant au même slug dans la table actuelle. **Ce sont des écarts de rattachement au modèle moderne, pas une preuve de corruption ou une autorisation de suppression.** Ne pas ajouter de FK universelle ni réécrire ces anciennes lignes sans analyse de leurs usages réels.

Contrôles positifs : 0 créneau RÉSA sans profil ; 0 paire EXPLORE/RÉSA de même slug avec deux `auth_user_id` différents ; 0 prestation active sur un profil non publié **au moment de l'audit**. Ces comptes doivent rester contrôlés automatiquement avant toute migration.

### Pilote réel Baptiste

`sortie-peche-jb-baptiste-760a00ad` : une fiche EXPLORE, un profil RÉSA, **même propriétaire authentifié**, 1 prestation `Sortie pêche` (240 minutes, tarif sur demande, brouillon), 3 créneaux datés, 0 réservation. `resa_published=false`, `pilot_enabled=false`. Les deux calendriers sont cohérents sur les dates 10–12 octobre, 09 h–13 h. Une journée EXPLORE n'est cependant pas, à elle seule, un créneau RÉSA.

## 3. Contraintes physiques réellement présentes

- `digiy_explore_calendar.place_id → digiy_explore_places.id` via FK et `UNIQUE(place_id,day)`.
- `digiy_resa_slots.slug → digiy_resa_profiles.slug` via FK; `UNIQUE(slug,slot_date,start_time)`, exclusion GiST des créneaux ouverts chevauchés.
- `digiy_resa_universal_launch_controls.slug → digiy_resa_profiles.slug`.
- `digiy_resa_bookings` possède un index/conflit d'exclusion GiST sur les rendez-vous en attente/confirmés.
- **Pas de FK physique** de `digiy_resa_services.slug` vers le profil moderne, ni de `digiy_resa_bookings.service_id` vers `digiy_resa_services.id` : les fonctions/RLS métiers effectuent des vérifications applicatives. Ne pas créer directement ces FK, car des lignes legacy seraient affectées.
- `digiy_trust_private.voluntary_feedback.listing_id → digiy_loc_master_units.id`. Ce stockage est **LOC-spécifique** ; ne pas y insérer un ID RÉSA/EXPLORE.

## 4. Sécurité actuelle

- RLS activée sur les tables publiques concernées et sur `digiy_trust_private.voluntary_feedback`.
- Pour la table TRUST privée : 0 policy, `anon`, `authenticated`, `authenticator` et `service_role` n'ont pas de droit d'usage du schéma ni de lecture/insertion de cette table lors du contrôle; elle reste fermée. `digiy_trust_server` **absent**.
- `digiy_resa_universal_pilot_gate_v1` répond `enabled=false` pour Baptiste. Aucune activation publique.
- La policy RÉSA historique « Public can read active RESA services » autorise la lecture anonyme sur `is_active=true` **sans** condition explicite sur `profile.is_published`. Le pilote est aujourd'hui protégé car sa prestation est inactive. **Point à durcir après analyse de compatibilité legacy**, ou adopter exclusivement la RPC publique filtrée et réviser les grants/policies ciblés.
- `digiy_resa_slots` conserve d'anciennes policies propriétaires permissives et une garde MFA **restrictive** sur `authenticated`. Éviter les modifications isolées des GRANT/policies tant que les parcours existants ne sont pas testés.
- Les travaux TRUST LOC V26/V27/V28 ont signalé des droits PUBLIC hérités sur des fonctions `SECURITY DEFINER`. **Ne pas contourner le garde-fou** pour créer un rôle serveur à la hâte.

## 5. Ordre proposé de consolidation SQL, sans rupture

**Lot A — registre de correspondance en lecture seule (premier candidat).** Définir un identifiant professionnel CORE stable et des références métier explicites `(module, identifiant métier)`, sans prétendre que des slugs différents sont équivalents. Valider le propriétaire `auth_user_id` côté CORE, pas dans le navigateur. Ajouter des requêtes de réconciliation et un compteur de décalages; ne pas migrer les anciennes réservations. Préparer migration versionnée, rollback et tests sur clone isolé.

**Lot B — intégrité du moteur universel RÉSA.** Classer les 7 réservations historiques et les 8 prestations anciennes avant toute contrainte. Exiger pour les **nouveaux événements uniquement** la correspondance service–profil–créneau et la même identité propriétaire. Contrôler au serveur la concordance EXPLORE « journée disponible » versus RÉSA « créneau actif » selon le contrat métier, y compris lors d'une fermeture ultérieure ; ne jamais annuler les rendez-vous déjà pris sans politique métier explicite. Durcir avec précaution la lecture `anon` des prestations actives sur fiches non publiées.

**Lot C — contrat de preuve TRUST transversal.** Un registre d'événements de prestation réalisée vérifié indépendamment, avec `source_module`, `source_event_id`, professionnel, client identifié par voie indépendante, preuve et identité de l'attestateur, consommation à usage unique et contraintes anti-doublon. `done` seul ne délivre ni attestation ni invitation. Les notations 1–5 étoiles, sans commentaire public, comporteront des critères métier et **rapport qualité-prix distinct et obligatoire**. N'ouvrir aucun formulaire avant validation RLS, permissions serveur, modération et tests de sécurité.

## 6. Critères de passage à une migration réelle

1. Inventaire des consommateurs (anciens clients, RESTO, LOC, EXPLORE, RÉSA), classement des enregistrements historiques.
2. Modèle SQL et rollback **versionnés dans GitHub**, aucun SQL improvisé en production.
3. Essai sur sauvegarde/clone isolé ; tests droits `anon`, `authenticated`, propriétaire, rôle serveur; vérification des règles métier et de l'absence de fuite de données.
4. Vérification de la sauvegarde restaurable et de l'impact sur les autres modules.
5. PR, CI verte, revue des droits `PUBLIC/SECURITY DEFINER`, validation humaine avant DDL et avant publication.

**Décision V1 :** conserver le pilote fermé et produire d'abord l'inventaire/l'audit en lecture seule. Les étapes A/B/C sont proposées, non déployées.

Script associé : [`audits/core-sql/V1_CROSS_MODULE_READONLY.sql`](../../audits/core-sql/V1_CROSS_MODULE_READONLY.sql).
