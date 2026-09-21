# Portage ElmUI — préparation, aucune activation

## Périmètre de cette étape

L'application consomme exclusivement `MrJ-am/style-mrjam` à la révision
`52ad33f881b50feef91d60915d17bae90abfc592`, avec ElmUI 1.1.8.
`style-mrjam.json` verrouille tous les modules compilables et les ressources
originales ; une empreinte différente ou un module supplémentaire fait échouer
la construction. Le cache est ignoré par Git, jamais une copie locale à éditer.

La structure de page, le catalogue, les compositions de navigation, les cartes
de leçon, les scènes pédagogiques, les retours, les indices, le clavier de
symboles, les actions, les pages vidéo et les bilans utilisent ElmUI et les
composants communs. Les compositions pédagogiques restent dans l'application.
Aucune couleur, bordure ou variante décorative de bouton n'y est dupliquée.

**Le portage n'est pas terminé.** Les choix natifs contenant du KaTeX, la saisie
bornée avec ses identifiants et le sélecteur mobile restent des îlots HTML
historiques explicites. Leur CSS est conservé seulement pour ces îlots.
Le noyau imposé ne propose pas encore leurs contrats complets ; ils ne doivent
pas être réinventés en variantes ElmUI locales. Les ajouts communs seront testés
dans la bibliothèque puis adoptés avec une nouvelle révision coordonnée.
Les liens actifs méritent également une variante sémantique commune avant de
retirer les derniers marqueurs de navigation historiques.

## Préservation

`cours/parcours.org`, `data/course.json`, `Course`, `Logic`, `Exercise`,
`public/bridge.js`, `public/video.js` et `.openai/hosting.json` sont inchangés.
`tests/contrats-reference.json` contient leurs empreintes depuis la référence
`7b434fc77334e5553cbe481194c28220523bbc33`.

Les ports `reportState`, `agentAction`, `focusElement`, les noms des trois outils,
leurs clés JSON, les identifiants éditoriaux et les fragments d'URL sont conservés.
La largeur du navigateur est un nouvel état purement visuel ; elle ne modifie pas
les réponses. Aucun renommage de symbole existant n'a été effectué dans cette
étape : les nouveaux auxiliaires sont en français, les noms historiques restent
stables jusqu'à leur migration individuelle compilée et testée.

## Vérifications reproductibles

```sh
npm ci
npm test
npm run build
python3 -m pip install -r tests/requirements.txt
python3 -m playwright install --with-deps chromium
npm run test:interface
```

Les tests existants couvrent 190 contrôles du correcteur, 299 formules KaTeX
et la source Org. Les nouveaux contrôles refusent les caches altérés et vérifient
les contrats immuables. Le test navigateur sert réellement `dist` en HTTP à la
racine et sous `/cours/` ; il exerce les 58 interfaces, les 12 bilans, les pages
vidéo, le clavier, les ports, les routes profondes et quatre largeurs.
Les services externes Vimeo sont **simulés** : reprise, destruction, erreur,
réessai et position sont contrôlés, pas la lecture réelle chez le fournisseur.
Le rapport et les captures sont produits dans `controles-interface/`.
La compilation et les tests du correcteur ont été exécutés dans l'atelier hors
ligne. L'HTTP est bloqué par Chromium dans cet atelier : le contrôle HTTP doit
être établi par le workflow applicatif, pas déduit de la CI de la bibliothèque.

## Identité : exactitude typographique non validée

Logo et feuille de signature sont copiés sans modification, avec vérification
SHA-256, depuis les ressources rattachées à Signature
`17495b13cefa24473e37434b98336b27caec8cdf`. Le logo conserve son original.
La signature demeure du texte `MrJ.am` sélectionnable, avec le point U+002E,
et la mention de droits réservés est visible.

Les deux polices autorisées ne sont pas distribuées dans cette préparation.
Le navigateur peut donc charger une police de remplacement et signaler les
ressources typographiques absentes. Cela n'est **pas** le rendu de signature
validé : leur intégration vérifiée depuis la source autorisée reste un préalable
à toute publication. Ne pas approuver les captures comme référence typographique.

## Hébergement et publication

Le dépôt déclare `.openai/hosting.json`, sortie statique `dist`, projet
`appgprj_6aa90edfad00819196e1986ebec837b8`. Les workflows de vérification produisent
un artefact, sans action d'activation ni destination VPS. Aucune URL publique
réellement servie ni correspondance à un domaine VPS n'a pu être établie à partir
de ces fichiers. La cible reste donc **à confirmer auprès de l'hébergement**.
Ne pas raccorder cet artefact à Nginx ni prétendre avoir confirmé la production.

`dist/manifeste-preparation.json` enregistre les révisions exactes et les
empreintes de l'artefact, avec `publicationAutorisee`, `portageComplet`,
`typographieValidee` et `hebergementConfirme` à `false`.
L'orchestrateur collectif devra lever ces réserves, valider tous les projets
et activer les artefacts déjà testés ensemble. Aucun déploiement isolé ici.
