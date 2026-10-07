module AtelierRegles exposing (checks)

import Atelier.Editeur as Ed
import Atelier.Exemples as X
import Atelier.Formule as F exposing (Formule(..))
import Atelier.Graphe as G
import Atelier.Noyau as N
import Atelier.Regles as R
import Atelier.Sauvegarde as S
import Atelier.Theoremes as T
import Atelier.Types exposing (..)
import Dict
import Json.Encode as E
import Set


ok : Result e a -> Bool
ok resultat =
    case resultat of
        Ok _ ->
            True

        Err _ ->
            False


checks : List ( String, Bool )
checks =
    let
        a =
            X.a

        b =
            X.b

        ctx =
            N.contexteInitial [ { id = "a", formule = a }, { id = "b", formule = b }, { id = "ab", formule = Et a b }, { id = "imp", formule = Implique a b }, { id = "faux", formule = Faux }, { id = "eq", formule = Equivalent a b }, { id = "nna", formule = Non (Non a) } ]

        fa =
            X.fait "fa" "a" a

        fb =
            X.fait "fb" "b" b

        fab =
            X.fait "fab" "ab" (Et a b)

        preuves =
            [ ( "∧I", X.regle "et" "etI" [ ( "A", a ), ( "B", b ) ] [ [ fa ], [ fb ] ] )
            , ( "∧G", X.regle "g" "etG" [ ( "A", a ), ( "B", b ) ] [ [ fab ] ] )
            , ( "∧D", X.regle "d" "etD" [ ( "A", a ), ( "B", b ) ] [ [ fab ] ] )
            , ( "⇒I", X.regle "i" "implI" [ ( "A", a ), ( "B", b ) ] [ [ fb ] ] )
            , ( "⇒E", X.regle "e" "implE" [ ( "A", a ), ( "B", b ) ] [ [ X.fait "fi" "imp" (Implique a b) ], [ fa ] ] )
            , ( "∨G", X.regle "ou1" "ouG" [ ( "A", a ), ( "B", b ) ] [ [ fa ] ] )
            , ( "∨D", X.regle "ou2" "ouD" [ ( "A", a ), ( "B", b ) ] [ [ fb ] ] )
            , ( "⊥E", X.regle "f" "fauxE" [ ( "A", b ) ] [ [ X.fait "ff" "faux" Faux ] ] )
            , ( "RA", X.regle "r" "RA" [ ( "A", a ) ] [ [ X.fait "fr" "faux" Faux ] ] )
            , ( "⇔E→", X.application "eqg" "fourni-equivG" [ ( "A", a ), ( "B", b ) ] [ [ X.fait "feqg" "eq" (Equivalent a b) ], [ fa ] ] )
            , ( "⇔E←", X.application "eqd" "fourni-equivD" [ ( "A", a ), ( "B", b ) ] [ [ X.fait "feqd" "eq" (Equivalent a b) ], [ fb ] ] )
            , ( "⇔I", X.application "eqi" "fourni-equivI" [ ( "A", a ), ( "B", b ) ] [ [ fb ], [ fa ] ] )
            , ( "¬¬E", X.application "nn" "fourni-double-non" [ ( "A", a ) ] [ [ X.fait "fnn" "nna" (Non (Non a)) ] ] )
            ]

        invalides =
            List.map (\( nom, Bloc bloc ) -> ( nom, Bloc { bloc | entrees = List.map (List.map (\(Bloc enfant) -> Bloc { enfant | regle = Reference "introuvable" })) bloc.entrees } )) preuves

        double =
            X.charger "double" True

        trans =
            X.charger "transitivite" True

        ext =
            T.extraire R.initiale (N.contexteInitial trans.premisses) "t" 1 "Trans" (Set.fromList [ "A", "B", "C" ]) trans.preuves

        def2 =
            ext |> Result.map (\d -> { d | version = 2, nom = "Autre nom" })

        lib =
            [ ext, def2 ] |> List.filterMap Result.toMaybe |> (++) R.initiale

        ancienne =
            X.application "usage" "t" [ ( "A", a ), ( "B", b ), ( "C", X.c ) ] [ [ X.fait "ab1" "hAB" (Implique a b) ], [ X.fait "bc1" "hBC" (Implique b X.c) ] ]

        ctxTrans =
            N.contexteInitial trans.premisses

        deuxHyp =
            [ X.fait "ref1" "identite1" a, X.regle "contraction" "etI" [ ( "A", a ), ( "B", a ) ] [ [ X.fait "une" "ref1" a ], [ X.fait "deux" "identite2" a ] ] ]

        contexteDeux =
            N.contexteInitial [ { id = "identite1", formule = a }, { id = "identite2", formule = a } ]

        extractionDeux =
            T.extraire R.initiale contexteDeux "deux" 1 "Deux lieurs" (Set.singleton "A") deuxHyp

        seulementDerniere =
            T.extraire R.initiale contexteDeux "une" 1 "Une entrée extérieure" (Set.singleton "A") [ X.fait "r" "identite1" a ]

        nonUtilise =
            T.extraire R.initiale contexteDeux "n" 1 "Sans l’étape inutilisée" (Set.singleton "A") [ X.fait "inutile" "identite2" a, X.fait "sortie" "identite1" a ]

        errDansInutile =
            T.extraire R.initiale contexteDeux "n" 1 "Refus" (Set.singleton "A") [ X.regle "vide" "etI" [ ( "A", a ), ( "B", a ) ] [ [], [] ], X.fait "sortie" "identite1" a ]

        etat0 =
            Ed.initial

        etat1 =
            Ed.update (Ed.Exemple "double") etat0 |> Ed.update (Ed.Charger True)

        etat2 =
            Ed.update (Ed.Selectionner "double") etat1 |> Ed.update Ed.PreparerExtraction |> Ed.update Ed.EnregistrerTheoreme

        historique =
            Ed.update Ed.Annuler etat2 |> Ed.update Ed.Retablir

        falsifie =
            ext |> Result.map (\d -> { d | certificat = [ X.fait "mensonge" "absent" a ] })

        mauvaisImport =
            falsifie |> Result.map (\d -> S.lire (E.encode 0 (S.encoder { double | bibliotheque = d :: R.initiale })))

        pasDep =
            ext |> Result.map (\d -> { d | dependances = [ ( "absent", 1 ) ] })

        composees =
            [ a, Non b, Et a b, Ou a (Non b), Implique (Et a b) X.c, Equivalent (Ou a b) X.c ]
    in
    List.map (\( nom, preuve ) -> ( "règle valide " ++ nom, ok (N.verifierBloc R.initiale ctx preuve) )) preuves
        ++ List.map (\( nom, preuve ) -> ( "règle invalide " ++ nom, not (ok (N.verifierBloc R.initiale ctx preuve)) )) invalides
        ++ List.filterMap
            (\( nom, preuve ) ->
                case preuve of
                    Bloc { regle } ->
                        case regle of
                            Application _ _ ->
                                Just ( "certificat développé " ++ nom, ok (T.developper R.initiale ctx preuve) )

                            _ ->
                                Nothing
            )
            preuves
        ++ [ ( "lieurs égaux distincts", Result.map (.entrees >> List.length >> (==) 2) extractionDeux |> Result.withDefault False )
           , ( "prémisse disponible inutilisée exclue", Result.map (.entrees >> List.length >> (==) 1) seulementDerniere |> Result.withDefault False )
           , ( "étape inutilisée exclue du certificat", Result.map (.entrees >> List.length >> (==) 1) nonUtilise |> Result.withDefault False )
           , ( "trou inutilisé empêche extraction", not (ok errDansInutile) )
           , ( "version précédente conservée", ok (N.verifierBloc lib ctxTrans ancienne) )
           , ( "version précise requise", not (ok (N.verifierBloc (List.filter (\d -> d.id /= "t" || d.version /= 1) lib) ctxTrans ancienne)) )
           , ( "certificat falsifié importé refusé", mauvaisImport |> Result.map (not << ok) |> Result.withDefault False )
           , ( "manifeste dépendances falsifié", not (pasDep |> Result.andThen (N.verifierDefinition R.initiale) |> ok) )
           , ( "annuler rétablit aussi bibliothèque", (Ed.update Ed.Annuler etat2).document == etat1.document )
           , ( "rétablir extraction atomique", historique.document == etat2.document )
           , ( "import corrompu conserve travail", (Ed.update (Ed.ImportRecu "pas du JSON") etat2).document == etat2.document )
           , ( "stockage corrompu protégé", (Ed.update (Ed.Restaurer "pas du JSON") etat2).stockageBloque )
           , ( "duplicata identités rejeté", not (ok (N.controlerIdentites R.initiale [] [ fa, fa ])) )
           , ( "référence anticipée rejetée", not (ok (N.verifierSequence R.initiale ctx [ X.fait "avant" "apres" a, X.fait "apres" "a" a ])) )
           , ( "argument formel hors certificat rejeté", not (ok (N.verifierBloc R.initiale Dict.empty (Bloc { id = "faux", regle = Argument 0, parametres = Dict.empty, entrees = [] }))) )
           ]
        ++ List.indexedMap (\i f -> ( "substitution structurale #" ++ String.fromInt i, F.substituer (Dict.singleton "A" f) (Implique (Parametre "A") (Et (Parametre "A") Faux)) == Implique f (Et f Faux) )) composees
