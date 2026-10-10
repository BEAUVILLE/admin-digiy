# DIGIY CORE · V3 — contrôle d'entrée propriétaire avant livraison adhérent

Date : **10 octobre 2026**. Source : audit réel de CORE `wesqmwjjtsefyjnluosj`, SQL en lecture seule, tests terrain précédents COMMERCE, BUILD et JOBS.

## Décision opérationnelle

**Activation de l'abonnement ≠ ouverture de l'espace propriétaire.**
L'opération `POST /api/admin/activate` de la page `activations.html` envoie un **téléphone de facturation**, un module, un plan et le montant. Elle ne crée pas, ne confirme pas et ne rattache pas à elle seule un compte Supabase Auth. Elle ne doit pas afficher « accès propriétaire prêt » à tort.

**Un futur adhérent ne reste pas devant une porte fermée :**
1. **Dossier métier validé humainement** (professionnel, module, activité et fiche précise). La validation commerciale et l'attribution d'identité sont deux décisions distinctes.
2. **Email propriétaire exact et accepté par le professionnel** ; vérifier l'identité et contrôler qu'il n'est pas le compte d'un tiers. Ne pas associer par numéro, slug, nom similaire, WhatsApp, cookie localStorage ou `user_metadata`.
3. **Identité Supabase Auth existante** (réutilisée si réellement la sienne) ou compte créé/invité par un processus administrateur serveur sûr et autorisé. Le portail appelle `auth.signInWithOtp({shouldCreateUser:false})` : **il ne crée aucun utilisateur**. Ne pas modifier ce drapeau à `true` pour résoudre un blocage : cela permettrait des inscriptions non validées.
4. **Attribuer dans CORE uniquement le véritable `auth.users.id`**, avec contrôle strict du dossier et vérification de concurrence avant mise à jour (auth UID unique selon modèle). Commerce : `digiy_commerce_sites.auth_user_id`. BUILD : `digiy_build_public_profiles.owner_id`. JOBS : `digiy_jobs_owner_workspaces.auth_user_id`. Pour JOBS, créer un espace vide seulement pour une personne identifiée et validée, jamais rattacher les offres ou candidatures historiques sans preuve de provenance. Utiliser une transaction admin validée et journalisée, pas un UPDATE déclenché par le navigateur client.
5. **Vérifier les Redirect URLs autorisées** sur Supabase Auth pour le chemin fixe exact du module, sans effacer les autres domaines. BUILD : `https://build.digiylyfe.com/gestion-build-v2.html`. JOBS : `https://jobs.digiylyfe.com/gestion-jobs-v2.html`. COMMERCE : `https://mon-commerce.digiylyfe.com/gestion-produits-v3.html`.
6. **Faire un vrai test propriétaire en navigation privée** : demander **un nouveau** magic link envoyé à l'adresse autorisée ; ouvrir le lien et vérifier le titre métier correct. Tester ensuite la déconnexion et la reconnexion.
7. **Faire un test négatif avec un autre compte** : la gestion, les commandes, demandes et candidatures d'un tiers restent invisibles sous RLS. Ne jamais demander le code OTP ou le lien reçu par email dans un ticket.
8. **Déclarer le dossier "accès propriétaire livré" uniquement après le test réel**. Sinon marquer **"accès propriétaire à finaliser"** et conserver la fiche/la commande/candidature intacte.

## État SQL du 10 octobre 2026

| Module | Total | Compte propriétaire Auth absent malgré un UID | Attribution vide | Publiées sans compte propriétaire valide |
|---|---:|---:|---:|---:|
| COMMERCE | 1 | 0 | 0 | 0 |
| BUILD | 12 | **7** | **4** | **5 sur 6 fiches publiées** |
| JOBS | 1 | 0 | 0 | 0 |

La seule fiche BUILD publiée reliée à un vrai Auth constatée lors de cet audit est `jb-baptiste-build`. Les 7 UID BUILD qui n'existent pas dans `auth.users` peuvent être des références historiques ; **ne pas les écraser sans identifier leur provenance**. Parmi les 7, **6 fiches sont inactives/non publiées** et **1 est publiée**. Les 4 sans propriétaire sont publiées. Ne pas fabriquer de comptes pour "faire passer" les tests.

Le pilote JOBS `pilote-jobs-baptiste-digiy` est connecté à un compte Auth validé et contient **0 offre / 0 candidature**. Les 4 offres et 8 candidatures historiques restent séparées ; ne pas attribuer ces données au pilote.

## Urgences terrain BUILD

Fiches publiées non encore ouvrables par un propriétaire Auth vérifié :
- `helage-plombier` — `owner_id` historique sans compte Auth
- `babacar-plombier-pro` — attribution propriétaire absente
- `mane-gning-nettoyage` — attribution propriétaire absente
- `partenaires-kourant` — attribution propriétaire absente
- `partenaires-mbaye` — attribution propriétaire absente

Chaque dossier nécessite validation humaine d'identité, email autorisé et rattachement serveur. **La vitrine publique peut rester visible** ; ne pas créer automatiquement un droit de gestion pour justifier cette visibilité.

## Contrat technique et garde-fous

- Audit réexécutable : `audits/core-sql/V3_OWNER_ACCESS_PREFLIGHT_READONLY.sql`, exclusivement SELECT/CTE, aucune donnée PII affichée.
- L'exécuter avec un rôle OPS contrôlé côté DB (lecture `auth.users`), **jamais en exposant cette requête aux navigateurs publics**, même authentifiés.
- Le front actuel de `admin-digiy/activations.html` envoie le paiement au backend ; il n'assure pas l'onboarding Auth. C'est un travail serveur séparé, à tracer.
- **Ne pas** mettre `auth_user_id` ou `owner_id` depuis les champs libres de la page commerçante. **Ne pas** désactiver RLS ni la vérification de compte.
- Ni SMS, ni logiciel de caisse, ni commission requis. L'email magic link est **AAL1**, pas une MFA fictive.
- Critère de fin du chantier à appliquer à chaque nouvelle fiche : **dossier validé + vrai Auth + rattachement exact + magic link testé + tiers refusé**.

## À ne pas conclure

Les contrôles SQL démontrent les correspondances actuellement stockées et les refus RLS en lecture seule ; ils ne prouvent pas que l'email a été reçu dans la boîte de chaque professionnel. Un rattachement existant ne démontre pas, à lui seul, que l'identité du titulaire a été vérifiée humainement. Ne promettre un accès personnel qu'après cette validation.
