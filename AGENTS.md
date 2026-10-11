# Composant Logique

L’assemblage, les commandes locales et toute la CI/CD appartiennent à
[MrJ-am/vps-infrastructure](https://github.com/MrJ-am/vps-infrastructure).
Lire le [contrat central](https://github.com/MrJ-am/vps-infrastructure/blob/main/coordination/CONTRATS.org),
le [manifeste](https://github.com/MrJ-am/vps-infrastructure/blob/main/assemblage/manifest.json)
et les [commandes de développement](https://github.com/MrJ-am/vps-infrastructure/blob/main/assemblage/DEVELOPPEMENT.md).
Interfaces Elm : elm-ui pour la présentation et elm-animator pour les transitions,
mutualisés dans style-mrjam. Pas de Html/Html.Styled/elm-css, CSS/HTML applicatif ou
animation ad hoc. Adaptateurs techniques étroits, documentés/testés ; Element.html
et htmlAttribute bornés. elm-review central obligatoire, sans suppressions/exclusions
générales ; tests des règles et parcours Continuous UI (interruptions/inversions,
focus/clavier/reduced-motion, rafraîchissement arrêté). Lire le
[contrat frontend](https://github.com/MrJ-am/vps-infrastructure/blob/main/assemblage/FRONTENDS.md).

Ce dépôt conserve ses sources, contrats et tests ; publier son commit avant
référencement central. Aucun workflow satellite, publication autonome, échange
obligatoire entre conversations ou acquittement. L’intégration centrale et les
tests pertinents valident un changement.

Préserver les modifications concurrentes, les données et les secrets. Commits
français, push sans force ; aucune PR ni modification de visibilité ou licence.
Une compilation ou un test local ne prouve pas une publication : citer les
révisions et les contrôles de la version réellement servie. Les anciennes règles
sont conservées dans `coordination/historique/AGENTS-avant-composants-20261011.md`.

Le projet est statique : interface, correcteur et état pédagogique restent en
Elm/ElmUI. Aucun backend ou système ASDF artificiel. JavaScript est réservé à
KaTeX, au navigateur et aux intégrations légitimes. L’infrastructure construit
et publie les ressources aux domaines et chemins existants.

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
