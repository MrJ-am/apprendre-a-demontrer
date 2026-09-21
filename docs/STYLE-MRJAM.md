# Reprise : style MrJ.am

## État au 21 septembre 2026

La préparation est sur `migration/style-mrjam`, sans modification de la production. Le workflow `atelier-style.yml` a validé les sources existantes dans l’exécution `35604499617` : compilation Elm, 190 contrôles du correcteur, 299 formules KaTeX et tests des contenus. Les interfaces ne sont pas encore portées en ElmUI. Ne pas annoncer une migration achevée.

Le noyau est désormais publié dans le dépôt public `MrJ-am/style-mrjam`, sur `main`. La révision initiale à utiliser pour l’intégration est `52ad33f881b50feef91d60915d17bae90abfc592`. Son workflow de vérification `35611477400` a réussi : installation neuve, validation des sources, empreintes, compilation optimisée et tests navigateur HTTP. Lire `README.md`, `AGENTS.md`, `docs/INTEGRATION.md` et `docs/DEPLOIEMENT.md` à cette révision. Il n’est plus nécessaire de créer le dépôt ni de récupérer une archive depuis la conversation.

## Décisions communes

Toutes les interfaces passent en ElmUI. L’identité verte existante est conservée et harmonisée avec Matheval. Les composants usuels proviennent de la bibliothèque publique `MrJ-am/style-mrjam`, consommée à une révision Git complète et précise lors de la compilation. Aucune feuille de style commune mutable n’est chargée à distance.

L’appel usuel est `bouton "Valider" Valider`, sans options de bordure, couleur ou arrondi. Les variantes correspondent à des intentions distinctes. Mutualiser les compositions récurrentes sans transférer les règles pédagogiques dans la bibliothèque de style. Tout composant commun manquant doit être ajouté à la bibliothèque, pas recréé localement ; sa nouvelle révision sera ensuite adoptée de façon coordonnée.

Écrire en français tout ce qui peut l’être. Avant les renommages, compiler une référence ; renommer un seul symbole et tous ses usages, recompiler, vérifier les contrats puis seulement passer au suivant. Préserver les noms imposés par les bibliothèques, les identifiants éditoriaux et les échanges avec JavaScript tant qu’une migration compatible n’est pas définie.

## Portage à effectuer

Porter les vues de `src/Main.elm` et retirer progressivement les styles ordinaires de `public/style.css`. Conserver le correcteur Elm, les parcours, les leçons, les identifiants et les comportements existants. Vérifier les interfaces de `public/bridge.js` et `public/video.js`, les ports Elm, KaTeX, la navigation et les vidéos. Un simple enveloppement de l’ancienne vue avec `Element.html` ne constitue pas le portage.

Le logo et la signature ont pour source `MrJ-am/Signature`, révision `17495b13cefa24473e37434b98336b27caec8cdf`. Leur utilisation est strictement réservée. Conserver le texte sélectionnable `MrJ.am` et le point U+002E. Les ressources sont versionnées avec la publication, pas modifiées à distance. La bibliothèque ne contient pas les ressources typographiques : leur intégration depuis la source autorisée et le contrôle du rendu exact restent à effectuer avant publication des applications.

## Publication

Une adoption du style reconstruit et redéploie tous les projets concernés, après réussite de tous les contrôles. Le workflow actuel vérifie et produit `dist` ; `.openai/hosting.json` décrit un hébergement statique. Confirmer sa cible réelle avant de prétendre avoir raccordé cette application à l’orchestrateur VPS. Préparer et tester la migration sur sa branche ; ne pas déclencher isolément le déploiement collectif. Aucun déploiement de style n’est effectué à ce stade.
