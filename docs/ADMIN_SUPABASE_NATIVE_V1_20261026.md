# DIGIY Admin sans VPS — prototype, NO GO production

Date : 26 octobre 2026. Aucun déploiement, aucune migration et aucun changement sur la page d'administration existante.

## Preuves relevées
- Un administrateur actif associé à un compte Auth email confirmé est disponible dans DIGIY CORE.
- Le cockpit principal admin-cockpit-v2.js appelle encore /api/admin/login, /api/admin/check et /api/admin/logout sur admin.digiylyfe.com.
- Les Edge Functions d'adhésion, bonne affaire et partenaires vérifient encore leurs sessions via ce domaine. Le cockpit secondaire a aussi des routes backend particulières.
- La PR #39 a modifié GitHub, mais aucun déploiement du backend sur un VPS n'a été vérifié.

## Cible 100% GitHub Pages + Supabase
1. Magic-link email administrateur autorisé par Supabase Auth ; le compte admin existant est réutilisé.
2. PIN personnel inchangé ; seul le serveur Edge appelle digiy_admin_login_for_user avec service_role.
3. La RPC lie la session PIN à l'identifiant Auth réellement vérifié, limite cinq échecs par fenêtre de 15 minutes et produit un token aléatoire de 8 heures.
4. Les vérifications du token sont liées au même utilisateur Supabase ; aucun mot de passe, PIN, hash ou clé serveur dans le navigateur.
5. Les Edge Functions métier doivent être migrées vers la validation Supabase et la liaison Auth + PIN, sans requêtes vers l'ancien backend.
6. La page isolée admin-sans-vps.html permet de tester login, check et logout sans toucher au cockpit actuel.

## Ordre des opérations (ne pas sauter d'étape)
- Revue indépendante de la migration SQL et test isolé, dont verrouillage 5 erreurs, nouvelle fenêtre, mauvais email, mauvais PIN, révocation et concurrence.
- Configurer l'URL exacte https://backoffice.digiylyfe.com/admin-sans-vps.html dans les Redirect URLs Supabase Auth si elle est absente.
- Appliquer après revue la migration additive candidate située dans audits/core-sql/candidates/. Elle ne touche pas admin_login.
- Déployer digiy-admin-session-v1 avec verify_jwt=false seulement si la validation explicite getUser + allowlist est conservée. La clé service_role reste dans Supabase, jamais dans GitHub Pages.
- Valider la page prototype sur appareil normal puis en navigation privée, avec l'admin réel ; ne jamais envoyer le PIN dans la discussion.
- Refaire les fonctions métiers d'adhésion, bonne affaire, partenaire, campus ; l'utilisateur ne doit pas pouvoir effectuer une décision avec un jeton emprunté ou sans sa session Auth correspondante.
- Refaire les autres panneaux et RPC de l'admin secondaire en liste blanche d'actions, jamais via un proxy service_role universel.
- Seulement après test de bout en bout et bascule du cockpit principal, révoquer EXECUTE à PUBLIC/anon/authenticated sur admin_login et vérifier service_role. L'ancien parcours doit rester fonctionnel jusqu'à ce moment.

## Régression / retour arrière
La PR n'altère aucune route publique, donnée, PIN ni RPC existante en production. Ne pas supprimer l'ancien code ou arrêter une infrastructure avant d'avoir identifié toutes ses dépendances. En cas d'échec du prototype, garder l'ancien parcours et isoler le problème sans toucher au PIN.

## Sécurité / limites
Le prototype est un jalon, PAS une migration complète : les fonctions métiers dépendent encore du circuit précédent. La sécurité globale reste NO GO. Les cinq tentatives constituent une limite par administrateur, pas un système de lutte contre les attaques distribuées complet. Le client stocke sa session Auth avec supabase-js et le second token seulement en sessionStorage ; protections XSS et audit des autres modules restent nécessaires.
