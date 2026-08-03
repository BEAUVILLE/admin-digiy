# DIGIYLYFE — Route vers le Graal

## Objectif

Protéger la base centrale DIGIYLYFE contre :

- une suppression accidentelle ;
- une mauvaise publication ;
- une panne Supabase ;
- une erreur humaine ;
- la perte d'un projet ou d'un compte.

Le rail ne conserve jamais de données en clair dans GitHub. Chaque export est archivé, chiffré, contrôlé, puis supprimé du runner.

## Ce qui est sauvegardé

### Base PostgreSQL

La sauvegarde suit l'ordre officiel Supabase :

1. `roles.sql` — rôles personnalisés ;
2. `schema.sql` — tables, fonctions, RPC, vues, politiques RLS et structure ;
3. `data.sql` — données au format COPY ;
4. `history_schema.sql` et `history_data.sql` — historique des migrations, lorsqu'il existe.

### Supabase Storage

Lorsque `SUPABASE_URL` et `SUPABASE_SERVICE_ROLE_KEY` sont configurés :

- inventaire des objets ;
- téléchargement des octets de chaque fichier ;
- contrôle SHA256 de chaque objet ;
- inclusion dans l'archive chiffrée.

Sans ces deux secrets, les métadonnées Storage sont sauvegardées mais pas les fichiers eux-mêmes.

## Chiffrement

- algorithme : AES-256-CBC ;
- dérivation : PBKDF2 ;
- 250 000 itérations ;
- somme de contrôle SHA256 externe ;
- aucun SQL non chiffré n'est envoyé dans les artefacts.

Le mot de passe `BACKUP_PASSPHRASE` doit être conservé hors de GitHub, dans un gestionnaire de mots de passe ou sur un support physique sûr. Sans ce mot de passe, la sauvegarde est volontairement illisible.

## Automatisation

Workflow : `.github/workflows/supabase-backup.yml`

- exécution quotidienne : 02 h 17 UTC ;
- lancement manuel possible depuis GitHub Actions ;
- artefact GitHub chiffré conservé 30 jours ;
- copie hors site S3 compatible facultative ;
- aucune erreur rouge lorsque les secrets ne sont pas encore configurés : le workflow reste en attente sans lire la base.

## Secrets obligatoires

Dans le dépôt `BEAUVILLE/admin-digiy` :

`Settings → Secrets and variables → Actions → New repository secret`

Ajouter :

### `SUPABASE_DB_URL`

Chaîne de connexion PostgreSQL de la production. Utiliser la connexion Session pooler en priorité sur un runner IPv4 ; la connexion directe convient lorsque le réseau accepte IPv6.

Exemple de forme — ne jamais copier cet exemple comme valeur réelle :

```text
postgresql://postgres.PROJECT_REF:MOT_DE_PASSE@REGION.pooler.supabase.com:5432/postgres
```

### `BACKUP_PASSPHRASE`

Phrase secrète longue et unique destinée uniquement aux sauvegardes.

## Secrets Storage recommandés

### `SUPABASE_URL`

```text
https://PROJECT_REF.supabase.co
```

### `SUPABASE_SERVICE_ROLE_KEY`

Clé `service_role` du projet. Elle reste exclusivement dans les secrets GitHub et n'est jamais écrite dans le dépôt ni dans les journaux.

## Copie hors site facultative

Pour une archive indépendante de GitHub :

- `BACKUP_S3_BUCKET` ;
- `BACKUP_S3_PREFIX` ;
- `BACKUP_S3_ENDPOINT` pour un fournisseur S3 compatible ;
- `BACKUP_AWS_ACCESS_KEY_ID` ;
- `BACKUP_AWS_SECRET_ACCESS_KEY` ;
- `BACKUP_AWS_REGION`.

La copie hors site reçoit uniquement le fichier chiffré et sa somme SHA256.

## Premier lancement

1. Configurer les secrets obligatoires.
2. Ouvrir l'onglet **Actions** du dépôt.
3. Choisir **DIGIY — Sauvegarde Supabase chiffrée**.
4. Lancer **Run workflow**.
5. Vérifier dans le résumé :
   - Base : rôles + schéma + données ;
   - Storage : `full_objects` ou `metadata_only` ;
   - Historique migrations : `saved` ou `absent` ;
   - artefact chiffré présent.
6. Télécharger l'artefact et exécuter la vérification.

## Vérifier une archive

Sur une machine avec OpenSSL :

```bash
export BACKUP_PASSPHRASE='PHRASE_SECRETE'
chmod +x scripts/verify-supabase-backup.sh
scripts/verify-supabase-backup.sh \
  digiy-supabase-DATE.tar.gz.enc \
  digiy-supabase-DATE.tar.gz.enc.sha256
```

Le script vérifie :

- la somme SHA256 externe ;
- le déchiffrement ;
- l'intégrité gzip ;
- l'intégrité de tous les fichiers internes ;
- la présence des rôles, du schéma et des données.

## Test de restauration

La restauration doit se faire dans un **nouveau projet Supabase de test**, jamais dans la production.

```bash
export BACKUP_PASSPHRASE='PHRASE_SECRETE'
export RESTORE_DB_URL='CONNEXION_DU_PROJET_TEST'
export SUPABASE_DB_URL='CONNEXION_DE_PRODUCTION'
export PRODUCTION_PROJECT_REF='REF_PRODUCTION'
export RESTORE_TARGET_PROJECT_REF='REF_TEST'
export CONFIRM_RESTORE_TEST='YES'

chmod +x scripts/restore-supabase-test.sh
scripts/restore-supabase-test.sh digiy-supabase-DATE.tar.gz.enc
```

Le script refuse :

- la même URL que la production ;
- le même project-ref que la production ;
- une cible contenant déjà des tables applicatives dans `public` ;
- une exécution sans confirmation explicite.

## Validation du Graal

Le palier sauvegarde est considéré comme validé seulement après :

- une sauvegarde automatique réussie ;
- un artefact chiffré téléchargé ;
- une vérification SHA256 réussie ;
- une restauration complète dans un projet de test ;
- un contrôle des tables, fonctions RPC et données essentielles ;
- un contrôle séparé des objets Storage ;
- une copie hors site active.

## Règle absolue

Ne jamais :

- commiter un fichier `.sql`, `.dump` ou `.tar.gz` contenant des données ;
- écrire une clé `service_role` dans une page HTML ;
- restaurer directement dans la production pour faire un essai ;
- perdre la phrase secrète de chiffrement.
