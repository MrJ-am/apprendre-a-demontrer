module Atelier.Types exposing (..)

import Atelier.Formule exposing (Formule)
import Dict exposing (Dict)


type Regle
    = Primitive String
    | Reference String
    | Application String Int
    | Argument Int
    | Enchainement


type Preuve
    = Bloc DonneesBloc


type alias DonneesBloc =
    { id : String
    , regle : Regle
    , parametres : Dict String Formule
    , entrees : List (List Preuve)
    }


type alias Hypothese =
    { id : String, formule : Formule }


{-| Dans un certificat, les identifiants des hypothèses du port désignent les
lieurs internes sous lesquels l'argument de preuve doit être fourni. Pour une
occurrence, ils sont renommés en fonction de l'identité du bloc et du port.
-}
type alias Port =
    { hypotheses : List Hypothese, conclusion : Formule }


type alias Contrat =
    { entrees : List Port, conclusion : Formule }


type alias Definition =
    { id : String
    , version : Int
    , nom : String
    , parametres : List String
    , entrees : List Port
    , conclusion : Formule
    , certificat : List Preuve
    , dependances : List ( String, Int )
    }


type alias Bibliotheque =
    List Definition


type alias Document =
    { premisses : List Hypothese
    , objectif : Formule
    , preuves : List Preuve
    , bibliotheque : Bibliotheque
    , prochain : Int
    }


type Probleme
    = Incomplet String
    | Erreur String


type alias Verdict =
    { conclusion : Formule
    , libres : Dict String Formule
    , classique : Bool
    }


type alias Contexte =
    Dict String Verdict


identifiant : Preuve -> String
identifiant (Bloc b) =
    b.id


hypotheseId : String -> Int -> Int -> String
hypotheseId bloc entree index =
    bloc ++ "/h/" ++ String.fromInt entree ++ "/" ++ String.fromInt index


cle : String -> Int -> String
cle id version =
    id ++ "@" ++ String.fromInt version


trouverDefinition : Bibliotheque -> String -> Int -> Maybe Definition
trouverDefinition bibliotheque id version =
    List.filter (\d -> d.id == id && d.version == version) bibliotheque |> List.head


messageProbleme : Probleme -> String
messageProbleme p =
    case p of
        Incomplet s ->
            s

        Erreur s ->
            s
