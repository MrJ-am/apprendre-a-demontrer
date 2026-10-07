port module AtelierCheck exposing (main)

import Atelier.Exemples as X
import Atelier.Formule as F exposing (Formule(..))
import Atelier.Graphe as G
import Atelier.Noyau as N
import Atelier.Regles as R
import Atelier.Sauvegarde as S
import Atelier.Theoremes as T
import Atelier.Types exposing (..)
import AtelierRegles
import Dict
import Json.Decode as D
import Json.Encode as E
import Platform
import Set


port finished : E.Value -> Cmd msg


ok : Result e a -> Bool
ok r =
    case r of
        Ok _ ->
            True

        Err _ ->
            False


verifierDoc : Document -> Result Probleme Verdict
verifierDoc doc =
    N.verifier doc.bibliotheque doc.premisses doc.objectif doc.preuves


extraireDoc : String -> String -> Document -> Result Probleme Definition
extraireDoc id nom doc =
    T.extraire doc.bibliotheque (N.contexteInitial doc.premisses) id 1 nom (Set.fromList [ "A", "B", "C" ]) doc.preuves


checks : List ( String, Bool )
checks =
    let
        a =
            X.a

        b =
            X.b

        c =
            X.c

        ab =
            Implique a b

        trans =
            X.charger "transitivite" True

        ctx =
            N.contexteInitial trans.premisses

        t =
            extraireDoc "transitivite" "Transitivité" trans

        lib =
            Result.map (\d -> d :: R.initiale) t |> Result.withDefault R.initiale

        occurrence =
            X.application "usage" "transitivite" [ ( "A", a ), ( "B", b ), ( "C", c ) ] [ [ X.fait "u1" "hAB" ab ], [ X.fait "u2" "hBC" (Implique b c) ] ]

        chaine =
            X.charger "chaine" False

        premiere =
            X.application "premiere" "transitivite" [ ( "A", a ), ( "B", b ), ( "C", c ) ] [ [ X.fait "p1" "hAB" ab ], [ X.fait "p2" "hBC" (Implique b c) ] ]

        seconde =
            X.application "seconde" "transitivite" [ ( "A", a ), ( "B", c ), ( "C", X.d ) ] [ [ X.fait "s1" "premiere" (Implique a c) ], [ X.fait "s2" "hCD" (Implique c X.d) ] ]

        ch =
            { chaine | bibliotheque = lib, preuves = [ premiere, seconde ] }

        second =
            T.extraire lib (N.contexteInitial ch.premisses) "chaine" 1 "Chaîne de trois implications" (Set.fromList [ "A", "B", "C", "D" ]) ch.preuves

        chlib =
            Result.map (\d -> d :: lib) second |> Result.withDefault lib

        chdoc =
            { ch | bibliotheque = chlib }

        trou =
            X.regle "impossible" "implI" [ ( "A", a ), ( "B", b ) ] [ [] ]

        hors =
            X.fait "hors" (hypotheseId "impossible" 0 0) a

        cas =
            X.charger "cas" True

        fuite =
            G.transformer
                (\n ->
                    if n.id == "casHB" then
                        { n | regle = Reference (hypotheseId "cas" 1 0) }

                    else
                        n
                )
                cas.preuves

        fauxCertificat =
            t |> Result.map (\d -> { d | conclusion = Atome "Mensonge" })

        reflexe =
            X.regle "reflexe" "implI" [ ( "A", a ), ( "B", a ) ] [ [ X.fait "ref" (hypotheseId "reflexe" 0 0) a ] ]

        sansUsage =
            X.regle "sansUsage" "implI" [ ( "A", a ), ( "B", b ) ] [ [ X.fait "b" "hB" b ] ]

        echange =
            X.charger "echange" True

        ech =
            T.extraire R.initiale (N.contexteInitial echange.premisses) "echange" 1 "Échanger" (Set.fromList [ "A", "B" ]) echange.preuves

        p =
            Implique (Atome "P") (Atome "Q")

        q =
            Ou (Atome "R") (Atome "S")

        echLib =
            Result.map (\d -> d :: R.initiale) ech |> Result.withDefault R.initiale

        echUsage =
            X.application "composee" "echange" [ ( "A", p ), ( "B", q ) ] [ [ X.fait "composee-entree" "hComposee" (Et p q) ] ]

        echCtx =
            N.contexteInitial [ { id = "hComposee", formule = Et p q } ]

        cycle =
            t |> Result.map (\d -> { d | certificat = [ occurrence ], dependances = [ ( "transitivite", 1 ) ] })

        expansionConserve bibliotheque contexte preuve =
            T.developper bibliotheque contexte preuve |> Result.andThen (\developpee -> N.verifierBloc bibliotheque contexte developpee) |> ok

        doubled =
            { echange | preuves = G.dupliquer "copie/" trans.preuves, premisses = trans.premisses, objectif = trans.objectif }
    in
    List.map (\nom -> ( "exemple " ++ nom, ok (verifierDoc (X.charger nom True)) )) [ "double", "echange", "transitivite", "cas", "contraposition", "classique" ]
        ++ [ ( "certificats dérivés", ok (N.verifierBibliotheque R.initiale) )
           , ( "transitivité exactement deux entrées", Result.map (.entrees >> List.length >> (==) 2) t |> Result.withDefault False )
           , ( "transitivité trois paramètres", Result.map (.parametres >> (==) [ "A", "B", "C" ]) t |> Result.withDefault False )
           , ( "application directe", ok (N.verifierBloc lib ctx occurrence) )
           , ( "expansion transitivité", expansionConserve lib ctx occurrence )
           , ( "composition deux occurrences", ok (verifierDoc ch) )
           , ( "extraction second niveau", ok second )
           , ( "bibliothèque deux niveaux", ok (N.verifierBibliotheque chlib) )
           , ( "aller-retour complet", S.lire (E.encode 0 (S.encoder chdoc)) == Ok chdoc )
           , ( "hypothèse inutilisée", ok (N.verifierBloc R.initiale (N.contexteInitial [ { id = "hB", formule = b } ]) sansUsage) )
           , ( "identité sans prémisse", ok (N.verifier R.initiale [] (Implique a a) [ reflexe ]) )
           , ( "trou non certifié", not (ok (N.verifierBloc R.initiale Dict.empty trou)) )
           , ( "hypothèse hors portée", not (ok (N.verifierBloc R.initiale Dict.empty hors)) )
           , ( "branches isolées", not (ok (verifierDoc { cas | preuves = fuite })) )
           , ( "disjonction obligatoire"
             , not
                (ok
                    (verifierDoc
                        { cas
                            | preuves =
                                G.transformer
                                    (\n ->
                                        if n.id == "cas" then
                                            { n | entrees = [] :: List.drop 1 n.entrees }

                                        else
                                            n
                                    )
                                    cas.preuves
                        }
                    )
                )
             )
           , ( "pas de projection disjonctive", not (ok (N.verifierBloc R.initiale (N.contexteInitial [ { id = "h", formule = Ou a b } ]) (X.regle "bad" "etD" [ ( "A", a ), ( "B", b ) ] [ [ X.fait "badH" "h" (Ou a b) ] ]))) )
           , ( "pas de commutativité silencieuse", not (F.egales (Et a b) (Et b a)) )
           , ( "définition négation", F.egales (Non a) (Implique a Faux) )
           , ( "définition équivalence", F.egales (Equivalent a b) (Et (Implique a b) (Implique b a)) )
           , ( "certificat falsifié rejeté", not (fauxCertificat |> Result.andThen (N.verifierDefinition lib) |> ok) )
           , ( "port superflu importé rejeté", not (t |> Result.map (\d -> { d | entrees = d.entrees ++ [ { hypotheses = [], conclusion = Parametre "A" } ] }) |> Result.andThen (N.verifierDefinition lib) |> ok) )
           , ( "cycle théorème rejeté", not (cycle |> Result.andThen (\d -> N.verifierBibliotheque (d :: R.initiale)) |> ok) )
           , ( "dépendance absente rejetée", not (second |> Result.andThen (N.verifierDefinition R.initiale) |> ok) )
           , ( "instanciation composée", ok (N.verifierBloc echLib echCtx echUsage) )
           , ( "expansion composée", expansionConserve echLib echCtx echUsage )
           , ( "duplication lieurs frais", ok (verifierDoc doubled) )
           , ( "substitution simultanée", F.substituer (Dict.fromList [ ( "A", Parametre "B" ), ( "B", a ) ]) (Et (Parametre "A") (Parametre "B")) == Et (Parametre "B") a )
           , ( "deux paramètres même image", F.substituer (Dict.fromList [ ( "A", a ), ( "B", a ) ]) (Et (Parametre "A") (Parametre "B")) == Et a a )
           , ( "référence circulaire", not (ok (N.verifierSequence R.initiale Dict.empty [ X.fait "boucle" "boucle" a ])) )
           , ( "paramètres inconnus import", not (ok (S.lire "{\"format\":\"atelier-preuves\",\"version\":999}")) )
           , ( "pas de quantificateur simulé", not (ok (F.lire "∀x P(x)")) )
           , ( "pas de quantificateur déguisé à l’import", not (ok (D.decodeValue F.decoder (F.encoder (Atome "∀x P(x)")))) )
           , ( "classique transitive", verifierDoc (X.charger "classique" True) |> Result.map .classique |> Result.withDefault False )
           , ( "contraposition constructive", verifierDoc (X.charger "contraposition" True) |> Result.map (not << .classique) |> Result.withDefault False )
           ]


main : Program () () ()
main =
    Platform.worker { init = \_ -> ( (), finished (E.list (\( nom, passe ) -> E.object [ ( "nom", E.string nom ), ( "passe", E.bool passe ) ]) (checks ++ AtelierRegles.checks)) ), update = \_ m -> ( m, Cmd.none ), subscriptions = \_ -> Sub.none }
