# Reprise : style MrJ.am

## État au 21 septembre 2026

La préparation est sur `migration/style-mrjam`, sans modification de la production. Le portage ElmUI est complet et contrôlé ; `docs/VALIDATION-ELMUI.md` conserve les preuves. Le workflow `atelier-style.yml` et son exécution `35604499617` constituent la référence historique avant portage.

La révision consommée de `MrJ-am/style-mrjam` est `492afe54cba22ed49c35423d4f37dae1ba0d9944`, verrouillée dans `style-mrjam.json`. Lire `README.md`, `AGENTS.md`, `docs/INTEGRATION.md` et `docs/DEPLOIEMENT.md` à cette révision. La révision initiale `52ad33f881b50feef91d60915d17bae90abfc592` reste une référence historique.

## Décisions communes

Toutes les interfaces passent en ElmUI. L’identité verte existante est conservée et harmonisée avec Matheval. Les composants usuels proviennent de la bibliothèque publique `MrJ-am/style-mrjam`, consommée à une révision Git complète et précise lors de la compilation. Aucune feuille de style commune mutable n’est chargée à distance.

L’appel usuel est `bouton "Valider" Valider`, sans options de bordure, couleur ou arrondi. Les variantes correspondent à des intentions distinctes. Mutualiser les compositions récurrentes sans transférer les règles pédagogiques dans la bibliothèque de style. Tout composant commun manquant doit être ajouté à la bibliothèque, pas recréé localement ; sa nouvelle révision sera ensuite adoptée de façon coordonnée.

Écrire en français tout ce qui peut l’être. Avant les renommages, compiler une référence ; renommer un seul symbole et tous ses usages, recompiler, vérifier les contrats puis seulement passer au suivant. Préserver les noms imposés par les bibliothèques, les identifiants éditoriaux et les échanges avec JavaScript tant qu’une migration compatible n’est pas définie.

## Contrats à préserver

Les vues de `src/Main.elm` utilisent les composants communs ; `public/style.css` garde les ponts techniques. Conserver le correcteur Elm, les parcours, les leçons, les identifiants et les comportements existants. Vérifier les interfaces de `public/bridge.js` et `public/video.js`, les ports Elm, KaTeX, la navigation et les vidéos.

Le logo et la signature ont pour source `MrJ-am/Signature`, révision `17495b13cefa24473e37434b98336b27caec8cdf`. Leur utilisation est strictement réservée. Conserver le texte sélectionnable `MrJ.am` et le point U+002E. Les ressources sont versionnées avec la publication, pas modifiées à distance. `npm run preparer:identite` récupère et vérifie les polices originales dans un atelier exclu des archives de préparation ; `npm run test:typographie` vérifie le rendu et le copier-coller natif. Lire `docs/TYPOGRAPHIE.md`.

## Publication

La cible retenue est `https://logique.echos.systems`, servie par Nginx sur le VPS administré par `MrJ-am/vps-infrastructure`, depuis `/srv/logique/current`. `.openai/hosting.json` reste une trace historique, pas une instruction de publication. Les candidats système sont construits sans activation ; le certificat réel et la publication restent à effectuer dans le mécanisme coordonné avec Mémoire et Vision. Cette application ne reconstruit pas NixOS et ne dispose d'aucun workflow de déploiement isolé.

## Candidat documentaire du 26 septembre 2026

Le verrou candidat adopte `3aab7233465ac0abe49464fa26a360765ccb4004`.
Les contrôles courants et tableaux sont factorisés dans le style ; les boutons
courts ont une cible nominale de 34 px. Les attentes de densité des tests suivent
ce contrat, sans copie de décoration dans l’application.

La reconstruction et la suite navigateur ont réussi : 58 exercices, 12 bilans,
12 pages vidéo, clavier et quatre largeurs. Les services vidéo externes sont
simulés explicitement. Les contrôles distants, notamment typographiques, restent
requis avant activation.

La reconstruction finale conserve les SHA-256 des bundles soumis aux tests.
Ce candidat est préparé localement : aucune nouvelle publication ni activation
n’est revendiquée. L’adoption doit être coordonnée avec Vision et l’autre
consommateur, après toutes les validations, avec retour applicatif conservé.
