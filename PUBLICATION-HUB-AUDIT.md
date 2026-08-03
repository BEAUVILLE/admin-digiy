# DIGIY ADMIN — Publication HUB

## Objet

Ajouter au backoffice existant une porte dédiée à la publication et à la mise à jour des professionnels dans le moteur territorial DIGIYLYFE, sans SQL manuel.

## Fichier ajouté

- `publication-hub.html`

## Rail utilisé

- session JWT existante du cockpit ;
- contrôle `GET /api/admin/check` ;
- catalogue public `digiy_metiers` et `digiy_zones` ;
- RPC fixe `digiy_hub_publish_partner` via la passerelle backend existante.

## Protections posées

1. Aucun appel d’écriture sans session admin valide.
2. Aucun appel d’écriture tant que le catalogue métiers/zones n’est pas chargé.
3. Détection sans écriture du contrat réel de la RPC avant déverrouillage.
4. Blocage immédiat si la sonde est acceptée comme une publication.
5. Prévisualisation de la carte publique avant confirmation.
6. Confirmation humaine finale avant chaque publication.
7. Les données privées ne figurent pas dans le formulaire.

## Point de sécurité découvert

La route générique actuelle `/api/rpc/:rpcName` transmet tout nom de RPC fourni par un administrateur authentifié avec la clé service Supabase. Une liste blanche backend est recommandée avant fusion définitive.

Liste minimale envisagée :

- `digiy_pay_admin_list_public_proofs`
- `digiy_pay_public_proof_validate`
- `digiy_hub_publish_partner`

La liste pourra être complétée par variable d’environnement pour les opérations exceptionnelles, sans rouvrir toutes les fonctions Supabase.

## Test fonctionnel à réaliser avant fusion

1. Ouvrir le cockpit et se connecter par PIN.
2. Ouvrir `publication-hub.html` sur la branche de prévisualisation ou après déploiement temporaire.
3. Vérifier les trois voyants : session, catalogue, contrat RPC.
4. Contrôler la réponse brute de la sonde.
5. Ne lancer une publication qu’après reconnaissance complète des paramètres.
6. Tester avec une fiche pilote identifiable et vérifier création ou mise à jour sans doublon dans le HUB.

## Hors périmètre de cette branche

- modification des activations existantes ;
- modification des preuves PAY ;
- modification des tables privées ;
- ajout de SQL ;
- déploiement ou redémarrage du backend Deno.
