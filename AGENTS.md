# Composant Logique

La préparation Rust/Elm du 28 octobre 2026 gèle tous les déploiements.
L'assemblage applicatif est dans [mrjam-plateforme](https://github.com/MrJ-am/mrjam-plateforme),
les propositions de règles indépendantes dans [mrjam-validation](https://github.com/MrJ-am/mrjam-validation),
et l'environnement de développement dans [vps-infrastructure/environment](https://github.com/MrJ-am/vps-infrastructure/tree/main/environment).
La forge cible est https://forge.mrj.am ; son raccordement et les ACL restent à établir.
Ne créer ni workflow, ni déclencheur de déploiement dans ce dépôt.
Une vérification locale ne vaut ni qualification complète ni autorisation de production.
Conserver les révisions exactes des dépendances, les licences et les ressources réservées.
Aucune donnée personnelle, aucun accès de production, aucun secret dans le dépôt.
L'historique Git conserve les versions antérieures ; aucune réécriture forcée.

Présentation avec elm-ui et transitions avec elm-animator dans style-mrjam.
Les applications gardent leur état métier. Pas de présentation HTML/CSS parallèle,
de suppression générale des règles ou de mise à jour implicite du style vers HEAD.
Les adaptateurs techniques restent étroits, nommés et testés ; les parcours clavier,
focus, interruptions, inversion, reduced-motion et repos restent à qualifier.
Les règles canoniques proposées sont dans mrjam-validation/review.
La compilation et elm-review sont rejouables avec son dossier frontend-qualification.

Logique reste un site statique : interface, correcteur et état pédagogique en Elm.
Node et Python servent à la construction et aux tests locaux.

Modifier les contenus dans `cours/parcours.org` ; générer et vérifier
`data/course.json` par les commandes centrales, sans édition manuelle des données
générées. Conserver identifiants des parcours/leçons/exercices. Qualifier le
correcteur après impact : corrections mathématiques, réponses alternatives,
portées et cadre classique du cours. Garder l’état local et ses reprises.

Lire `docs/STYLE-MRJAM.md` avant une modification d’interface. Réutiliser le
style verrouillé, préserver compacité/tactile/clavier et identité visuelle.
Les vidéos provisoires restent annoncées ; le support LaTeX original privé
ne devient pas public sans instruction de son auteur. Logo/signature réservés,
source Signature, texte sélectionnable `MrJ.am`. Noms français sous notre
contrôle ; aucun renommage aveugle des contenus ou contrats externes.
