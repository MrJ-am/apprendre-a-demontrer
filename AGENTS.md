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

## Style MrJ.am et code français

- Lire `docs/STYLE-MRJAM.md` avant de modifier les interfaces. Le passage à ElmUI et à la bibliothèque commune est décidé, mais la préparation ne doit pas être présentée comme un portage ou un déploiement terminé.
- Utiliser les composants de `MrJ-am/style-mrjam` à une révision exacte, fournie à la compilation. L’appel courant est `bouton "Valider" Valider`. Les variantes expriment une sémantique, pas des options de décoration répétées dans chaque projet.
- Écrire les noms, les commentaires et la documentation en français lorsque nous les contrôlons ; garder le code lisible et compact.
- Pour les noms existants, établir une compilation de référence, renommer un seul symbole avec tous ses usages, compiler tous les consommateurs et vérifier les échanges JavaScript avant le renommage suivant. Ne pas traduire aveuglément les identifiants de contenus ou les noms externes.
- Le logo et la signature sont d’utilisation strictement réservée. `MrJ-am/Signature` est la source de référence à version précise ; conserver le texte sélectionnable `MrJ.am`.
- Une adoption du style reconstruit et redéploie tous les projets concernés, seulement après validation de tous les artefacts. Ne pas supposer qu’un artefact `dist` produit par la CI a été déployé : vérifier la cible réellement servie.
