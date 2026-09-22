# Domaine et interface — 22 septembre 2026

La cible contractuelle est `https://logique.echos.systems/`. La préparation
d'infrastructure antérieure n'avait pas été activée ; un domaine sans hôte Nginx
dédié recevait le site par défaut Matheval et sa redirection `/matheval/`.
La correction du serveur et sa preuve de publication relèvent du dépôt privé VPS.
Ne pas déduire une publication de cette branche ni d'une CI réussie.

La révision commune du style corrige le dimensionnement des pages et fenêtres
pour la hauteur visible. Les tests parcourent les 58 exercices, les 12 leçons,
les routes profondes, le clavier et quatre largeurs d'écran.

Les affiches distantes ne sont plus chargées avant activation. Tous les lecteurs
externes passent par le composant avec information préalable, activation volontaire
et arrêt. Vimeo reçoit `dnt=1` ; ce paramètre seul n'est pas une preuve d'absence
de traceurs. Aucune préférence de consentement n'est mémorisée automatiquement.
Le parcours et la reprise vidéo vivent en mémoire dans cette version ; le site
n'a ni compte, ni mot de passe, ni collecte d'adresse électronique.

L'archive de préparation conserve ses règles antérieures. L'artefact distinct
`site-logique-verifie` contient les fontes originales autorisées pour la publication,
seulement après leur contrôle typographique ; il reste soumis aux vérifications
d'hébergement, aux validations des autres consommateurs et au retour arrière VPS.
