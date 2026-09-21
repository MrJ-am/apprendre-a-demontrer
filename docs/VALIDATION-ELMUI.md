# Validation de la préparation ElmUI — 21 septembre 2026

## Référence applicative vérifiée

Branche : `migration/style-mrjam`.
Code applicatif : `8121f40c2f5966d9ffeba58aded11f9b138167dc`.
Bibliothèque compilée : `52ad33f881b50feef91d60915d17bae90abfc592`, exclusivement.
Workflow applicatif réussi : `35620873284`.
Artefact : `10650120110` (`apprendre-a-demontrer-preparation`).
SHA-256 de son archive :
`cfea96232c71d429ddf6e5ee869fd0eddb2937f1c40186fd242da257b8243056`.
Les 74 empreintes du manifeste ont été vérifiées après téléchargement.

Installation neuve, compilation optimisée, formatage, 190 contrôles du correcteur,
299 formules KaTeX et 14 tests Python réussis. La référence antérieure avait été
compilée et testée avant le portage ; aucun symbole existant n'a été renommé.

Le navigateur a réellement chargé l'artefact en HTTP, à la racine et sous `/cours/`.
Le rapport de l'artefact confirme 58 exercices (réponses incorrectes puis correctes,
indices), 12 bilans, 12 pages vidéo, 303 rendus KaTeX observés, les ports, le clavier,
la restitution du focus, l'historique, les routes profondes et les largeurs
320, 390, 768 et 1280 pixels. Aucune erreur JavaScript non gérée n'a été constatée.
Le débordement des libellés HTML héritant d'ElmUI a été corrigé avant ce succès.
Les captures à 320 et 1280 pixels ont aussi été examinées visuellement.

**Vimeo est simulé** pour le SDK, l'affiche et l'iframe externes : reprise,
destruction, erreur et réessai sont testés, pas la lecture réelle du fournisseur.
Les fichiers pédagogiques, le correcteur, `bridge.js`, `video.js` et la déclaration
d'hébergement sont inchangés, avec contrôle de leurs empreintes de référence.

## Ajouts communs préparés séparément

Dépôt : `MrJ-am/style-mrjam`.
Branche : `migration/demonstration-controles`.
Révision candidate : `e8137349cdfdfd1dc0ea488af97d005fe81e3479`.
Workflow réussi : `35621470927`.

Les composants `choixRiches`, `champIdentifie`, `lienActif`, `lienExterne` et
`boutonDevoiler` sont ajoutés dans la bibliothèque, avec galerie et contrôles
clavier, libellés accessibles, attributs sémantiques et petits écrans.
Ils ne sont **pas encore consommés par l'application** : son verrou reste 52ad33f.
Voir `docs/CONTROLES-DEMONSTRATION.md` dans cette branche de la bibliothèque.
Aucune modification de `main`, aucun changement automatique des autres projets.

## Réserves bloquant la publication

Le portage reste partiel : choix natifs à contenu mathématique, champ identifié
et sélecteur mobile restent des îlots HTML historiques. Le sélecteur compact
reste à mutualiser ; l'adoption des ajouts nécessitera une nouvelle révision
collective explicitement validée et de nouveaux tests applicatifs.

Le logo original, la feuille de signature et les droits réservés sont préservés.
Le texte `MrJ.am` est sélectionnable et son point est U+002E. Les polices autorisées
restent à intégrer depuis la source Signature ; le rendu actuel de remplacement
n'est pas validé typographiquement. Aucun fichier de police n'a été ajouté.

La cible déclarée est un hébergement statique : `dist`, projet
`appgprj_6aa90edfad00819196e1986ebec837b8` dans `.openai/hosting.json`.
Les fichiers du dépôt ne donnent pas d'URL effectivement servie. Aucun outil
d'administration de cette cible n'a été identifié parmi les connecteurs examinés.
L'adresse et le rattachement au dispositif collectif restent à confirmer ;
ne pas supposer une destination VPS et ne pas raccorder cet artefact à Nginx.

Aucun déploiement, aucune fusion de branche principale et aucune activation
collective n'ont été effectués. Les workflows restants n'ont que le droit de lire
les sources et produisent des artefacts de contrôle. Le workflow ponctuel de
transfert a été supprimé. Les indicateurs `portageComplet`, `typographieValidee`,
`hebergementConfirme` et `publicationAutorisee` restent à `false` dans le manifeste.

Les détails de conception et les commandes reproductibles figurent dans
`docs/PORTAGE-ELMUI.md`. Les commits ultérieurs ne contenant que ce compte rendu
ne changent pas le code applicatif de référence ; leur CI reconstruit néanmoins
un artefact rattaché à leur propre révision.
