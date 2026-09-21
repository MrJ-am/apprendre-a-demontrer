# Portage ElmUI — préparation complète, aucune activation

## État

L'application consomme exclusivement `MrJ-am/style-mrjam` à la révision
`492afe54cba22ed49c35423d4f37dae1ba0d9944`, avec ElmUI 1.1.8.
`style-mrjam.json` verrouille la révision, les modules compilables et les
ressources d'identité ; une empreinte différente ou un module supplémentaire
fait échouer la construction.

Le portage des contrôles ordinaires est terminé. La structure de page, le
catalogue, les compositions de navigation, les cartes de leçon, les scènes
pédagogiques, les retours, les indices, le clavier de symboles, les actions,
les pages vidéo, les bilans, les choix à contenu KaTeX, la saisie bornée et le
sélecteur compact utilisent ElmUI ou un composant sémantique commun de
`style-mrjam`. Le sélecteur natif est encapsulé par la bibliothèque commune,
car ElmUI ne fournit pas de `select` HTML natif.

Les styles spécialisés qui restent dans l'application concernent les ponts
techniques : KaTeX, le lecteur vidéo et le lien d'évitement. Les règles
décoratives des anciens îlots `.selection-historique`,
`.saisies-historiques`, `.choices` et `.answer-field` ont été retirées.

## Préservation

`cours/parcours.org`, `data/course.json`, `Course`, `Logic`, `Exercise`,
`public/bridge.js`, `public/video.js` et `.openai/hosting.json` restent
protégés par les contrats de référence. Les ports `reportState`,
`agentAction`, `focusElement`, les noms des outils, leurs clés JSON, les
identifiants pédagogiques et les fragments d'URL sont conservés.

Aucun renommage en masse n'a été effectué. Les nouveaux composants et
auxiliaires sont français et sémantiques ; les contrats externes restent
inchangés.

## Vérifications reproductibles

```sh
npm ci
npm test
npm run build
python3 -m pip install -r tests/requirements.txt
python3 -m playwright install --with-deps chromium
npm run test:interface
```

Les contrôles couvrent le correcteur, les formules KaTeX, la source Org, les
58 exercices, les 12 bilans, les pages vidéo, le clavier, les ports, les routes
profondes et les largeurs 320, 390, 768 et 1280 pixels. Le site est réellement
servi en HTTP pendant le test. Vimeo reste simulé pour le SDK, l'affiche et
l'iframe externes : reprise, destruction, erreur, réessai et position sont
testés, pas la lecture réelle chez le fournisseur.

## Identité

Le logo original, la signature sélectionnable `MrJ.am`, le point U+002E et la
mention de droits réservés sont préservés depuis la source autorisée
`MrJ-am/Signature` à la révision
`17495b13cefa24473e37434b98336b27caec8cdf`.

Les polices de signature ne sont pas distribuées dans l'artefact de préparation.
Le rendu typographique exact reste donc à valider au moment de l'intégration
autorisée des ressources de production ; `typographieValidee` reste faux.

## Domaine et publication

Le domaine public retenu est `logique.echos.systems`. Le README l'utilise
également comme domaine attendu pour l'autorisation d'intégration Vimeo.
La cible statique reste celle déclarée par `.openai/hosting.json` : répertoire
`dist`, projet `appgprj_6aa90edfad00819196e1986ebec837b8`.

Le DNS du domaine personnalisé doit encore être raccordé avec les valeurs
fournies par ChatGPT Sites, puis vérifié sur la cible réellement servie.
Jusqu'à cette vérification, `hebergementConfirme` reste faux.
`publicationAutorisee` reste également faux : aucun déploiement isolé ni
activation collective n'est déclenché par cette branche.

Le manifeste de préparation porte désormais `portageComplet: true`, mais
`typographieValidee`, `hebergementConfirme` et `publicationAutorisee`
restent à `false`.
