module Atelier.Exemples exposing (..)

import Atelier.Formule exposing (Formule(..))
import Atelier.Regles as R
import Atelier.Types exposing (..)
import Dict


a : Formule
a =
    Atome "A"


b : Formule
b =
    Atome "B"


c : Formule
c =
    Atome "C"


d : Formule
d =
    Atome "D"


fait : String -> String -> Formule -> Preuve
fait id ref f =
    Bloc { id = id, regle = Reference ref, parametres = Dict.singleton "S" f, entrees = [] }


regle : String -> String -> List ( String, Formule ) -> List (List Preuve) -> Preuve
regle id r ps es =
    Bloc { id = id, regle = Primitive r, parametres = Dict.fromList ps, entrees = es }


application : String -> String -> List ( String, Formule ) -> List (List Preuve) -> Preuve
application id def ps es =
    Bloc { id = id, regle = Application def 1, parametres = Dict.fromList ps, entrees = es }


vide : Document
vide =
    { premisses = [], objectif = Implique a a, preuves = [], bibliotheque = R.initiale, prochain = 1 }


titres : List ( String, String )
titres =
    [ ( "vide", "Atelier libre" ), ( "double", "A · Une hypothèse, deux usages" ), ( "echange", "B · Échanger une conjonction" ), ( "transitivite", "C · Transitivité de l’implication" ), ( "chaine", "C+ · Chaîne de trois implications" ), ( "cas", "D · Distinguer les cas" ), ( "contraposition", "E · Contraposition" ), ( "classique", "F · Double négation" ) ]


charger : String -> Bool -> Document
charger nom solution =
    let
        exemple hs objectif ps =
            { vide
                | premisses = List.map (\( id, f ) -> { id = id, formule = f }) hs
                , objectif = objectif
                , preuves =
                    if solution then
                        ps

                    else
                        []
            }

        ab =
            Implique a b

        bc =
            Implique b c
    in
    case nom of
        "double" ->
            exemple [ ( "hA", a ) ]
                (Et a a)
                [ regle "double" "etI" [ ( "A", a ), ( "B", a ) ] [ [ fait "double1" "hA" a ], [ fait "double2" "hA" a ] ] ]

        "echange" ->
            exemple [ ( "hAB", Et a b ) ]
                (Et b a)
                [ regle "echange"
                    "etI"
                    [ ( "A", b ), ( "B", a ) ]
                    [ [ regle "projD" "etD" [ ( "A", a ), ( "B", b ) ] [ [ fait "refD" "hAB" (Et a b) ] ] ], [ regle "projG" "etG" [ ( "A", a ), ( "B", b ) ] [ [ fait "refG" "hAB" (Et a b) ] ] ] ]
                ]

        "transitivite" ->
            exemple [ ( "hAB", ab ), ( "hBC", bc ) ]
                (Implique a c)
                [ regle "trans"
                    "implI"
                    [ ( "A", a ), ( "B", c ) ]
                    [ [ regle "obtenirB" "implE" [ ( "A", a ), ( "B", b ) ] [ [ fait "refAB" "hAB" ab ], [ fait "refA" (hypotheseId "trans" 0 0) a ] ]
                      , regle "obtenirC" "implE" [ ( "A", b ), ( "B", c ) ] [ [ fait "refBC" "hBC" bc ], [ fait "refB" "obtenirB" b ] ]
                      ]
                    ]
                ]

        "chaine" ->
            exemple [ ( "hAB", ab ), ( "hBC", bc ), ( "hCD", Implique c d ) ] (Implique a d) []

        "cas" ->
            exemple [ ( "hOu", Ou a b ), ( "hAC", Implique a c ), ( "hBC", bc ) ]
                c
                [ regle "cas"
                    "ouE"
                    [ ( "A", a ), ( "B", b ), ( "C", c ) ]
                    [ [ fait "casOu" "hOu" (Ou a b) ]
                    , [ regle "casA" "implE" [ ( "A", a ), ( "B", c ) ] [ [ fait "casAC" "hAC" (Implique a c) ], [ fait "casHA" (hypotheseId "cas" 1 0) a ] ] ]
                    , [ regle "casB" "implE" [ ( "A", b ), ( "B", c ) ] [ [ fait "casBC" "hBC" bc ], [ fait "casHB" (hypotheseId "cas" 2 0) b ] ] ]
                    ]
                ]

        "contraposition" ->
            exemple [ ( "hAB", ab ) ]
                (Implique (Non b) (Non a))
                [ regle "contra"
                    "implI"
                    [ ( "A", Non b ), ( "B", Non a ) ]
                    [ [ application "nonA"
                            "fourni-nonI"
                            [ ( "A", a ) ]
                            [ [ application "contradiction"
                                    "fourni-contradiction"
                                    [ ( "A", b ) ]
                                    [ [ regle "contraB" "implE" [ ( "A", a ), ( "B", b ) ] [ [ fait "contraAB" "hAB" ab ], [ fait "contraA" (hypotheseId "nonA" 0 0) a ] ] ]
                                    , [ fait "contraNonB" (hypotheseId "contra" 0 0) (Non b) ]
                                    ]
                              ]
                            ]
                      ]
                    ]
                ]

        "classique" ->
            exemple [ ( "hNonNonA", Non (Non a) ) ]
                a
                [ regle "classique"
                    "RA"
                    [ ( "A", a ) ]
                    [ [ application "contrClassique" "fourni-contradiction" [ ( "A", Non a ) ] [ [ fait "refNonA" (hypotheseId "classique" 0 0) (Non a) ], [ fait "refNonNonA" "hNonNonA" (Non (Non a)) ] ] ] ]
                ]

        _ ->
            vide
