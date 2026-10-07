module Atelier.Graphe exposing (..)

import Atelier.Formule as F exposing (Formule)
import Atelier.Types exposing (..)
import Dict exposing (Dict)
import Set exposing (Set)


noeuds : List Preuve -> List DonneesBloc
noeuds =
    List.concatMap (\(Bloc b) -> b :: List.concatMap noeuds b.entrees)


trouver : String -> List Preuve -> Maybe DonneesBloc
trouver id =
    noeuds >> List.filter (\b -> b.id == id) >> List.head


transformer : (DonneesBloc -> DonneesBloc) -> List Preuve -> List Preuve
transformer fn =
    List.map (\(Bloc b) -> Bloc (fn { b | entrees = List.map (transformer fn) b.entrees }))


formules : List Preuve -> List Formule
formules =
    noeuds >> List.concatMap (.parametres >> Dict.values)


substituer : Dict String Formule -> List Preuve -> List Preuve
substituer valeurs =
    transformer (\b -> { b | parametres = Dict.map (\_ -> F.substituer valeurs) b.parametres })


generaliser : Set String -> List Preuve -> List Preuve
generaliser noms =
    transformer (\b -> { b | parametres = Dict.map (\_ -> F.generaliser noms) b.parametres })


{-| Renommer simultanément toutes les identités internes et leurs références,
y compris les lieurs dérivés du couple (bloc, indice). Les références extérieures
restent inchangées. Une duplication ne capture donc jamais un autre contexte.
-}
renommer : (String -> String) -> List Preuve -> List Preuve
renommer fn =
    transformer
        (\b ->
            { b
                | id = fn b.id
                , regle =
                    case b.regle of
                        Reference ref ->
                            Reference (fn ref)

                        autre ->
                            autre
            }
        )


renommage : String -> List Preuve -> String -> String
renommage prefixe preuves id =
    let
        correspondances =
            noeuds preuves |> List.map .id |> List.sortBy (String.length >> negate)
    in
    List.filter (\ancien -> id == ancien || String.startsWith (ancien ++ "/h/") id) correspondances
        |> List.head
        |> Maybe.map (\ancien -> prefixe ++ ancien ++ String.dropLeft (String.length ancien) id)
        |> Maybe.withDefault id


dupliquer : String -> List Preuve -> List Preuve
dupliquer prefixe preuves =
    renommer (renommage prefixe preuves) preuves


dependances : List Preuve -> List ( String, Int )
dependances =
    noeuds
        >> List.filterMap
            (\b ->
                case b.regle of
                    Application id v ->
                        Just ( id, v )

                    _ ->
                        Nothing
            )
        >> Set.fromList
        >> Set.toList


retirer : String -> List Preuve -> List Preuve
retirer id =
    List.filter (identifiant >> (/=) id) >> List.map (\(Bloc b) -> Bloc { b | entrees = List.map (retirer id) b.entrees })


type alias Cible =
    { parent : String, indice : Int, position : Int }


cibleTexte : Cible -> String
cibleTexte c =
    c.parent ++ "|" ++ String.fromInt c.indice ++ "|" ++ String.fromInt c.position


lireCible : String -> Maybe Cible
lireCible s =
    case String.split "|" s of
        [ parent, i, j ] ->
            Maybe.map2 (Cible parent) (String.toInt i) (String.toInt j)

        _ ->
            Nothing


inserer : Cible -> Preuve -> List Preuve -> Result String (List Preuve)
inserer cible preuve preuves =
    let
        insererIci liste =
            if cible.position < 0 || cible.position > List.length liste then
                Err "La position a changé. Sélectionnez à nouveau l’emplacement."

            else
                Ok (List.take cible.position liste ++ [ preuve ] ++ List.drop cible.position liste)
    in
    if cible.parent == "racine" then
        insererIci preuves

    else
        case trouver cible.parent preuves of
            Nothing ->
                Err "Cavité introuvable."

            Just parent ->
                case List.drop cible.indice parent.entrees |> List.head of
                    Nothing ->
                        Err "Cavité introuvable."

                    Just liste ->
                        insererIci liste
                            |> Result.map
                                (\nouvelle ->
                                    transformer
                                        (\b ->
                                            if b.id == cible.parent then
                                                { b
                                                    | entrees =
                                                        List.indexedMap
                                                            (\i xs ->
                                                                if i == cible.indice then
                                                                    nouvelle

                                                                else
                                                                    xs
                                                            )
                                                            b.entrees
                                                }

                                            else
                                                b
                                        )
                                        preuves
                                )


sequence : Cible -> List Preuve -> Maybe (List Preuve)
sequence cible preuves =
    if cible.parent == "racine" then
        Just preuves

    else
        trouver cible.parent preuves |> Maybe.andThen (.entrees >> List.drop cible.indice >> List.head)


position : String -> List Preuve -> Maybe Cible
position recherche preuves =
    let
        parcourir parent indice liste =
            List.indexedMap
                (\index (Bloc b) ->
                    if b.id == recherche then
                        Just { parent = parent, indice = indice, position = index }

                    else
                        b.entrees |> List.indexedMap (parcourir b.id) |> List.filterMap identity |> List.head
                )
                liste
                |> List.filterMap identity
                |> List.head
    in
    parcourir "racine" 0 preuves


{-| Ne garder, dans chaque séquence, que la dernière étape et les étapes
antérieures dont elle cite la sortie. L'ordre est conservé. À utiliser après
validation de toute la sélection : un trou inutilisé ne doit pas être effacé
pour permettre une certification. La construction éditée n'est pas modifiée.
-}
elaguer : List Preuve -> List Preuve
elaguer preuves =
    let
        nettoyees =
            List.map (\(Bloc b) -> Bloc { b | entrees = List.map elaguer b.entrees }) preuves

        fermer ids =
            let
                references =
                    nettoyees
                        |> List.filter (identifiant >> (\id -> Set.member id ids))
                        |> noeuds
                        |> List.filterMap
                            (\b ->
                                case b.regle of
                                    Reference ref ->
                                        Just ref

                                    _ ->
                                        Nothing
                            )
                        |> Set.fromList

                nouveaux =
                    Set.union ids references
            in
            if nouveaux == ids then
                ids

            else
                fermer nouveaux

        necessaires =
            List.reverse nettoyees |> List.head |> Maybe.map (identifiant >> Set.singleton >> fermer) |> Maybe.withDefault Set.empty
    in
    List.filter (identifiant >> (\id -> Set.member id necessaires)) nettoyees
