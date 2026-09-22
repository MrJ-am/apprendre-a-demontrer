# Validation de la préparation ElmUI — 21 septembre 2026

## Référence fonctionnelle vérifiée

Branche : `migration/style-mrjam`.
Code applicatif : `f53e87a0c4d183f7409969d44bc0da8a838613e6`.
Bibliothèque compilée : `492afe54cba22ed49c35423d4f37dae1ba0d9944`.
Workflow applicatif réussi : `35626946268`.
Artefact : `10652083516` (`apprendre-a-demontrer-preparation`).
SHA-256 de l'archive : `c29ae4f773b134b8ccaab4a66b9a979bca1af38406f798bfd3b1a02cd2d2d2b0`.

Le noyau commun à cette révision a lui-même passé sa CI complète, workflow
`35626380932` : compilation optimisée, empreintes, galerie, interactions,
clavier et petits écrans.

## Portage

Le portage des contrôles ordinaires est complet. Les choix mathématiques à
contenu KaTeX utilisent `choixRiches`, les réponses bornées utilisent
`champIdentifieSoumis` et le sélecteur mobile utilise `selecteur`.
Les anciens îlots CSS correspondants ont été retirés de l'application.

Le correcteur, les exercices, les identifiants pédagogiques, les ports,
`bridge.js`, `video.js`, KaTeX et la navigation restent préservés.
Le manifeste de préparation porte `portageComplet: true`.

Les tests applicatifs reconstruisent le site depuis une installation neuve,
vérifient le correcteur et les données, puis servent réellement `dist` en HTTP.
Ils parcourent les 58 exercices, les 12 bilans, les pages vidéo, le clavier, les
ports, les routes profondes et les largeurs 320, 390, 768 et 1280 pixels.

**Vimeo est simulé** pour le SDK, l'affiche et l'iframe externes : les états de
reprise, destruction, erreur, réessai et position sont contrôlés, pas la lecture
réelle chez le fournisseur.

## Identité de l'archive fonctionnelle initiale

Le logo original, la signature sélectionnable `MrJ.am`, le point U+002E et les
droits réservés sont préservés depuis `MrJ-am/Signature` à la révision
`17495b13cefa24473e37434b98336b27caec8cdf`.

Les polices autorisées ne sont pas distribuées dans l'artefact de préparation ;
son indicateur `typographieValidee` reste à `false`. L'intégration complète
et les contrôles supplémentaires sont décrits dans [TYPOGRAPHIE.md](TYPOGRAPHIE.md).

## Domaine et publication

Le domaine retenu est `logique.echos.systems`. Le README le déclare aussi comme
domaine à autoriser pour l'intégration Vimeo.

La cible retenue est Nginx sur le VPS `187.77.95.158`, depuis
`/srv/logique/current`. L'ancienne déclaration `.openai/hosting.json` n'est
plus la cible souhaitée. La construction des candidats système a réussi dans
`MrJ-am/vps-infrastructure`, exécution `35659924636`, sans activation.
Le certificat réel et les contrôles du site publié restent à effectuer.

Aucun déploiement isolé, aucune fusion de branche principale et aucune activation
collective n'ont été effectués. `hebergementConfirme`, `typographieValidee`
et `publicationAutorisee` restent à `false`.
