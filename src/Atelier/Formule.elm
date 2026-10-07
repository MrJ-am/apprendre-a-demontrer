module Atelier.Formule exposing (Formule(..), afficher, atomes, complete, decoder, definir, egales, encoder, generaliser, lire, map, parametres, remplacer, substituer)

{-| Syntaxe propre à l'atelier. Aucune normalisation sémantique : seules ¬ et ⇔
sont des abréviations définitionnelles. Un paramètre n'est pas un atome et un
trou n'est ni l'un ni l'autre. La substitution est simultanée (non récursive
sur ses images), ce qui permet A := A ∧ B sans cycle de métavariables.
-}

import Char
import Dict exposing (Dict)
import Json.Decode as D
import Json.Encode as E
import Parser as P exposing ((|.), (|=), Parser)
import Set exposing (Set)


type Formule
    = Atome String
    | Parametre String
    | Trou String
    | Faux
    | Et Formule Formule
    | Ou Formule Formule
    | Implique Formule Formule
    | Non Formule
    | Equivalent Formule Formule


map : (Formule -> Formule) -> Formule -> Formule
map f formule =
    f
        (case formule of
            Et a b ->
                Et (map f a) (map f b)

            Ou a b ->
                Ou (map f a) (map f b)

            Implique a b ->
                Implique (map f a) (map f b)

            Equivalent a b ->
                Equivalent (map f a) (map f b)

            Non a ->
                Non (map f a)

            _ ->
                formule
        )


substituer : Dict String Formule -> Formule -> Formule
substituer substitutions =
    map
        (\f ->
            case f of
                Parametre p ->
                    Dict.get p substitutions |> Maybe.withDefault f

                _ ->
                    f
        )


generaliser : Set String -> Formule -> Formule
generaliser noms =
    map
        (\f ->
            case f of
                Atome a ->
                    if Set.member a noms then
                        Parametre a

                    else
                        f

                _ ->
                    f
        )


collecter : (Formule -> Maybe String) -> Formule -> Set String
collecter f formule =
    let
        enfants =
            case formule of
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
    in
    List.foldl Set.union (f formule |> Maybe.map Set.singleton |> Maybe.withDefault Set.empty) (List.map (collecter f) enfants)


atomes : Formule -> Set String
atomes =
    collecter
        (\f ->
            case f of
                Atome a ->
                    Just a

                _ ->
                    Nothing
        )


parametres : Formule -> Set String
parametres =
    collecter
        (\f ->
            case f of
                Parametre a ->
                    Just a

                _ ->
                    Nothing
        )


complete : Formule -> Bool
complete =
    collecter
        (\f ->
            case f of
                Trou a ->
                    Just a

                _ ->
                    Nothing
        )
        >> Set.isEmpty


definir : Formule -> Formule
definir =
    map
        (\f ->
            case f of
                Non a ->
                    Implique a Faux

                Equivalent a b ->
                    Et (Implique a b) (Implique b a)

                _ ->
                    f
        )


egales : Formule -> Formule -> Bool
egales a b =
    definir a == definir b


afficher : Formule -> String
afficher formule =
    let
        membre f =
            case f of
                Atome _ ->
                    afficher f

                Parametre _ ->
                    afficher f

                Trou _ ->
                    afficher f

                Faux ->
                    afficher f

                Non _ ->
                    afficher f

                _ ->
                    "(" ++ afficher f ++ ")"

        deux op a b =
            membre a ++ " " ++ op ++ " " ++ membre b
    in
    case formule of
        Atome a ->
            a

        Parametre a ->
            a

        Trou _ ->
            "□"

        Faux ->
            "⊥"

        Et a b ->
            deux "∧" a b

        Ou a b ->
            deux "∨" a b

        Implique a b ->
            deux "⇒" a b

        Non a ->
            "¬" ++ membre a

        Equivalent a b ->
            deux "⇔" a b


{-| Chemin dans l'arbre syntaxique, indépendant de la position à l'écran.
-}
remplacer : List Int -> Formule -> Formule -> Formule
remplacer chemin valeur formule =
    case chemin of
        [] ->
            valeur

        i :: suite ->
            let
                deux constructeur a b =
                    if i == 0 then
                        constructeur (remplacer suite valeur a) b

                    else
                        constructeur a (remplacer suite valeur b)
            in
            case formule of
                Et a b ->
                    deux Et a b

                Ou a b ->
                    deux Ou a b

                Implique a b ->
                    deux Implique a b

                Equivalent a b ->
                    deux Equivalent a b

                Non a ->
                    Non (remplacer suite valeur a)

                _ ->
                    formule


token : String -> Parser ()
token s =
    P.symbol s |. P.spaces


expression : Parser Formule
expression =
    implication |> P.andThen (\a -> P.oneOf [ P.succeed (Equivalent a) |. token "⇔" |= P.lazy (\_ -> expression), P.succeed a ])


implication : Parser Formule
implication =
    disjonction |> P.andThen (\a -> P.oneOf [ P.succeed (Implique a) |. token "⇒" |= P.lazy (\_ -> implication), P.succeed a ])


chaine : String -> (Formule -> Formule -> Formule) -> Parser Formule -> Parser Formule
chaine op constructeur terme =
    terme |> P.andThen (\a -> P.loop a (\g -> P.oneOf [ P.succeed (\d -> P.Loop (constructeur g d)) |. token op |= terme, P.succeed (P.Done g) ]))


disjonction : Parser Formule
disjonction =
    chaine "∨" Ou (chaine "∧" Et unaire)


unaire : Parser Formule
unaire =
    P.oneOf
        [ P.succeed Non |. token "¬" |= P.lazy (\_ -> unaire)
        , P.succeed Faux |. token "⊥"
        , P.succeed identity |. token "(" |= P.lazy (\_ -> expression) |. token ")"
        , P.map Atome (P.variable { start = Char.isAlpha, inner = \c -> Char.isAlphaNum c || c == '_' || c == '\'', reserved = Set.fromList [ "forall", "exists" ] }) |. P.spaces
        ]


lire : String -> Result String Formule
lire source =
    if String.length source > 500 || List.length (String.indexes "(" source) > 40 then
        Err "Cette formule dépasse la taille du prototype."

    else
        let
            normalisee =
                List.foldl (\( a, b ) -> String.replace a b) source [ ( "<=>", "⇔" ), ( "<->", "⇔" ), ( "=>", "⇒" ), ( "->", "⇒" ), ( "→", "⇒" ), ( "~", "¬" ), ( "!", "¬" ), ( "&", "∧" ), ( "|", "∨" ) ]
        in
        P.run (P.succeed identity |. P.spaces |= expression |. P.end) normalisee |> Result.mapError (\_ -> "Formule illisible : utilisez des atomes, ∧, ∨, ⇒, ¬, ⇔, ⊥ et des parenthèses. Les quantificateurs ne sont pas encore pris en charge.")


encoder : Formule -> E.Value
encoder f =
    let
        tag genre xs =
            E.object [ ( "type", E.string genre ), ( "arguments", E.list encoder xs ) ]

        nom t a =
            E.object [ ( "type", E.string t ), ( "nom", E.string a ) ]
    in
    case f of
        Atome a ->
            nom "atome" a

        Parametre a ->
            nom "parametre" a

        Trou a ->
            nom "trou" a

        Faux ->
            tag "faux" []

        Et a b ->
            tag "et" [ a, b ]

        Ou a b ->
            tag "ou" [ a, b ]

        Implique a b ->
            tag "implique" [ a, b ]

        Non a ->
            tag "non" [ a ]

        Equivalent a b ->
            tag "equivalent" [ a, b ]


decoder : D.Decoder Formule
decoder =
    decodeProfondeur 0


decodeProfondeur : Int -> D.Decoder Formule
decodeProfondeur profondeur =
    if profondeur > 60 then
        D.fail "Formule trop profonde."

    else
        D.field "type" D.string
            |> D.andThen
                (\t ->
                    let
                        enfant =
                            D.lazy (\_ -> decodeProfondeur (profondeur + 1))

                        args =
                            D.field "arguments"

                        deux c =
                            args (D.list enfant)
                                |> D.andThen
                                    (\xs ->
                                        case xs of
                                            [ a, b ] ->
                                                D.succeed (c a b)

                                            _ ->
                                                D.fail "Connecteur binaire mal formé."
                                    )

                        nom c =
                            D.field "nom" D.string
                                |> D.andThen
                                    (\s ->
                                        if String.isEmpty s || String.length s > 80 then
                                            D.fail "Nom incorrect."

                                        else
                                            D.succeed (c s)
                                    )
                    in
                    case t of
                        "atome" ->
                            D.field "nom" D.string
                                |> D.andThen
                                    (\s ->
                                        case lire s of
                                            Ok (Atome identifiant) ->
                                                if identifiant == s then
                                                    D.succeed (Atome s)

                                                else
                                                    D.fail "Nom d’atome invalide."

                                            _ ->
                                                D.fail "Un atome doit être un nom ; les quantificateurs ne sont pas des atomes."
                                    )

                        "parametre" ->
                            nom Parametre

                        "trou" ->
                            nom Trou

                        "faux" ->
                            D.succeed Faux

                        "et" ->
                            deux Et

                        "ou" ->
                            deux Ou

                        "implique" ->
                            deux Implique

                        "equivalent" ->
                            deux Equivalent

                        "non" ->
                            args (D.list enfant)
                                |> D.andThen
                                    (\xs ->
                                        case xs of
                                            [ a ] ->
                                                D.succeed (Non a)

                                            _ ->
                                                D.fail "Négation mal formée."
                                    )

                        _ ->
                            D.fail "Connecteur inconnu."
                )
