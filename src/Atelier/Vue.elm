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
import Element.Font as Police
import Element.Region as Region
import Html.Attributes as A
import MrJam as M
import MrJam.Blocs as B
import MrJam.Identite as Identite
import Set


attribut : String -> String -> UI.Attribute msg
attribut nom valeur =
    UI.htmlAttribute
        (if nom == "class" then
            A.class valeur

         else
            A.attribute nom valeur
        )


repere : String -> Element msg -> Element msg
repere id =
    UI.el [ UI.width (UI.minimum 0 UI.fill), attribut "id" id ]


texte : String -> Element msg
texte =
    M.paragraphe


petit : String -> Element msg
petit s =
    UI.paragraph [ UI.width UI.shrink, attribut "class" "mrjam-legende" ] [ UI.text s ]


ligne : List (Element msg) -> Element msg
ligne =
    UI.row [ UI.spacing 5 ]


source : String -> String -> Element Message
source id libelle =
    UI.el [ attribut "data-atelier-source" id, attribut "class" "atelier-poignee", attribut "data-testid" id ] (B.poignee libelle (Choisir id))


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
formuleFixe f =
    let
        ( signe, enfants ) =
            operateur f
    in
    (case f of
        Trou _ ->
            B.logement []

        _ ->
            B.proposition []
    )
        (avecOperateur (UI.text signe) (List.map formuleFixe enfants))


{-| Chaque sous-proposition possède une adresse syntaxique. Le dépôt se fait
sur le logement réellement désigné, même après zoom ou défilement du canevas.
-}
formuleDirecte : Modele -> String -> List Int -> Formule -> Element Message
formuleDirecte m base chemin f =
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
            [ attribut "data-atelier-cible" destination
            , attribut "data-atelier-source" ("prop:" ++ reference)
            , attribut "class" "atelier-poignee"
            , attribut "data-sous-formule" reference
            ]

        bouton =
            B.commande [ attribut "aria-label" ("Modifier " ++ reference), UI.htmlAttribute (A.title (F.afficher f)) ] (UI.text signe) action
    in
    (case f of
        Trou _ ->
            B.logement attributs

        _ ->
            B.proposition attributs
    )
        (avecOperateur bouton (List.indexedMap (\i enfant -> formuleDirecte m base (chemin ++ [ i ]) enfant) enfants))


champFormule : String -> String -> Formule -> Element Message
champFormule cible libelle f =
    UI.el [ attribut "data-formule" cible ]
        (ligne [ petit libelle, B.proposition [] (B.commande [ attribut "aria-label" ("Modifier " ++ cible) ] (UI.text (F.afficher f)) (EditerFormule cible)) ])


champDirect : Modele -> String -> Formule -> Element Message
champDirect m cible f =
    UI.el [ attribut "data-formule" cible ] (formuleDirecte m cible [] f)


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


zone : Modele -> G.Cible -> Formule -> Bool -> Element Message
zone m cible attendu vide =
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
        [ attribut "data-atelier-cible" identite
        , attribut "data-testid" identite
        , attribut "class"
            (if depart then
                "depart"

             else if vide then
                "vide"

             else
                "interstice"
            )
        ]
        (B.commande
            [ attribut "aria-label"
                (if vide then
                    "Démontrer " ++ F.afficher attendu

                 else
                    "Insérer une étape ici"
                )
            ]
            (UI.text libelle)
            (Placer identite)
        )


sequence : Bool -> Modele -> String -> Int -> Contexte -> Formule -> List Preuve -> Element Message
sequence lecture m parent indice contexte attendu preuves =
    let
        avancer ( index, preuve ) ( ctx, accumulees ) =
            let
                suivant =
                    N.verifierBloc m.document.bibliotheque ctx preuve |> Result.map (\v -> Dict.insert (identifiant preuve) v ctx) |> Result.withDefault ctx

                avant =
                    if lecture then
                        []

                    else
                        [ zone m { parent = parent, indice = indice, position = index } attendu False ]
            in
            ( suivant, accumulees ++ avant ++ [ bloc lecture m ctx preuve ] )

        ( _, vues ) =
            List.foldl avancer ( contexte, [] ) (List.indexedMap Tuple.pair preuves)
    in
    UI.column [ UI.spacing 0, UI.alignLeft ]
        (vues
            ++ (if lecture then
                    []

                else
                    [ zone m { parent = parent, indice = indice, position = List.length preuves } attendu (List.isEmpty preuves) ]
               )
        )


bloc : Bool -> Modele -> Contexte -> Preuve -> Element Message
bloc lecture m contexte ((Bloc b) as preuve) =
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
                    source ("bloc:" ++ b.id) (titreCourt bibliotheque b.regle)
                 ]
                    ++ List.map
                        (\( p, f ) ->
                            if lecture then
                                formuleFixe f

                            else
                                champDirect m ("param:" ++ b.id ++ ":" ++ p) f
                        )
                        params
                    ++ [ if lecture then
                            UI.none

                         else
                            B.commande [ attribut "aria-label" "Inspecter", UI.htmlAttribute (A.title "Inspecter, dupliquer, créer un théorème") ] (UI.text "⋯") (Selectionner b.id)
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
                                        B.commande [ attribut "aria-label" "Faits dans cette cavité", UI.htmlAttribute (A.title "Faits disponibles ici") ] (UI.text "☰") (ChoisirCavite { parent = b.id, indice = i, position = List.length ps })
                                    ]
                                , sequence lecture m b.id i (N.ajouterHypotheses e.hypotheses contexte) e.conclusion ps
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
                    , UI.el [ UI.htmlAttribute (A.title message), attribut "aria-label" message ]
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
        [ attribut "data-bloc" b.id ]
        entete
        (if ferme then
            []

         else
            cavites
        )
        pied


paletteRegle : Modele -> Regle -> Element Message
paletteRegle m regle =
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
    B.emboitable B.Neutre
        []
        (source id (titreCourt m.document.bibliotheque regle))
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
                (Dict.toList ctx |> List.map (\( id, v ) -> B.emboitable B.Neutre [] (ligne [ source ("fait:" ++ id) "utiliser", formuleFixe v.conclusion ]) [] UI.none))
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
            B.logement

        _ ->
            B.proposition
    )
        [ attribut "data-atelier-cible" cible, attribut "data-chemin" adresse ]
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
                    B.commande [ attribut "aria-label" signe ]
                        (UI.text signe)
                        (if m.cibleFormule /= Nothing then
                            Connecteur r

                         else
                            Choisir ("connecteur:" ++ r)
                        )
            in
            B.proposition [ attribut "data-atelier-source" ("connecteur:" ++ r), attribut "class" "atelier-poignee" ]
                (avecOperateur bouton (List.map (\_ -> B.logement [] (UI.text "…")) enfants))
    in
    UI.column [ UI.spacing 14, UI.alignLeft ]
        ([ petit "Glisser dans un emplacement vert."
         , UI.wrappedRow [ UI.spacing 6, UI.width UI.fill ] (List.map (\a -> B.proposition [] (source ("atome:" ++ a) a)) [ "A", "B", "C", "D", "P", "Q", "R", "S" ])
         ]
            ++ List.map connecteur [ ( "et", "∧" ), ( "ou", "∨" ), ( "implique", "⇒" ), ( "non", "¬" ), ( "equivalent", "⇔" ), ( "faux", "⊥" ) ]
        )


composeur : Modele -> Element Message
composeur m =
    UI.column [ UI.width UI.fill, UI.spacing 12 ]
        [ palettePropositions m
        , UI.el [ attribut "class" "mrjam-outils" ]
            (M.pile
                [ M.sousTitre "Proposition"
                , arbreFormule m [] m.brouillon
                , source "prop:brouillon" (F.afficher m.brouillon)
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
                        UI.el [ attribut "class" "mrjam-outils" ] (inspecteur m)

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
                            UI.column [ UI.spacing 18, attribut "class" "mrjam-palette-blocs" ] (List.map (\d -> paletteRegle m (Application d.id d.version)) defs)

                    _ ->
                        UI.column [ UI.spacing 18, attribut "class" "mrjam-palette-blocs" ] (List.map (paletteRegle m) regles)
    in
    UI.column [ UI.width (UI.minimum 0 UI.fill), UI.spacing 14, attribut "id" "atelier-palette" ]
        [ UI.wrappedRow [ UI.width UI.fill, UI.spacing 3 ]
            (List.map
                (\( p, famille, nom ) -> B.onglet (p == m.panneau) famille nom (Panneau p))
                [ ( "construire", "regles", "Construire" ), ( "utiliser", "regles", "Utiliser" ), ( "formules", "propositions", "Propositions" ), ( "faits", "regles", "Faits" ), ( "theoremes", "regles", "Mes théorèmes" ), ( "enonce", "", "Énoncé" ), ( "inspecter", "", "Inspecteur" ) ]
            )
        , contenu
        ]


vue : Int -> Modele -> Element Message
vue largeur m =
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
                                (if largeur < 600 then
                                    16

                                 else
                                    20
                                )
                            , attribut "id" "lesson-heading"
                            , UI.htmlAttribute (A.tabindex -1)
                            ]
                            (UI.text "Atelier de preuves")
                        ]
                    , UI.el [ UI.alignRight ] (ligne [ B.outil "Annuler" "↶" Annuler, B.outil "Rétablir" "↷" Retablir, B.outil "Exporter JSON" "↥" Exporter, B.outil "Importer JSON" "↧" Importer ])
                    ]
                , UI.wrappedRow [ UI.width UI.fill, UI.spacing 7 ]
                    [ UI.el
                        [ UI.width
                            (UI.px
                                (if largeur < 500 then
                                    148

                                 else
                                    245
                                )
                            )
                        ]
                        (M.selecteur "Exemple" Ex.titres m.exemple Exemple)
                    , B.commande [ attribut "aria-label" "Construire l’énoncé", UI.htmlAttribute (A.title "Charger l’énoncé à construire") ] (UI.text "Énoncé") (Charger False)
                    , B.commande [ attribut "aria-label" "Charger la solution manipulable", UI.htmlAttribute (A.title "Charger la solution manipulable") ] (UI.text "Solution") (Charger True)
                    , UI.el [ UI.alignRight ] (ligne [ B.outil "Réduire" "−" (Zoomer -10), UI.text (String.fromInt m.zoom ++ "%"), B.outil "Agrandir" "+" (Zoomer 10), B.outil "Recentrer" "⌖" Recentrer ])
                    ]
                ]

        projet =
            UI.el [ attribut "class" "mrjam-projet" ]
                (UI.column [ UI.spacing 5, UI.width UI.fill ]
                    [ ligne [ petit "OBJECTIF", champDirect m "objectif" doc.objectif ]
                    , UI.wrappedRow [ UI.width UI.fill, UI.spacing 5 ]
                        ([ petit "DONNÉES" ]
                            ++ List.map (\h -> champDirect m ("premisse:" ++ h.id) h.formule) doc.premisses
                            ++ [ B.commande [ attribut "aria-label" "Déclarer une prémisse", UI.htmlAttribute (A.title "Ajouter une donnée") ] (UI.text "+") AjouterPremisse ]
                        )
                    ]
                )

        canevas =
            UI.column [ UI.width UI.fill, UI.height UI.fill, attribut "id" "atelier-canevas" ]
                [ projet
                , UI.el
                    [ attribut "class" "mrjam-canevas"
                    , attribut "id" "atelier-surface"
                    , attribut "data-atelier-defile" "canevas"
                    , attribut "aria-label" "Espace d’assemblage des preuves"
                    , UI.htmlAttribute (A.tabindex 0)
                    ]
                    (UI.column
                        [ attribut "class" "mrjam-canevas-contenu"
                        , UI.htmlAttribute (A.style "zoom" (String.fromFloat (toFloat m.zoom / 100)))
                        , UI.spacing 18
                        ]
                        [ sequence False m "racine" 0 (N.contexteInitial doc.premisses) doc.objectif doc.preuves
                        , case m.inspection of
                            Nothing ->
                                UI.none

                            Just preuve ->
                                M.pile [ petit "Démonstration instanciée · lecture", bloc True m (Ed.selectionnee m |> Maybe.map Tuple.second |> Maybe.withDefault Dict.empty) preuve, M.boutonSecondaire "Fermer la démonstration" FermerInspection ]
                        ]
                    )
                ]

        statut =
            UI.column [ UI.width UI.fill, UI.spacing 3 ]
                [ UI.wrappedRow [ UI.width UI.fill, UI.spacing 8 ]
                    [ UI.el [ attribut "id" "atelier-verification", Police.bold ] (UI.text verification)
                    , UI.el [ UI.alignRight ] (M.lien "Les parcours" "#/parcours")
                    , Identite.signature
                    ]
                , UI.el [ attribut "id" "atelier-message", attribut "role" "status", attribut "aria-live" "polite" ] (petit m.message)
                , if m.stockageBloque then
                    M.actions [ M.bouton "Exporter avant de continuer" Exporter, M.boutonSecondaire "Reprendre la sauvegarde locale" ReprendreStockage ]

                  else
                    UI.none
                ]
    in
    UI.el [ attribut "id" "atelier", UI.width UI.fill ] (B.espace commandes (palette m) canevas statut)
