# DIGIY CORE — restauration privée sur Mac

**État : procédure préparée ; VRAIE restauration non exécutée.**

La sauvegarde chiffrée du 9 octobre 2026 est disponible dans l'[artefact GitHub 11590062979](https://github.com/BEAUVILLE/admin-digiy/actions/runs/37870420013/artifacts/11590062979), avec rétention de 30 jours. Télécharger le ZIP ORIGINAL depuis la page GitHub, sans le déposer sur un site tiers ou dans le chat.

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
# UNIQUEMENT si le volume du répertoire personnel est réellement chiffré :
DIGIY_ENCRYPTED_STORAGE_CONFIRMED=YES \
  bash scripts/restore-from-downloaded-artifact-local.sh \
  "$HOME/Downloads/NOM_DU_ZIP_TELECHARGE_DEPUIS_GITHUB.zip"
```

Remplacer le nom fictif du ZIP par le fichier téléchargé. La clé chiffrée est demandée directement dans le terminal avec saisie masquée ; ne jamais la coller dans ChatGPT. Le script refuse GitHub Actions, les URL de bases distantes, l'utilisation d'un secret préexporté et les terminaux non interactifs.

Le contrôle vérifie les **deux membres chiffrés** du ZIP ainsi que leur empreinte SHA-256, sans suivre l'ancien chemin absolu du runner GitHub qui apparaît dans le manifeste. Les données déchiffrées temporaires résident uniquement dans `~/DIGIY_PRIVATE_RESTORE/` sur le volume privé et sont détruites à la fin. Le conteneur PostgreSQL 17 est éphémère, **sans réseau** et n'a aucune connexion possible à la base DIGIY CORE.

**PASS uniquement** si tous ces marqueurs figurent dans la sortie : `ISOLATED_ARCHIVE_INTEGRITY_OK`, `ISOLATED_POSTGRES_READY`, `ISOLATED_RESTORE_SQL_OK`, `ISOLATED_RESTORE_PROOF_OK` (81 dates bloquées sur 81, zéro réservation MASTER et une RPC présente), et `ISOLATED_RESTORE_PRODUCTION_UNTOUCHED`.

**NO-GO au moindre échec** : fichier roles.sql réel, dépendances ou versions Supabase, données et droits ; aucun changement automatique en production. Cette restauration logique ne couvre pas les octets Storage, les fonctions Edge ni la configuration Auth/SMTP.

La preuve de restauration réelle, une validation propriétaire authentifiée à Saly/Sarlat et un GO SQL de production distinct restent obligatoires avant LOC V30.
