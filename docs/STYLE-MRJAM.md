# Intégration du socle commun

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

Présentation en elm-ui, transitions avec elm-animator dans le socle style-mrjam.
Les applications expriment état métier et intentions puis composent ce socle.
Pas de présentation Html/Html.Styled/elm-css, CSS applicatif, styles inline, HTML
injecté ni moteur d’animation local. Bootstrap minimal et adaptateurs techniques
étroits seulement : périmètre nommé, justification de la capacité manquante,
contrôle et tests. Element.html/htmlAttribute sont réservés à ces adaptateurs.
Les références de type nécessaires au navigateur restent autorisées.

elm-review central bloque la qualification des sources assemblées, y compris le
style à sa révision verrouillée. Les règles résolvent les symboles (alias/exposing),
vérifient frontières et échappatoires ; tests positifs/négatifs et fixture rejetée.
Aucun contournement par exclusions générales ou suppressions régénérées.

À qualifier pour chaque candidat : interruptions/inversions rapides, état/focus/clavier,
reduced-motion et arrêt du rafraîchissement inutile. Une action métier n’attend
pas une décoration. Préserver fonctionnalités, accessibilité et identité visuelle.
Une analyse statique ne prouve pas ces parcours navigateur.

Sources de style à révision Git exacte, récupérées pour la construction sans
copie divergente entretenue dans l’application ; artefact complet/empreintes.
Composants publiés avant manifeste. Le futur circuit de promotion appartiendra à une autorité d'exploitation séparée,
avec ses preuves et préconditions ; il reste désactivé pendant cette préparation.

Logique reste statique, avec correcteur Elm, cours, état local et reprises.
Conserver KaTeX, vidéos, ports techniques, clavier et le cadre classique du cours.
Le rendu TeX/vidéo et les gestes composent les façades communes Mathématiques,
Videos et Manipulation. Les adaptateurs privés ne sont pas importés par les vues.
Les gestes sont transitoires, hors document/certificat/historique ; le zoom est
borné50–150% et l’horloge commune s’arrête à la fin du geste. JS conserve les
événements, fichiers, géométrie et stockage ; aucun clone/style/RAF de présentation.
Les contrôles centraux et parcours navigateur qualifient la révision consommée.
