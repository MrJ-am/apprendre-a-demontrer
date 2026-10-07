module Atelier.Regles exposing (contrat, creer, entreeOrdinaire, etiquettes, initiale, nom, parametres, primitives)

import Atelier.Formule as F exposing (Formule(..))
import Atelier.Types exposing (..)
import Dict


entreeOrdinaire : Formule -> Port
entreeOrdinaire f =
    { hypotheses = [], conclusion = f }


primitives : List String
primitives =
    [ "etI", "implI", "etG", "etD", "implE", "ouG", "ouD", "ouE", "fauxE", "RA" ]


etiquettes : List ( String, String )
etiquettes =
    [ ( "etI", "Montrons une conjonction" ), ( "implI", "Montrons une implication" ), ( "etG", "Utilisons la partie gauche" ), ( "etD", "Utilisons la partie droite" ), ( "implE", "Appliquons une implication" ), ( "ouG", "Introduisons une disjonction à gauche" ), ( "ouD", "Introduisons une disjonction à droite" ), ( "ouE", "Distinguons les cas" ), ( "fauxE", "Concluons à partir d’une contradiction" ), ( "RA", "Raisonnons par l’absurde · classique" ) ]


nom : Bibliotheque -> Regle -> String
nom bibliotheque regle =
    case regle of
        Primitive p ->
            Dict.get p (Dict.fromList etiquettes) |> Maybe.withDefault "Règle inconnue"

        Reference _ ->
            "Utilisons un fait"

        Application id version ->
            trouverDefinition bibliotheque id version |> Maybe.map .nom |> Maybe.withDefault "Théorème manquant"

        Argument i ->
            "Entrée " ++ String.fromInt (i + 1)

        Enchainement ->
            "Démonstration développée"


parametres : Bibliotheque -> Regle -> List String
parametres bibliotheque regle =
    case regle of
        Primitive p ->
            if p == "ouE" then
                [ "A", "B", "C" ]

            else if List.member p [ "RA", "fauxE" ] then
                [ "A" ]

            else
                [ "A", "B" ]

        Application id version ->
            trouverDefinition bibliotheque id version |> Maybe.map .parametres |> Maybe.withDefault []

        _ ->
            [ "S" ]


contrat : Bibliotheque -> DonneesBloc -> Result Probleme Contrat
contrat bibliotheque b =
    let
        p nomParam =
            Dict.get nomParam b.parametres |> Maybe.withDefault (Trou nomParam)

        a =
            p "A"

        c =
            p "C"

        d =
            p "B"

        sous i f g =
            { hypotheses = [ { id = hypotheseId b.id i 0, formule = f } ], conclusion = g }

        resultat entrees conclusion =
            Ok { entrees = entrees, conclusion = conclusion }
    in
    case b.regle of
        Reference _ ->
            resultat [] (p "S")

        Enchainement ->
            resultat [ entreeOrdinaire (p "S") ] (p "S")

        Argument _ ->
            Err (Erreur "Un argument formel n’est autorisé que dans son certificat.")

        Application id version ->
            trouverDefinition bibliotheque id version
                |> Maybe.map
                    (\def ->
                        resultat
                            (List.indexedMap (\i e -> { hypotheses = List.indexedMap (\j h -> { id = hypotheseId b.id i j, formule = F.substituer b.parametres h.formule }) e.hypotheses, conclusion = F.substituer b.parametres e.conclusion }) def.entrees)
                            (F.substituer b.parametres def.conclusion)
                    )
                |> Maybe.withDefault (Err (Erreur ("Définition absente : " ++ cle id version)))

        Primitive r ->
            case r of
                "etI" ->
                    resultat [ entreeOrdinaire a, entreeOrdinaire d ] (Et a d)

                "etG" ->
                    resultat [ entreeOrdinaire (Et a d) ] a

                "etD" ->
                    resultat [ entreeOrdinaire (Et a d) ] d

                "implI" ->
                    resultat [ sous 0 a d ] (Implique a d)

                "implE" ->
                    resultat [ entreeOrdinaire (Implique a d), entreeOrdinaire a ] d

                "ouG" ->
                    resultat [ entreeOrdinaire a ] (Ou a d)

                "ouD" ->
                    resultat [ entreeOrdinaire d ] (Ou a d)

                "ouE" ->
                    resultat [ entreeOrdinaire (Ou a d), sous 1 a c, sous 2 d c ] c

                "fauxE" ->
                    resultat [ entreeOrdinaire Faux ] a

                "RA" ->
                    resultat [ sous 0 (Non a) Faux ] a

                _ ->
                    Err (Erreur "Cette règle primitive n’existe pas.")


creer : Bibliotheque -> String -> Regle -> Dict.Dict String Formule -> Preuve
creer bibliotheque id regle valeurs =
    let
        b =
            { id = id, regle = regle, parametres = valeurs, entrees = [] }
    in
    Bloc { b | entrees = contrat bibliotheque b |> Result.map (.entrees >> List.map (\_ -> [])) |> Result.withDefault [] }


{-| La palette fournie utilise exactement le même mécanisme de certificats que
les théorèmes extraits. Argument i désigne un entreeOrdinaire de preuve, jamais un axiome.
Le noyau vérifie son contexte hypothétique avant de l'accepter.
-}
initiale : Bibliotheque
initiale =
    let
        a =
            Parametre "A"

        b =
            Parametre "B"

        prim id r ps es =
            Bloc { id = id, regle = Primitive r, parametres = Dict.fromList ps, entrees = es }

        argument id i =
            Bloc { id = id, regle = Argument i, parametres = Dict.empty, entrees = [] }

        fait id ref f =
            Bloc { id = id, regle = Reference ref, parametres = Dict.singleton "S" f, entrees = [] }

        def id titre params entrees conclusion certificat =
            { id = id, version = 1, nom = titre, parametres = params, entrees = entrees, conclusion = conclusion, certificat = certificat, dependances = [] }
    in
    [ def "fourni-nonI"
        "Montrons une négation"
        [ "A" ]
        [ { hypotheses = [ { id = hypotheseId "neg" 0 0, formule = a } ], conclusion = Faux } ]
        (Non a)
        [ prim "neg" "implI" [ ( "A", a ), ( "B", Faux ) ] [ [ argument "neg-corps" 0 ] ] ]
    , def "fourni-contradiction"
        "Obtenons une contradiction"
        [ "A" ]
        [ entreeOrdinaire a, entreeOrdinaire (Non a) ]
        Faux
        [ prim "contr" "implE" [ ( "A", a ), ( "B", Faux ) ] [ [ argument "contr-non" 1 ], [ argument "contr-oui" 0 ] ] ]
    , def "fourni-double-non"
        "Éliminons une double négation · classique"
        [ "A" ]
        [ entreeOrdinaire (Non (Non a)) ]
        a
        [ prim "absurde"
            "RA"
            [ ( "A", a ) ]
            [ [ prim "double-e" "implE" [ ( "A", Non a ), ( "B", Faux ) ] [ [ argument "double-p" 0 ], [ fait "double-h" (hypotheseId "absurde" 0 0) (Non a) ] ] ] ]
        ]
    , def "fourni-equivI"
        "Montrons une équivalence"
        [ "A", "B" ]
        [ { hypotheses = [ { id = hypotheseId "aller" 0 0, formule = a } ], conclusion = b }, { hypotheses = [ { id = hypotheseId "retour" 0 0, formule = b } ], conclusion = a } ]
        (Equivalent a b)
        [ prim "deux-sens"
            "etI"
            [ ( "A", Implique a b ), ( "B", Implique b a ) ]
            [ [ prim "aller" "implI" [ ( "A", a ), ( "B", b ) ] [ [ argument "aller-entreeOrdinaire" 0 ] ] ], [ prim "retour" "implI" [ ( "A", b ), ( "B", a ) ] [ [ argument "retour-entreeOrdinaire" 1 ] ] ] ]
        ]
    , def "fourni-equivG"
        "Utilisons une équivalence →"
        [ "A", "B" ]
        [ entreeOrdinaire (Equivalent a b), entreeOrdinaire a ]
        b
        [ prim "equiv-e"
            "implE"
            [ ( "A", a ), ( "B", b ) ]
            [ [ prim "equiv-p" "etG" [ ( "A", Implique a b ), ( "B", Implique b a ) ] [ [ argument "equiv-entreeOrdinaire" 0 ] ] ], [ argument "equiv-a" 1 ] ]
        ]
    , def "fourni-equivD"
        "Utilisons une équivalence ←"
        [ "A", "B" ]
        [ entreeOrdinaire (Equivalent a b), entreeOrdinaire b ]
        a
        [ prim "equiv-e"
            "implE"
            [ ( "A", b ), ( "B", a ) ]
            [ [ prim "equiv-p" "etD" [ ( "A", Implique a b ), ( "B", Implique b a ) ] [ [ argument "equiv-entreeOrdinaire" 0 ] ] ], [ argument "equiv-b" 1 ] ]
        ]
    ]
