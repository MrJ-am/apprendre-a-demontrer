module Atelier.Vue exposing (vue)

import Atelier.Editeur as Ed exposing (Message(..), Modele)
import Atelier.Exemples as Ex
import Atelier.Formule as F exposing (Formule(..))
import Atelier.Graphe as G
import Atelier.Noyau as N
import Atelier.Regles as R
import Atelier.Types exposing (..)
import Dict
import Element as UI exposing (Element)
import Element.Background as Fond
import Element.Border as Bordure
import Element.Font as Police
import Element.Region as Region
import MrJam as M
import MrJam.Accessibilite as A
import MrJam.Blocs as B
import MrJam.Identite as Identite
import MrJam.Manipulation as Manipulation
import Set


{-| Un aperçu réutilise les pièces, sans recopier leurs identifiants ni cibles.
-}
marquer : Bool -> (String -> UI.Attribute msg) -> String -> UI.Attribute msg
marquer apercu marque valeur =
    if apercu then
        UI.alpha 1

    else
        marque valeur


zoneDestination : Bool -> Modele -> String -> List (UI.Attribute msg)
zoneDestination apercu m valeur =
    if apercu then
        []

    else
        Manipulation.cible m.geste valeur


repere : String -> Element msg -> Element msg
repere id =
    UI.el [ UI.width (UI.minimum 0 UI.fill), A.identifiant id ]


texte : String -> Element msg
texte =
    M.paragraphe


petit : String -> Element msg
petit s =
    UI.paragraph [ UI.width UI.shrink, Police.size 12 ] [ UI.text s ]


ligne : List (Element msg) -> Element msg
ligne =
    UI.row [ UI.spacing 5 ]


source : Bool -> Modele -> String -> String -> Element Message
source apercu m id libelle =
    UI.el
        ([ marquer apercu Manipulation.source id, marquer apercu Manipulation.test id ]
            ++ (if apercu then
                    []

                else
                    Manipulation.prise m.geste id
               )
        )
        (B.poignee libelle (Choisir id))


operateur : Formule -> ( String, List Formule )
operateur f =
    case f of
        Et a b ->
            ( "∧", [ a, b ] )

        Ou a b ->
            ( "∨", [ a, b ] )

        Implique a b ->
            ( "⇒", [ a, b ] )

        Equivalent a b ->
            ( "⇔", [ a, b ] )

        Non a ->
            ( "¬", [ a ] )

        Trou _ ->
            ( "…", [] )

        _ ->
            ( F.afficher f, [] )


avecOperateur : Element msg -> List (Element msg) -> Element msg
avecOperateur signe enfants =
    case enfants of
        [ a, b ] ->
            ligne [ a, signe, b ]

        [ a ] ->
            ligne [ signe, a ]

        _ ->
            signe


formuleFixe : Formule -> Element msg
formuleFixe =
    formuleNiveau 0


formuleNiveau : Int -> Formule -> Element msg
formuleNiveau niveau f =
    let
        ( signe, enfants ) =
            operateur f
    in
    (case f of
        Trou _ ->
            B.logementImbrique []

        _ ->
            B.propositionNiveau niveau []
    )
        (avecOperateur (UI.text signe) (List.map (formuleNiveau (niveau + 1)) enfants))


{-| Chaque sous-proposition possède une adresse syntaxique. Le dépôt se fait
sur le logement réellement désigné, même après zoom ou défilement du canevas.
-}
formuleDirecte : Bool -> Modele -> String -> List Int -> Formule -> Element Message
formuleDirecte apercu m base chemin f =
    let
        reference =
            base
                ++ (if List.isEmpty chemin then
                        ""

                    else
                        "|" ++ (List.map String.fromInt chemin |> String.join ".")
                   )

        destination =
            "formule:" ++ reference

        ( signe, enfants ) =
            operateur f

        action =
            if m.source == Nothing then
                EditerFormule reference

            else
                Placer destination

        attributs =
            [ marquer apercu Manipulation.source ("prop:" ++ reference), marquer apercu Manipulation.sousFormule reference ]
                ++ (if apercu then
                        []

                    else
                        Manipulation.prise m.geste ("prop:" ++ reference)
                   )
                ++ (if apercu then
                        []

                    else
                        Manipulation.cible m.geste destination
                   )

        bouton =
            B.commande [ Region.description ("Modifier " ++ reference), A.infoBulle (F.afficher f) ] (UI.text signe) action
    in
    (case f of
        Trou _ ->
            B.logementImbrique attributs

        _ ->
            B.propositionNiveau (List.length chemin) attributs
    )
        (avecOperateur bouton (List.indexedMap (\i enfant -> formuleDirecte apercu m base (chemin ++ [ i ]) enfant) enfants))


champFormule : String -> String -> Formule -> Element Message
champFormule cible libelle f =
    UI.el [ Manipulation.formule cible ]
        (ligne [ petit libelle, B.proposition [] (B.commande [ Region.description ("Modifier " ++ cible) ] (UI.text (F.afficher f)) (EditerFormule cible)) ])


champDirect : Modele -> String -> Formule -> Element Message
champDirect m cible f =
    UI.el [ Manipulation.formule cible ] (formuleDirecte False m cible [] f)


classique : Bibliotheque -> Regle -> Bool
classique bibliotheque regle =
    case regle of
        Primitive "RA" ->
            True

        Application id version ->
            trouverDefinition bibliotheque id version |> Maybe.map (N.verifierDefinition bibliotheque >> Result.map .classique >> Result.withDefault False) |> Maybe.withDefault False

        _ ->
            False


etat : Result Probleme Verdict -> ( B.Etat, String )
etat resultat =
    case resultat of
        Ok v ->
            ( B.Verifie
            , if v.classique then
                "✓ Vérifiée · règle classique"

              else
                "✓ Vérifiée"
            )

        Err (Incomplet s) ->
            ( B.ACompleter, "○ À compléter · " ++ s )

        Err (Erreur s) ->
            ( B.Incorrect, "! Erreur · " ++ s )


titreCourt : Bibliotheque -> Regle -> String
titreCourt bibliotheque regle =
    case regle of
        Primitive "etI" ->
            "réunir"

        Primitive "implI" ->
            "si"

        Primitive "implE" ->
            "appliquer ⇒"

        Primitive "etG" ->
            "garder à gauche"

        Primitive "etD" ->
            "garder à droite"

        Primitive "ouG" ->
            "introduire ∨ gauche"

        Primitive "ouD" ->
            "introduire ∨ droite"

        Primitive "ouE" ->
            "raisonner par cas"

        Primitive "fauxE" ->
            "depuis ⊥"

        Primitive "RA" ->
            "par l’absurde · classique"

        Reference _ ->
            "utiliser"

        Enchainement ->
            "enchaîner"

        _ ->
            R.nom bibliotheque regle


zone : Bool -> Modele -> G.Cible -> Formule -> Bool -> Element Message
zone apercu m cible attendu vide =
    let
        identite =
            "preuve:" ++ G.cibleTexte cible

        depart =
            vide && cible.parent == "racine"

        libelle =
            if depart then
                "Glisser une règle ici"

            else if vide then
                "preuve de " ++ F.afficher attendu

            else
                "+"
    in
    B.cavite
        ([ marquer apercu Manipulation.test identite
         , UI.width
            (if depart then
                UI.px 200

             else
                UI.shrink
            )
         , UI.paddingXY
            (if depart then
                17

             else
                4
            )
            (if depart then
                20

             else
                2
            )
         ]
            ++ zoneDestination apercu m identite
        )
        (B.commande
            [ Region.description
                (if vide then
                    "Démontrer " ++ F.afficher attendu

                 else
                    "Insérer une étape ici"
                )
            ]
            (UI.text libelle)
            (Placer identite)
        )


sequence : Bool -> Bool -> Modele -> String -> Int -> Contexte -> Formule -> List Preuve -> Element Message
sequence lecture apercu m parent indice contexte attendu preuves =
    let
        avancer ( index, preuve ) ( ctx, accumulees ) =
            let
                suivant =
                    N.verifierBloc m.document.bibliotheque ctx preuve |> Result.map (\v -> Dict.insert (identifiant preuve) v ctx) |> Result.withDefault ctx

                avant =
                    if lecture then
                        []

                    else
                        [ zone apercu m { parent = parent, indice = indice, position = index } attendu False ]
            in
            ( suivant, accumulees ++ avant ++ [ bloc lecture apercu m ctx preuve ] )

        ( _, vues ) =
            List.foldl avancer ( contexte, [] ) (List.indexedMap Tuple.pair preuves)
    in
    UI.column [ UI.spacing 0, UI.alignLeft ]
        (vues
            ++ (if lecture then
                    []

                else
                    [ zone apercu m { parent = parent, indice = indice, position = List.length preuves } attendu (List.isEmpty preuves) ]
               )
        )


bloc : Bool -> Bool -> Modele -> Contexte -> Preuve -> Element Message
bloc lecture apercu m contexte ((Bloc b) as preuve) =
    let
        bibliotheque =
            m.document.bibliotheque

        resultat =
            N.verifierBloc bibliotheque contexte preuve

        ( statut, message ) =
            etat resultat

        contrat =
            R.contrat bibliotheque b

        ferme =
            Set.member b.id m.repli && not lecture

        params =
            R.parametres bibliotheque b.regle |> List.filterMap (\p -> Dict.get p b.parametres |> Maybe.map (Tuple.pair p))

        entete =
            ligne
                ([ if lecture then
                    UI.text (titreCourt bibliotheque b.regle)

                   else
                    source apercu m ("bloc:" ++ b.id) (titreCourt bibliotheque b.regle)
                 ]
                    ++ List.map
                        (\( p, f ) ->
                            if lecture then
                                formuleFixe f

                            else
                                UI.el [ marquer apercu Manipulation.formule ("param:" ++ b.id ++ ":" ++ p) ] (formuleDirecte apercu m ("param:" ++ b.id ++ ":" ++ p) [] f)
                        )
                        params
                    ++ [ if lecture then
                            UI.none

                         else
                            B.commande [ Region.description "Inspecter", A.infoBulle "Inspecter, dupliquer, créer un théorème" ] (UI.text "⋯") (Selectionner b.id)
                       ]
                )

        cavites =
            case contrat of
                Err _ ->
                    []

                Ok c ->
                    List.map2
                        (\( i, e ) ps ->
                            UI.column [ UI.spacing 4, UI.alignLeft ]
                                [ ligne
                                    [ petit
                                        (if List.isEmpty e.hypotheses then
                                            "prouver"

                                         else
                                            "sous"
                                        )
                                    , if List.isEmpty e.hypotheses then
                                        formuleFixe e.conclusion

                                      else
                                        ligne (List.map (.formule >> formuleFixe) e.hypotheses)
                                    , if lecture then
                                        UI.none

                                      else
                                        B.commande [ Region.description "Faits dans cette cavité", A.infoBulle "Faits disponibles ici" ] (UI.text "☰") (ChoisirCavite { parent = b.id, indice = i, position = List.length ps })
                                    ]
                                , sequence lecture apercu m b.id i (N.ajouterHypotheses e.hypotheses contexte) e.conclusion ps
                                ]
                        )
                        (List.indexedMap Tuple.pair c.entrees)
                        b.entrees

        conclusion =
            contrat |> Result.map .conclusion |> Result.withDefault (Trou "sortie")

        pied =
            UI.column [ UI.spacing 3 ]
                [ if ferme then
                    petit (contrat |> Result.map (\c -> "Entrées : " ++ String.join " ; " (List.map (.conclusion >> F.afficher) c.entrees)) |> Result.withDefault "Contrat invalide")

                  else
                    UI.none
                , ligne
                    [ UI.text "donc"
                    , formuleFixe conclusion
                    , UI.el [ A.infoBulle message, Region.description message ]
                        (UI.text
                            (case resultat of
                                Ok _ ->
                                    "✓"

                                Err (Incomplet _) ->
                                    "○"

                                _ ->
                                    "!"
                            )
                        )
                    , if classique bibliotheque b.regle then
                        petit "classique"

                      else
                        UI.none
                    ]
                ]
    in
    B.emboitable
        (if m.selection == Just b.id && not lecture then
            B.Selectionne

         else
            statut
        )
        ([ marquer apercu Manipulation.bloc b.id ]
            ++ (if lecture then
                    []

                else
                    [ marquer apercu Manipulation.piece ("bloc:" ++ b.id) ]
               )
        )
        entete
        (if ferme then
            []

         else
            cavites
        )
        pied


paletteRegle : Bool -> Modele -> Regle -> Element Message
paletteRegle apercu m regle =
    let
        id =
            case regle of
                Primitive r ->
                    "regle:" ++ r

                Application nom version ->
                    "theoreme:" ++ nom ++ ":" ++ String.fromInt version

                _ ->
                    ""

        noms =
            R.parametres m.document.bibliotheque regle

        b =
            case R.creer m.document.bibliotheque "apercu" regle (List.map (\p -> ( p, Parametre p )) noms |> Dict.fromList) of
                Bloc contenu ->
                    contenu

        contrat =
            R.contrat m.document.bibliotheque b

        cavites =
            contrat |> Result.map (.entrees >> List.map (\p -> ligne [ petit "preuve", formuleFixe p.conclusion ])) |> Result.withDefault []

        conclusion =
            contrat |> Result.map .conclusion |> Result.withDefault (Trou "sortie")
    in
    B.emboitableAvec B.Miniature
        B.Neutre
        [ marquer apercu Manipulation.piece id ]
        (source apercu m id (titreCourt m.document.bibliotheque regle))
        cavites
        (ligne
            [ UI.text "→"
            , formuleFixe conclusion
            , if classique m.document.bibliotheque regle then
                petit "classique"

              else
                UI.none
            ]
        )


faits : Modele -> Element Message
faits m =
    let
        ctx =
            Ed.contexte m m.cible |> Maybe.map Tuple.first |> Maybe.withDefault (N.contexteInitial m.document.premisses)
    in
    UI.column [ UI.spacing 12, UI.width UI.fill ]
        [ petit "Chaque utilisation crée une référence. Un fait reste disponible."
        , if Dict.isEmpty ctx then
            petit "Aucun fait ici. Sélectionnez une cavité ou déclarez une prémisse."

          else
            UI.column [ UI.spacing 12 ]
                (Dict.toList ctx |> List.map (\( id, v ) -> B.emboitable B.Neutre [ Manipulation.piece ("fait:" ++ id) ] (ligne [ source False m ("fait:" ++ id) "utiliser", formuleFixe v.conclusion ]) [] UI.none))
        ]


arbreFormule : Modele -> List Int -> Formule -> Element Message
arbreFormule m chemin f =
    let
        adresse =
            List.map String.fromInt chemin |> String.join "."

        cible =
            "formule:trou:" ++ adresse

        ( signe, enfants ) =
            operateur f

        bouton =
            B.commande []
                (UI.text signe)
                (if m.source == Nothing then
                    CheminFormule chemin

                 else
                    Placer cible
                )
    in
    (case f of
        Trou _ ->
            B.logementImbrique

        _ ->
            B.propositionNiveau (List.length chemin)
    )
        ([ Manipulation.chemin adresse ] ++ Manipulation.cible m.geste cible)
        (avecOperateur bouton (List.indexedMap (\i enfant -> arbreFormule m (chemin ++ [ i ]) enfant) enfants))


palettePropositions : Modele -> Element Message
palettePropositions m =
    let
        connecteur ( r, signe ) =
            let
                contenu =
                    Ed.connecteur r

                ( _, enfants ) =
                    operateur contenu

                bouton =
                    B.commande [ Region.description signe ]
                        (UI.text signe)
                        (if m.cibleFormule /= Nothing then
                            Connecteur r

                         else
                            Choisir ("connecteur:" ++ r)
                        )
            in
            B.proposition ([ Manipulation.source ("connecteur:" ++ r) ] ++ Manipulation.prise m.geste ("connecteur:" ++ r))
                (avecOperateur bouton (List.map (\_ -> B.logementImbrique [] (UI.text "…")) enfants))
    in
    UI.column [ UI.spacing 14, UI.alignLeft ]
        ([ petit "Glisser dans un emplacement vert."
         , UI.wrappedRow [ UI.spacing 6, UI.width UI.fill ] (List.map (\a -> B.proposition [ Manipulation.piece ("atome:" ++ a) ] (source False m ("atome:" ++ a) a)) [ "A", "B", "C", "D", "P", "Q", "R", "S" ])
         ]
            ++ List.map connecteur [ ( "et", "∧" ), ( "ou", "∨" ), ( "implique", "⇒" ), ( "non", "¬" ), ( "equivalent", "⇔" ), ( "faux", "⊥" ) ]
        )


composeur : Modele -> Element Message
composeur m =
    UI.column [ UI.width UI.fill, UI.spacing 12 ]
        [ palettePropositions m
        , UI.el [ UI.width UI.fill ]
            (M.pile
                [ M.sousTitre "Proposition"
                , arbreFormule m [] m.brouillon
                , source False m "prop:brouillon" (F.afficher m.brouillon)
                , M.bouton "Utiliser cette proposition" AppliquerFormule
                , M.champ "Nom de l’atome" m.nomAtome NomAtome
                , M.boutonSecondaire "Insérer cet atome" InsererAtome
                , M.champ "Saisie textuelle facultative" m.texteFormule TexteFormule
                , M.boutonSecondaire "Lire la saisie" AnalyserFormule
                , M.boutonSecondaire "Fermer le composeur" FermerFormule
                ]
            )
        ]


inspecteur : Modele -> Element Message
inspecteur m =
    case Ed.selectionnee m of
        Nothing ->
            texte "Sélectionnez un bloc avec Inspecter pour modifier ses paramètres, le replier ou créer un théorème."

        Just ( b, ctx ) ->
            let
                formule p =
                    Dict.get p b.parametres |> Maybe.withDefault (Trou p)

                application =
                    case b.regle of
                        Application _ _ ->
                            True

                        _ ->
                            False

                detail =
                    N.verifierBloc m.document.bibliotheque ctx (Bloc b) |> etat |> Tuple.second
            in
            M.pile
                [ repere "atelier-inspecteur" (M.sousTitre (R.nom m.document.bibliotheque b.regle))
                , M.texteSecondaire detail
                , M.pile (R.parametres m.document.bibliotheque b.regle |> List.map (\p -> champFormule ("param:" ++ b.id ++ ":" ++ p) (p ++ " := ") (formule p)))
                , M.actions
                    [ M.boutonSecondaire
                        (if Set.member b.id m.repli then
                            "Déplier"

                         else
                            "Replier"
                        )
                        Replier
                    , M.boutonSecondaire "Dupliquer" Dupliquer
                    ]
                , M.bouton "Créer un théorème" PreparerExtraction
                , if application then
                    M.pile [ M.boutonSecondaire "Voir la démonstration" Inspecter, M.boutonSecondaire "Développer cette occurrence" Developper ]

                  else
                    UI.none
                , M.boutonDestructif "Retirer ce bloc" Supprimer
                , M.texteSecondaire "Le repli masque le contenu. L’extraction crée une définition. Le développement remplace une occurrence par son certificat instancié."
                ]


extraction : Modele -> Element Message
extraction m =
    case m.extraction of
        Nothing ->
            UI.none

        Just e ->
            M.section "Créer un théorème : vérifier son contrat"
                [ M.champ "Nom du théorème" e.nom NomTheoreme
                , M.caseACocher "Inclure les étapes précédentes de cette cavité" e.sequence EtendueExtraction
                , M.texteSecondaire "Généralisation explicite : les atomes cochés deviennent des paramètres propositionnels. Les prémisses restent obligatoires."
                , M.actions (Set.toList e.atomes |> List.map (\a -> M.caseACocher ("Paramètre " ++ a) (Set.member a e.generalises) (Generaliser a)))
                , M.selecteur "Définition" (( "nouveau", "Créer une nouvelle définition" ) :: (m.document.bibliotheque |> List.filter (\d -> not (String.startsWith "fourni-" d.id)) |> List.map (\d -> ( d.id, "Nouvelle version de " ++ d.nom )))) (Maybe.withDefault "nouveau" e.versionDe) VersionDe
                , case Ed.propositionExtraction m of
                    Err p ->
                        M.avis M.Avertissement (messageProbleme p)

                    Ok def ->
                        M.pile
                            [ texte ("Paramètres : " ++ String.join ", " def.parametres)
                            , texte ("Entrées nécessaires : " ++ String.join " ; " (List.map (.conclusion >> F.afficher) def.entrees))
                            , texte ("Conclusion : " ++ F.afficher def.conclusion)
                            , M.texteSecondaire "Les hypothèses introduites et déchargées dans la sélection restent à l’intérieur du certificat. La construction actuelle est conservée."
                            , M.bouton "Enregistrer dans Mes théorèmes" EnregistrerTheoreme
                            ]
                , M.boutonSecondaire "Annuler l’extraction" FermerExtraction
                ]


palette : Modele -> Element Message
palette m =
    let
        regles =
            if m.panneau == "utiliser" then
                List.map Primitive [ "etG", "etD", "implE", "ouE", "fauxE", "RA" ] ++ List.map (\id -> Application id 1) [ "fourni-contradiction", "fourni-double-non", "fourni-equivG", "fourni-equivD" ]

            else
                List.map Primitive [ "etI", "implI", "ouG", "ouD" ] ++ List.map (\id -> Application id 1) [ "fourni-nonI", "fourni-equivI" ]

        contenu =
            if m.extraction /= Nothing then
                extraction m

            else if m.cibleFormule /= Nothing then
                composeur m

            else
                case m.panneau of
                    "faits" ->
                        faits m

                    "inspecter" ->
                        UI.el [ UI.width UI.fill ] (inspecteur m)

                    "formules" ->
                        palettePropositions m

                    "enonce" ->
                        M.pile
                            ([ M.sousTitre "Prémisses", petit "Données admises dans cet exercice." ]
                                ++ List.map (\h -> M.pile [ champDirect m ("premisse:" ++ h.id) h.formule, M.boutonSecondaire "Retirer la prémisse" (RetirerPremisse h.id) ]) m.document.premisses
                                ++ [ M.boutonSecondaire "Déclarer une prémisse" AjouterPremisse ]
                            )

                    "theoremes" ->
                        let
                            defs =
                                List.filter (\d -> not (String.startsWith "fourni-" d.id)) m.document.bibliotheque
                        in
                        if List.isEmpty defs then
                            petit "Vos théorèmes apparaîtront ici. Inspectez un bloc terminé, puis choisissez Créer un théorème."

                        else
                            UI.column [ UI.spacing 18 ] (List.map (\d -> paletteRegle False m (Application d.id d.version)) defs)

                    _ ->
                        UI.column [ UI.spacing 18 ] (List.map (paletteRegle False m) regles)
    in
    UI.column [ UI.width (UI.minimum 0 UI.fill), UI.spacing 14, A.identifiant "atelier-palette" ]
        [ UI.wrappedRow [ UI.width UI.fill, UI.spacing 3 ]
            (List.map
                (\( p, famille, nom ) -> B.onglet (p == m.panneau) famille nom (Panneau p))
                [ ( "construire", "regles", "Construire" ), ( "utiliser", "regles", "Utiliser" ), ( "formules", "propositions", "Propositions" ), ( "faits", "regles", "Faits" ), ( "theoremes", "regles", "Mes théorèmes" ), ( "enonce", "", "Énoncé" ), ( "inspecter", "", "Inspecteur" ) ]
            )
        , contenu
        ]


vue : { largeur : Int, hauteur : Int } -> Modele -> Element Message
vue dimensions m =
    let
        doc =
            m.document

        resultat =
            N.verifier doc.bibliotheque doc.premisses doc.objectif doc.preuves

        verification =
            case resultat of
                Ok v ->
                    "✓ Preuve vérifiée"
                        ++ (if v.classique then
                                " · classique"

                            else
                                " · sans règle classique"
                           )

                Err (Incomplet _) ->
                    "○ À compléter : " ++ F.afficher doc.objectif

                Err (Erreur s) ->
                    "! " ++ s

        commandes =
            UI.column [ UI.width UI.fill, UI.spacing 6 ]
                [ UI.wrappedRow [ UI.width UI.fill, UI.spacing 12 ]
                    [ ligne
                        [ Identite.logo
                        , UI.el
                            [ Region.heading 1
                            , Police.bold
                            , Police.size
                                (if dimensions.largeur < 600 then
                                    16

                                 else
                                    20
                                )
                            , A.identifiant "lesson-heading"
                            , A.tabulation -1
                            ]
                            (UI.text "Atelier de preuves")
                        ]
                    , UI.el [ UI.alignRight ] (ligne [ B.outil "Annuler" "↶" Annuler, B.outil "Rétablir" "↷" Retablir, B.outil "Exporter JSON" "↥" Exporter, B.outil "Importer JSON" "↧" Importer ])
                    ]
                , UI.wrappedRow [ UI.width UI.fill, UI.spacing 7 ]
                    [ UI.el
                        [ UI.width
                            (UI.px
                                (if dimensions.largeur < 500 then
                                    148

                                 else
                                    245
                                )
                            )
                        ]
                        (M.selecteur "Exemple" Ex.titres m.exemple Exemple)
                    , B.commande [ Region.description "Construire l’énoncé", A.infoBulle "Charger l’énoncé à construire" ] (UI.text "Énoncé") (Charger False)
                    , B.commande [ Region.description "Charger la solution manipulable", A.infoBulle "Charger la solution manipulable" ] (UI.text "Solution") (Charger True)
                    , UI.el [ UI.alignRight ] (ligne [ B.outil "Réduire" "−" (Zoomer -10), UI.text (String.fromInt m.zoom ++ "%"), B.outil "Agrandir" "+" (Zoomer 10), B.outil "Recentrer" "⌖" Recentrer ])
                    ]
                ]

        projet =
            UI.el
                [ UI.width UI.fill
                , UI.paddingXY 16
                    (if dimensions.hauteur < 500 then
                        6

                     else
                        12
                    )
                , Fond.color (UI.rgb 1 1 1)
                , Bordure.widthEach { bottom = 1, top = 0, left = 0, right = 0 }
                , Bordure.color (UI.rgb255 221 228 225)
                ]
                (UI.column [ UI.spacing 5, UI.width UI.fill ]
                    [ ligne [ petit "OBJECTIF", champDirect m "objectif" doc.objectif ]
                    , UI.wrappedRow [ UI.width UI.fill, UI.spacing 5 ]
                        ([ petit "DONNÉES" ]
                            ++ List.map (\h -> champDirect m ("premisse:" ++ h.id) h.formule) doc.premisses
                            ++ [ B.commande [ Region.description "Déclarer une prémisse", A.infoBulle "Ajouter une donnée" ] (UI.text "+") AjouterPremisse ]
                        )
                    ]
                )

        canevas =
            UI.column [ UI.width UI.fill, UI.height UI.fill, A.identifiant "atelier-canevas" ]
                [ projet
                , UI.el
                    [ UI.width (UI.minimum 0 UI.fill)
                    , UI.height (UI.minimum 0 UI.fill)
                    , UI.scrollbars
                    , UI.padding 16
                    , A.identifiant "atelier-surface"
                    , Manipulation.defilement
                    , Manipulation.fond ("preuve:racine|0|" ++ String.fromInt (List.length doc.preuves))
                    , Region.description "Espace d’assemblage des preuves"
                    , A.tabulation 0
                    ]
                    (UI.column
                        [ UI.width UI.shrink
                        , UI.height UI.shrink
                        , Manipulation.zoom m.zoom
                        , UI.spacing 18
                        ]
                        [ sequence False False m "racine" 0 (N.contexteInitial doc.premisses) doc.objectif doc.preuves
                        , case m.inspection of
                            Nothing ->
                                UI.none

                            Just preuve ->
                                M.pile [ petit "Démonstration instanciée · lecture", bloc True False m (Ed.selectionnee m |> Maybe.map Tuple.second |> Maybe.withDefault Dict.empty) preuve, M.boutonSecondaire "Fermer la démonstration" FermerInspection ]
                        ]
                    )
                ]

        statut =
            UI.column [ UI.width UI.fill, UI.spacing 3 ]
                [ UI.wrappedRow [ UI.width UI.fill, UI.spacing 8 ]
                    [ UI.el [ A.identifiant "atelier-verification", Police.bold ] (UI.text verification)
                    , UI.el [ UI.alignRight ] (M.lien "Les parcours" "#/parcours")
                    , Identite.signature
                    ]
                , UI.el [ A.identifiant "atelier-message", A.etat, Region.announce ] (petit m.message)
                , if m.stockageBloque then
                    M.actions [ M.bouton "Exporter avant de continuer" Exporter, M.boutonSecondaire "Reprendre la sauvegarde locale" ReprendreStockage ]

                  else
                    UI.none
                ]
    in
    UI.el
        ([ A.identifiant "atelier", UI.width UI.fill ]
            ++ (case m.geste of
                    Nothing ->
                        []

                    Just geste ->
                        [ Manipulation.fantome geste (apercuSource m geste.source) ]
               )
        )
        (B.espace dimensions commandes (palette m) canevas statut)


{-| L'aperçu partage les mêmes constructeurs de pièces que la palette/le canevas.
Aucun document, historique ni certificat n'est modifié par ce rendu.
-}
apercuSource : Modele -> String -> Element Message
apercuSource m identifiant =
    case Ed.lireSource m identifiant of
        Just (Ed.Nouvelle regle) ->
            paletteRegle True m regle

        Just (Ed.Deplacement id) ->
            G.trouver id m.document.preuves
                |> Maybe.map (\donnees -> bloc True True m (G.position id m.document.preuves |> Maybe.andThen (Ed.contexte m) |> Maybe.map Tuple.first |> Maybe.withDefault Dict.empty) (Bloc donnees))
                |> Maybe.withDefault UI.none

        Just (Ed.Fait _ formule) ->
            B.emboitableAvec B.Miniature B.Neutre [] (ligne [ UI.text "utiliser", formuleFixe formule ]) [] UI.none

        Just (Ed.Proposition formule) ->
            formuleFixe formule

        Nothing ->
            UI.none
