# Identité complète avant publication coordonnée

La source d'autorité est `MrJ-am/Signature`, révision
`17495b13cefa24473e37434b98336b27caec8cdf`, déclarée par la bibliothèque
`style-mrjam` verrouillée. Aucun dessin, CSS commun ou texte de signature
n'est réécrit. Le DOM conserve les six caractères ordinaires `MrJ.am`.

## Construction et contrôle

Après la construction et les tests applicatifs ordinaires :

```sh
npm run build
npm run preparer:identite
npm run test:typographie
```

`preparer:identite` contrôle toutes les empreintes de `dist`, récupère la
révision exacte de Signature et vérifie les deux blobs WOFF2 et leur licence
SIL OFL. Il compose `.cache/site-complet`, avec les polices servies localement
à côté de `signature.css`. Une police altérée fait échouer la préparation.
Le site `dist` reste inchangé et conserve ses indicateurs non publiables.

`test:typographie` sert réellement le candidat complet en HTTP, à la racine
et sous `/cours/`, sur une route profonde d'exercice, aux largeurs 320, 390,
768 et 1280 pixels. Il exige le chargement effectif des deux fontes, leurs
empreintes HTTP, les métriques originales de Signature, un texte unique sans
pseudo-contenu, l'absence de débordement et le copier-coller natif. La sélection
à la souris et le collage sont vérifiés pour `MrJ.am` puis chaque caractère,
dont le point U+002E. Les captures et empreintes vont dans
`controles-typographie`.

La largeur originale vaut 3,04 em plus 0,04 em de marge de sélection,
conformément à `web/geometry.json` et `tools/build-web.py` de Signature.
La hauteur de ligne originale vaut 1,183 em. Le contrôle porte sur Chromium ;
les gestes propres aux lecteurs mobiles, Safari et Firefox ne sont pas attestés.

Après réussite seulement, le manifeste du candidat complet et le rapport
portent `typographieValidee: true`. Le test remet cet indicateur à faux avant
toute nouvelle tentative et vérifie que les fichiers n'ont pas changé pendant
les contrôles. `hebergementConfirme` et `publicationAutorisee` restent faux.

## Archives et activation

Le workflow archive uniquement `dist`, `controles-interface` et
`controles-typographie` : les polices de l'atelier ne sont pas distribuées dans
les archives de préparation, conformément au contrat du style commun.
Le rapport conserve les empreintes du candidat complet ; il n'autorise pas
à déclarer la typographie de l'archive `dist` complète.

Le futur mécanisme privé de publication doit reconstruire à ces révisions
figées, composer le candidat complet, refaire tous les contrôles requis puis
conserver et transférer exactement les fichiers testés, sans reconstruction
après validation. La licence accompagne les fontes. La bascule attend aussi
les artefacts validés de Mémoire et Vision, le certificat de
`logique.echos.systems`, les contrôles Vimeo réels et le retour collectif.
Cette procédure n'accède pas au VPS et ne modifie pas NixOS.
