# DIGIY CORE — restauration privée sur Mac

**État (2026-10-09) : restauration SQL RÉELLE de l'archive #74 effectuée avec succès par l'opérateur sur Mac privé, sans réseau externe.** Journal non sensible : `ISOLATED_RESTORE_SQL_OK`, `ISOLATED_RESTORE_PROOF_OK` (81/81, 0 MASTER) et `ISOLATED_RESTORE_PRODUCTION_UNTOUCHED`. Le correctif local prépare Auth avec GoTrue `v2.197.0` et Storage avec `supabase/storage-api:v1.80.2`, complétées par les migrations officielles 0021, 0022, 0025 et 0057. **La nouvelle archive #75, créée après le passage du calendrier à 82 jours, n'a PAS encore été restaurée : sa propre preuve reste nécessaire.**

La sauvegarde récente est [**l'artefact GitHub privé #11604211913 — run #75**](https://github.com/BEAUVILLE/admin-digiy/actions/runs/37905010977/artifacts/11604211913), créée le 9 octobre 2026 à 08:27–08:33 UTC et conservée jusqu'au 8 novembre. Télécharger le ZIP ORIGINAL de cette exécution : `digiy-supabase-2026-10-09T08-27-18Z.zip`. L'[archive précédente #74](https://github.com/BEAUVILLE/admin-digiy/actions/runs/37887484483/artifacts/11596464191) n'inclut pas nécessairement la 82e journée ajoutée ensuite. Ne déposer aucun ZIP sur un site tiers ni dans ce chat.

## Prérequis obligatoires

- Mac personnel, autorisé et volume de destination chiffré (vérifier FileVault avec `fdesetup status`).
- Docker Desktop opérationnel (`docker info`), Python 3, OpenSSL et `shasum` ou `sha256sum`.
- Checkout local à jour du dépôt `BEAUVILLE/admin-digiy`, avec les scripts de restauration revus et les tests GitHub verts.
- Ne jamais partager mot de passe, capture de données restaurées ni dumps SQL. Aucun secret GitHub n'est sollicité par le connecteur.

## Commande de l'opérateur uniquement

Depuis le répertoire local `admin-digiy` sur le Mac sécurisé :

```bash
fdesetup status
docker info
python3 --version
# Après git pull --ff-only origin main et vérification du volume chiffré,
# baseline 82 observée à 08:20 UTC. ÉGALITÉ stricte requise.
DIGIY_EXPECTED_MASTER_BLOCKED_DAYS=82 \
DIGIY_ENCRYPTED_STORAGE_CONFIRMED=YES \
  bash scripts/restore-from-downloaded-artifact-local.sh \
  "$HOME/Downloads/digiy-supabase-2026-10-09T08-27-18Z.zip"
```

Remplacer le nom fictif du ZIP par le fichier téléchargé. La clé chiffrée est demandée directement dans le terminal avec saisie masquée ; ne jamais la coller dans ChatGPT. Le script refuse GitHub Actions, les URL de bases distantes, l'utilisation d'un secret préexporté et les terminaux non interactifs.

Le contrôle vérifie les **deux membres chiffrés** du ZIP ainsi que leur empreinte SHA-256, sans suivre l'ancien chemin absolu du runner GitHub qui apparaît dans le manifeste. Les données déchiffrées temporaires résident uniquement dans `~/DIGIY_PRIVATE_RESTORE/` sur le volume privé et sont détruites à la fin. Le conteneur PostgreSQL 17 est éphémère, **sans réseau externe** (`--network none`). Un second conteneur éphémère construit à partir de l'image officielle **`supabase/gotrue:v2.197.0`** partage UNIQUEMENT son espace réseau fermé (`--network container:<postgres>`), afin de lancer les migrations officielles Supabase Auth avec des identifiants locaux générés à usage unique. Aucun nom d'hôte ni mot de passe de DIGIY CORE n'est transmis. L'initialisation doit produire `ISOLATED_AUTH_MIGRATIONS_OK` et `ISOLATED_AUTH_CATALOG_OK` (27 tables). Un conteneur Storage partage le même réseau Docker sans sortie externe. Les scripts officiels sont appliqués à la base jetable avec des identifiants générés localement. Les marqueurs `ISOLATED_STORAGE_MIGRATIONS_OK`, `ISOLATED_STORAGE_MULTIPART_COMPAT_OK` et `ISOLATED_STORAGE_CATALOG_OK` vérifient les 8 tables Storage attendues, indépendamment des tables supplémentaires de l'image. Les correctifs locaux `auth.jwt()` et `audit_log_entries.ip_address` restent contrôlés.

**PASS uniquement** si tous ces marqueurs figurent dans la sortie : `ISOLATED_ARCHIVE_INTEGRITY_OK`, `ISOLATED_POSTGRES_READY`, `ISOLATED_AUTH_MIGRATIONS_OK`, `ISOLATED_AUTH_CATALOG_OK`, `ISOLATED_AUTH_JWT_BOOTSTRAP_OK`, `ISOLATED_AUTH_AUDIT_COMPAT_OK`, `ISOLATED_STORAGE_MIGRATIONS_OK`, `ISOLATED_STORAGE_MULTIPART_COMPAT_OK`, `ISOLATED_STORAGE_CATALOG_OK`, `ISOLATED_RESTORE_SQL_OK`, `ISOLATED_RESTORE_PROOF_OK` (nombre strictement attendu de dates toutes bloquées, par exemple 82/82 pour #75, zéro réservation MASTER et une RPC présente), et `ISOLATED_RESTORE_PRODUCTION_UNTOUCHED`.

**NO-GO au moindre échec** : fichier roles.sql réel, dépendances ou versions Supabase, données et droits ; aucun changement automatique en production. Cette restauration logique ne couvre pas les octets Storage, les fonctions Edge ni la configuration Auth/SMTP.

Le test CI synthétique vérifie aussi qu'une archive artificielle de 82 jours échoue si l'opérateur attend 81, puis réussit exactement avec 82. Le test inclut `COPY auth.custom_oauth_providers`, `COPY auth.audit_log_entries`, `COPY storage.buckets`, `COPY storage.objects`, `COPY storage.s3_multipart_uploads` et `COPY storage.s3_multipart_uploads_parts`. Il est vert avec les migrations officielles. Il ne remplace pas une vraie récupération. La preuve de restauration **de la nouvelle archive #75** et la vérification des copies propriétaires déployées restent obligatoires avant l'activation SQL de LOC V30. Le succès de #74 ne couvre pas le nouveau snapshot. Un contrôle agrégé ne prouve pas seul l'identité exacte des journées historiques.
