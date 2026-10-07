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
import Html.Attributes as A
import MrJam as M
import MrJam.Blocs as B
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
    UI.el [ UI.width UI.fill, attribut "id" id ]


texte : String -> Element msg
texte =
    M.paragraphe


source : String -> String -> Element Message
source id libelle =
    UI.el [ UI.width UI.shrink, UI.htmlAttribute (A.style "width" "max-content"), UI.htmlAttribute (A.style "max-width" "100%"), attribut "data-atelier-source" id, attribut "class" "atelier-poignee", attribut "data-testid" id ]
        (M.boutonSecondaire ("⠿ " ++ libelle) (Choisir id))


champFormule : String -> String -> Formule -> Element Message
champFormule cible libelle f =
    B.proposition [ UI.width (UI.minimum 0 UI.fill), UI.htmlAttribute (A.style "width" "100%"), attribut "data-atelier-cible" ("formule:" ++ cible), attribut "data-formule" cible ]
        (UI.wrappedRow [ UI.spacing 5, UI.width (UI.minimum 0 UI.fill) ]
            [ M.boutonSecondaire (libelle ++ F.afficher f) (EditerFormule cible)
            , UI.el [ attribut "data-atelier-source" ("prop:" ++ cible), attribut "class" "atelier-poignee" ] (M.boutonSecondaire "⠿" (Choisir ("prop:" ++ cible)))
            ]
        )


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


zone : Modele -> G.Cible -> Formule -> Bool -> Element Message
zone m cible attendu vide =
    let
        identite =
            "preuve:" ++ G.cibleTexte cible

        libelle =
            if vide then
                "Démontrer " ++ F.afficher attendu

            else
                "Insérer une étape ici"
    in
    B.cavite [ attribut "data-atelier-cible" identite, attribut "data-testid" identite ]
        (M.boutonSecondaire
            ((if m.source == Nothing then
                "＋ "

              else
                "Placer ici · "
             )
                ++ libelle
            )
            (Placer identite)
        )


sequence : Bool -> Modele -> String -> Int -> Contexte -> Formule -> List Preuve -> Element Message
sequence lecture m parent indice contexte attendu preuves =
    let
        avancer ( index, preuve ) ( ctx, accumulees ) =
            let
                resultat =
                    N.verifierBloc m.document.bibliotheque ctx preuve

                suivant =
                    Result.map (\v -> Dict.insert (identifiant preuve) v ctx) resultat |> Result.withDefault ctx

                cible =
                    { parent = parent, indice = indice, position = index }

                avant =
                    if lecture then
                        []

                    else
                        [ zone m cible attendu (List.isEmpty preuves) ]
            in
            ( suivant, accumulees ++ avant ++ [ bloc lecture m ctx preuve ] )

        ( _, vues ) =
            List.foldl avancer ( contexte, [] ) (List.indexedMap Tuple.pair preuves)
    in
    UI.column [ UI.width (UI.minimum 0 UI.fill), UI.spacing 8 ]
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

        titre =
            R.nom bibliotheque b.regle
                ++ (if classique bibliotheque b.regle && not (String.contains "classique" (R.nom bibliotheque b.regle)) then
                        " · classique"

                    else
                        ""
                   )

        ferme =
            Set.member b.id m.repli && not lecture

        entete =
            UI.column [ UI.spacing 6, UI.width UI.fill ]
                [ if lecture then
                    texte titre

                  else
                    UI.wrappedRow [ UI.width UI.fill, UI.spacing 5 ]
                        [ source ("bloc:" ++ b.id) titre
                        , M.boutonSecondaire "Inspecter" (Selectionner b.id)
                        ]
                , if lecture then
                    M.texteSecondaire (Dict.toList b.parametres |> List.map (\( p, f ) -> p ++ " := " ++ F.afficher f) |> String.join " · ")

                  else
                    M.actions
                        (Dict.toList b.parametres
                            |> List.map
                                (\( p, f ) ->
                                    B.proposition [ attribut "data-atelier-cible" ("formule:param:" ++ b.id ++ ":" ++ p) ]
                                        (M.boutonSecondaire (p ++ " : " ++ F.afficher f) (EditerFormule ("param:" ++ b.id ++ ":" ++ p)))
                                )
                        )
                ]

        cavites =
            case contrat of
                Err _ ->
                    []

                Ok c ->
                    List.map2
                        (\( i, e ) ps ->
                            UI.column [ UI.width (UI.minimum 0 UI.fill), UI.spacing 7 ]
                                [ B.objectif (texte ("Montrons " ++ F.afficher e.conclusion))
                                , if List.isEmpty e.hypotheses then
                                    UI.none

                                  else
                                    M.pile (List.map (\h -> M.texteSecondaire ("Supposons " ++ F.afficher h.formule ++ " · hypothèse locale de cette cavité")) e.hypotheses)
                                , if lecture then
                                    UI.none

                                  else
                                    M.boutonSecondaire "Faits dans cette cavité" (ChoisirCavite { parent = b.id, indice = i, position = List.length ps })
                                , sequence lecture m b.id i (N.ajouterHypotheses e.hypotheses contexte) e.conclusion ps
                                ]
                        )
                        (List.indexedMap Tuple.pair c.entrees)
                        b.entrees

        conclusion =
            contrat |> Result.map (.conclusion >> F.afficher) |> Result.withDefault "?"

        contracte =
            case contrat of
                Err p ->
                    texte (messageProbleme p)

                Ok c ->
                    texte ("Entrées : " ++ (List.map (.conclusion >> F.afficher) c.entrees |> String.join " ; ") ++ " ⊢ " ++ conclusion)
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
        (M.pile
            [ if ferme then
                contracte

              else
                UI.none
            , texte
                ((if Result.toMaybe resultat == Nothing then
                    "Conclusion attendue : "

                  else
                    "Nous obtenons donc "
                 )
                    ++ conclusion
                )
            , M.texteSecondaire message
            ]
        )


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

        schema =
            contrat |> Result.map (\c -> String.join " ; " (List.map (.conclusion >> F.afficher) c.entrees) ++ " ⊢ " ++ F.afficher c.conclusion) |> Result.withDefault "Certificat absent"

        nombre =
            contrat |> Result.map (.entrees >> List.length) |> Result.withDefault 0
    in
    B.emboitable B.Neutre
        []
        (source id (R.nom m.document.bibliotheque regle))
        (if nombre == 0 then
            []

         else
            [ M.texteSecondaire (String.fromInt nombre ++ " cavité(s) de preuve") ]
        )
        (M.texteSecondaire
            (schema
                ++ (if classique m.document.bibliotheque regle then
                        " · règle classique"

                    else
                        ""
                   )
            )
        )


faits : Modele -> Element Message
faits m =
    let
        ctx =
            Ed.contexte m m.cible |> Maybe.map Tuple.first |> Maybe.withDefault (N.contexteInitial m.document.premisses)
    in
    M.pile
        [ M.sousTitre "Faits disponibles ici"
        , M.texteSecondaire ("Contexte « " ++ m.cible.parent ++ " » · chaque utilisation crée une référence, le fait reste disponible.")
        , if Dict.isEmpty ctx then
            texte "Aucun fait disponible. Vous pouvez raisonner sous une hypothèse locale ou déclarer une prémisse de l’exercice."

          else
            M.pile (Dict.toList ctx |> List.map (\( id, v ) -> source ("fait:" ++ id) (F.afficher v.conclusion)))
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


arbreFormule : Modele -> List Int -> Formule -> Element Message
arbreFormule m chemin f =
    let
        cible =
            "formule:trou:" ++ (List.map String.fromInt chemin |> String.join ".")

        enfants =
            case f of
                Et a b ->
                    [ a, b ]

                Ou a b ->
                    [ a, b ]

                Implique a b ->
                    [ a, b ]

                Equivalent a b ->
                    [ a, b ]

                Non a ->
                    [ a ]

                _ ->
                    []

        operateur =
            case f of
                Et _ _ ->
                    "∧"

                Ou _ _ ->
                    "∨"

                Implique _ _ ->
                    "⇒"

                Equivalent _ _ ->
                    "⇔"

                Non _ ->
                    "¬"

                _ ->
                    F.afficher f
    in
    B.proposition [ UI.width (UI.minimum 0 UI.fill), UI.htmlAttribute (A.style "width" "100%"), attribut "data-atelier-cible" cible, attribut "data-chemin" (List.map String.fromInt chemin |> String.join ".") ]
        (UI.column [ UI.spacing 6, UI.width (UI.minimum 0 UI.fill) ]
            [ M.boutonSecondaire
                ((if m.chemin == chemin then
                    "▸ "

                  else
                    ""
                 )
                    ++ operateur
                )
                (if m.source == Nothing then
                    CheminFormule chemin

                 else
                    Placer cible
                )
            , UI.column [ UI.spacing 5, UI.width UI.fill ] (List.indexedMap (\i enfant -> arbreFormule m (chemin ++ [ i ]) enfant) enfants)
            ]
        )


composeur : Modele -> Element Message
composeur m =
    M.pile
        [ M.sousTitre "Composer une proposition"
        , M.texteSecondaire "Sélectionnez un emplacement rond, puis un connecteur ou un atome. Vous pouvez aussi les glisser. Une proposition n’est jamais une preuve."
        , M.actions ([ ( "et", "∧" ), ( "ou", "∨" ), ( "implique", "⇒" ), ( "non", "¬" ), ( "equivalent", "⇔" ), ( "faux", "⊥" ) ] |> List.map (\( r, s ) -> UI.el [ attribut "data-atelier-source" ("connecteur:" ++ r), attribut "class" "atelier-poignee" ] (M.boutonSecondaire s (Connecteur r))))
        , M.actions (List.map (\a -> source ("atome:" ++ a) a) [ "A", "B", "C", "P", "Q", "R", "S" ])
        , M.champ "Nom de l’atome" m.nomAtome NomAtome
        , M.boutonSecondaire "Insérer cet atome" InsererAtome
        , arbreFormule m [] m.brouillon
        , source "prop:brouillon" (F.afficher m.brouillon)
        , M.bouton "Utiliser cette proposition" AppliquerFormule
        , M.champ "Saisie textuelle facultative" m.texteFormule TexteFormule
        , M.actions [ M.boutonSecondaire "Lire la saisie" AnalyserFormule, M.boutonSecondaire "Fermer le composeur" FermerFormule ]
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
            case m.panneau of
                "utiliser" ->
                    List.map Primitive [ "etG", "etD", "implE", "ouE", "fauxE", "RA" ] ++ List.map (\id -> Application id 1) [ "fourni-contradiction", "fourni-double-non", "fourni-equivG", "fourni-equivD" ]

                _ ->
                    List.map Primitive [ "etI", "implI", "ouG", "ouD" ] ++ List.map (\id -> Application id 1) [ "fourni-nonI", "fourni-equivI" ]
    in
    UI.column [ UI.width (UI.minimum 0 UI.fill), UI.spacing 12, attribut "id" "atelier-palette" ]
        [ M.actions ([ ( "construire", "Construire" ), ( "utiliser", "Utiliser" ), ( "faits", "Faits" ), ( "theoremes", "Mes théorèmes" ), ( "formules", "Propositions" ), ( "inspecter", "Inspecteur" ) ] |> List.map (\( p, libelle ) -> M.boutonSecondaire libelle (Panneau p)))
        , if m.cibleFormule /= Nothing then
            composeur m

          else
            case m.panneau of
                "faits" ->
                    faits m

                "inspecter" ->
                    inspecteur m

                "formules" ->
                    composeur m

                "theoremes" ->
                    let
                        defs =
                            List.filter (\d -> not (String.startsWith "fourni-" d.id)) m.document.bibliotheque
                    in
                    if List.isEmpty defs then
                        texte "Vos théorèmes apparaîtront ici. Construisez une preuve, inspectez sa conclusion, puis choisissez Créer un théorème."

                    else
                        M.pile (List.map (\d -> paletteRegle m (Application d.id d.version)) defs)

                _ ->
                    M.pile (List.map (paletteRegle m) regles)
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
                    "✓ Preuve vérifiée dans les hypothèses affichées"
                        ++ (if v.classique then
                                " · raisonnement classique"

                            else
                                " · sans règle classique"
                           )

                Err (Incomplet _) ->
                    "○ À compléter : il reste à démontrer " ++ F.afficher doc.objectif

                Err (Erreur s) ->
                    "! Erreur : " ++ s

        canevas =
            UI.column [ UI.width (UI.minimum 0 UI.fill), UI.spacing 14, attribut "id" "atelier-canevas" ]
                [ M.sousTitre "Votre démonstration"
                , B.objectif (champFormule "objectif" "Objectif · " doc.objectif)
                , M.texteSecondaire "Les cavités contiennent des preuves. Chaque dernière étape en donne la conclusion. Les hypothèses locales restent dans leur cavité."
                , UI.el [ UI.width UI.fill, attribut "class" "atelier-canevas-defilant" ] (sequence False m "racine" 0 (N.contexteInitial doc.premisses) doc.objectif doc.preuves)
                , repere "atelier-verification"
                    (M.avis
                        (if Result.toMaybe resultat == Nothing then
                            M.Avertissement

                         else
                            M.Succes
                        )
                        verification
                    )
                ]
    in
    UI.column [ UI.width UI.fill, UI.spacing 18, attribut "id" "atelier" ]
        [ repere "lesson-heading" (M.sousTitre "Atelier de preuves — prototype")
        , texte "Construisez une démonstration. Faites-en un théorème. Composez la suite."
        , M.actions [ M.boutonSecondaire "Annuler" Annuler, M.boutonSecondaire "Rétablir" Retablir, M.boutonSecondaire "Exporter JSON" Exporter, M.boutonSecondaire "Importer JSON" Importer ]
        , M.selecteur "Exemple" Ex.titres m.exemple Exemple
        , M.actions [ M.bouton "Construire l’énoncé" (Charger False), M.boutonSecondaire "Charger la solution manipulable" (Charger True) ]
        , M.carte
            [ M.sousTitre "Prémisses déclarées"
            , if List.isEmpty doc.premisses then
                M.texteSecondaire "Aucune prémisse extérieure. L’objectif n’est pas un fait acquis."

              else
                M.pile
                    (List.map
                        (\h ->
                            M.pile
                                [ champFormule ("premisse:" ++ h.id) "Hypothèse · " h.formule, M.actions [ source ("fait:" ++ h.id) "Utiliser ce fait", M.boutonSecondaire "Retirer la prémisse" (RetirerPremisse h.id) ] ]
                        )
                        doc.premisses
                    )
            , M.boutonSecondaire "Déclarer une prémisse" AjouterPremisse
            ]
        , repere "atelier-message" (UI.el [ attribut "role" "status", attribut "aria-live" "polite", UI.width UI.fill ] (M.avis M.Information m.message))
        , if m.stockageBloque then
            M.actions [ M.bouton "Exporter avant de continuer" Exporter, M.boutonSecondaire "Reprendre la sauvegarde locale" ReprendreStockage ]

          else
            M.texteSecondaire "Sauvegarde locale automatique · aucune démonstration n’est envoyée à un serveur."
        , if largeur >= 1000 then
            UI.row [ UI.width UI.fill, UI.spacing 20, UI.alignTop ]
                [ UI.el [ UI.width (UI.px 300), UI.alignTop, attribut "class" "atelier-palette-defilante" ] (palette m), UI.el [ UI.width (UI.minimum 0 UI.fill), UI.alignTop ] canevas ]

          else
            M.pile
                [ M.boutonDevoiler "atelier-palette"
                    "Palette et outils"
                    (m.panneau /= "ferme")
                    (Panneau
                        (if m.panneau == "ferme" then
                            "construire"

                         else
                            "ferme"
                        )
                    )
                , if m.panneau == "ferme" then
                    UI.none

                  else
                    palette m
                , canevas
                ]
        , extraction m
        , case m.inspection of
            Nothing ->
                UI.none

            Just preuve ->
                M.section "Démonstration instanciée — lecture du certificat"
                    [ bloc True m (Ed.selectionnee m |> Maybe.map Tuple.second |> Maybe.withDefault Dict.empty) preuve, M.boutonSecondaire "Fermer la démonstration" FermerInspection ]
        , M.texteSecondaire "Cadre propositionnel. ¬A abrège A ⇒ ⊥ ; A ⇔ B abrège (A ⇒ B) ∧ (B ⇒ A). Les règles classiques restent signalées, même dans les théorèmes repliés."
        ]
