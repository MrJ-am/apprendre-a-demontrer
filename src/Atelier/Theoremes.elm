module Atelier.Theoremes exposing (developper, extraire)

import Atelier.Formule as F exposing (Formule(..))
import Atelier.Graphe as G
import Atelier.Noyau as N
import Atelier.Regles as R
import Atelier.Types exposing (..)
import Dict
import Set exposing (Set)


{-| L'extraction crée une définition sans supprimer la construction sélectionnée.
Sa frontière est l'ensemble des références effectivement citées et extérieures
au sous-arbre. Deux lieurs de même formule restent deux entrées ; deux citations
du même fait donnent une seule entrée. Les hypothèses internes déchargées ne
franchissent jamais cette frontière. La généralisation est fournie explicitement.
-}
extraire : Bibliotheque -> Contexte -> String -> Int -> String -> Set String -> List Preuve -> Result Probleme Definition
extraire bibliotheque contexte id version nom generalises selection =
    let
        preuves =
            G.elaguer selection

        internes =
            G.noeuds preuves |> List.concatMap (\b -> b.id :: (R.contrat bibliotheque b |> Result.map (.entrees >> List.concatMap .hypotheses >> List.map .id) |> Result.withDefault [])) |> Set.fromList

        externes =
            G.noeuds preuves
                |> List.filterMap
                    (\b ->
                        case b.regle of
                            Reference ref ->
                                if Set.member ref internes then
                                    Nothing

                                else
                                    Just ref

                            _ ->
                                Nothing
                    )
                |> List.foldl
                    (\ref refs ->
                        if List.member ref refs then
                            refs

                        else
                            refs ++ [ ref ]
                    )
                    []
                |> List.sort

        indices =
            List.indexedMap (\i ref -> ( ref, i )) externes |> Dict.fromList

        reecrire b =
            case b.regle of
                Reference ref ->
                    Dict.get ref indices |> Maybe.map (\i -> { b | regle = Argument i, parametres = Dict.empty }) |> Maybe.withDefault b

                _ ->
                    b

        entrees =
            List.filterMap (\ref -> Dict.get ref contexte |> Maybe.map (.conclusion >> F.generaliser generalises >> R.entreeOrdinaire)) externes
    in
    N.controlerIdentites bibliotheque [] selection
        |> Result.andThen (\_ -> N.verifierSequence bibliotheque contexte selection)
        |> Result.andThen
            (\v ->
                let
                    certificat =
                        G.transformer reecrire preuves |> G.generaliser generalises

                    def =
                        { id = id, version = version, nom = nom, parametres = Set.toList generalises, entrees = entrees, conclusion = F.generaliser generalises v.conclusion, certificat = certificat, dependances = G.dependances certificat }
                in
                if String.isEmpty (String.trim nom) then
                    Err (Erreur "Donnez un nom au théorème.")

                else if List.length entrees /= List.length externes then
                    Err (Erreur "La sélection contient une référence extérieure indisponible.")

                else
                    N.verifierDefinition (def :: bibliotheque) def |> Result.map (\_ -> def)
            )


{-| Expansion d'une occurrence, avec conservation de son identité de sortie.
Le certificat et chaque usage d'une entrée sont alpha-renommés séparément. Les
hypothèses locales du port fourni sont reliées aux lieurs frais du certificat.
L'enchaînement est un simple conteneur de séquence, pas une règle supplémentaire.
-}
developper : Bibliotheque -> Contexte -> Preuve -> Result Probleme Preuve
developper bibliotheque contexte (Bloc b) =
    case b.regle of
        Application id version ->
            case trouverDefinition bibliotheque id version of
                Nothing ->
                    Err (Erreur "Définition absente.")

                Just def ->
                    N.verifierBloc bibliotheque contexte (Bloc b)
                        |> Result.andThen
                            (\avant ->
                                let
                                    renomme =
                                        G.renommage (b.id ++ "/developpement/") def.certificat

                                    liaisons =
                                        List.indexedMap (\i e -> List.indexedMap (\j h -> ( hypotheseId b.id i j, renomme h.id )) e.hypotheses) def.entrees |> List.concat |> Dict.fromList

                                    remplacerArgument noeud =
                                        case noeud.regle of
                                            Argument index ->
                                                let
                                                    fournie =
                                                        List.drop index b.entrees |> List.head |> Maybe.withDefault []

                                                    copie =
                                                        G.dupliquer (noeud.id ++ "/fourni/") fournie |> G.renommer (\ancien -> Dict.get ancien liaisons |> Maybe.withDefault ancien)

                                                    objectif =
                                                        List.drop index def.entrees |> List.head |> Maybe.map (.conclusion >> F.substituer b.parametres) |> Maybe.withDefault (Trou "entrée")
                                                in
                                                { noeud | regle = Enchainement, parametres = Dict.singleton "S" objectif, entrees = [ copie ] }

                                            _ ->
                                                noeud

                                    certificat =
                                        G.substituer b.parametres def.certificat |> G.renommer renomme |> G.transformer remplacerArgument

                                    resultat =
                                        Bloc { b | regle = Enchainement, parametres = Dict.singleton "S" avant.conclusion, entrees = [ certificat ] }
                                in
                                N.controlerIdentites bibliotheque [] [ resultat ]
                                    |> Result.andThen (\_ -> N.verifierBloc bibliotheque contexte resultat)
                                    |> Result.andThen
                                        (\apres ->
                                            if F.egales avant.conclusion apres.conclusion && avant.libres == apres.libres && avant.classique == apres.classique then
                                                Ok resultat

                                            else
                                                Err (Erreur "Le développement ne conserve pas exactement les dépendances de l’interface.")
                                        )
                            )

        _ ->
            Err (Erreur "Sélectionnez une application de théorème.")
