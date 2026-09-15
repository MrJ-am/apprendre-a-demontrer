# Apprendre à démontrer

- Le site est développé en Elm. Garder le correcteur et l’état pédagogique dans Elm ; réserver JavaScript au rendu KaTeX, au navigateur et aux intégrations.
- Modifier les contenus dans `cours/parcours.org`. Générer `data/course.json` avec `npm run build:data`, puis vérifier avec `npm run check:data`. Ne pas modifier les données générées à la main.
- Conserver les identifiants des parcours, leçons et exercices lorsqu’ils représentent les mêmes contenus.
- Vérifier les corrections mathématiques, les réponses alternatives et les conditions de portée. Les exercices de formalisation utilisent le cadre classique annoncé dans le cours.
- Utiliser `npm test` pour les changements du correcteur ou des données. Utiliser `npm run build` pour les changements du site avant publication.
- Préserver l’identité visuelle, la compacité sur téléphone, les cibles tactiles et la navigation au clavier.
- Les vidéos provisoires restent explicitement annoncées comme telles jusqu’à la fourniture d’un identifiant réel.
- Le support LaTeX original fourni dans la conversation sert de référence ; son ajout à un dépôt public exige une demande explicite de l’auteur.
- Enregistrer les changements avec un message de commit en français, puis synchroniser le dépôt demandé.
