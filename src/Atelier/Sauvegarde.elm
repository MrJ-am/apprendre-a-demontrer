module Atelier.Sauvegarde exposing (decoder, encoder, lire, preuveDecoder, preuveEncoder)

{-| Format déclaratif versionné. Le JSON décrit des arbres ; aucun code ni verdict
persisté n'est exécuté ou cru. Les certificats sont revérifiés à chaque import.
Les limites de taille/profondeur protègent aussi l'import accidentel d'un gros fichier.
-}

import Atelier.Formule as F
import Atelier.Graphe as G
import Atelier.Noyau as N
import Atelier.Types exposing (..)
import Dict
import Json.Decode as D
import Json.Encode as E
import Set


hypEncoder : Hypothese -> E.Value
hypEncoder h =
    E.object [ ( "id", E.string h.id ), ( "formule", F.encoder h.formule ) ]


hypDecoder : D.Decoder Hypothese
hypDecoder =
    D.map2 Hypothese (D.field "id" D.string) (D.field "formule" F.decoder)


entreeEncoder : Port -> E.Value
entreeEncoder e =
    E.object [ ( "hypotheses", E.list hypEncoder e.hypotheses ), ( "conclusion", F.encoder e.conclusion ) ]


entreeDecoder : D.Decoder Port
entreeDecoder =
    D.map2 Port (D.field "hypotheses" (D.list hypDecoder)) (D.field "conclusion" F.decoder)


regleEncoder : Regle -> E.Value
regleEncoder r =
    let
        tag t champs =
            E.object (( "type", E.string t ) :: champs)
    in
    case r of
        Primitive p ->
            tag "primitive" [ ( "nom", E.string p ) ]

        Reference id ->
            tag "reference" [ ( "id", E.string id ) ]

        Application id version ->
            tag "application" [ ( "id", E.string id ), ( "version", E.int version ) ]

        Argument i ->
            tag "argument" [ ( "indice", E.int i ) ]

        Enchainement ->
            tag "sequence" []


regleDecoder : D.Decoder Regle
regleDecoder =
    D.field "type" D.string
        |> D.andThen
            (\t ->
                case t of
                    "primitive" ->
                        D.map Primitive (D.field "nom" D.string)

                    "reference" ->
                        D.map Reference (D.field "id" D.string)

                    "application" ->
                        D.map2 Application (D.field "id" D.string) (D.field "version" D.int)

                    "argument" ->
                        D.map Argument (D.field "indice" D.int)

                    "sequence" ->
                        D.succeed Enchainement

                    _ ->
                        D.fail "Type de justification inconnu."
            )


preuveEncoder : Preuve -> E.Value
preuveEncoder (Bloc b) =
    E.object
        [ ( "id", E.string b.id ), ( "regle", regleEncoder b.regle ), ( "parametres", E.dict identity F.encoder b.parametres ), ( "entrees", E.list (E.list preuveEncoder) b.entrees ) ]


preuveDecoder : D.Decoder Preuve
preuveDecoder =
    preuveProfondeur 0


preuveProfondeur : Int -> D.Decoder Preuve
preuveProfondeur profondeur =
    if profondeur > 60 then
        D.fail "Preuve trop profonde."

    else
        D.map4 (\id regle params entrees -> Bloc { id = id, regle = regle, parametres = params, entrees = entrees })
            (D.field "id" D.string)
            (D.field "regle" regleDecoder)
            (D.field "parametres" (D.dict F.decoder))
            (D.field "entrees" (D.list (D.list (D.lazy (\_ -> preuveProfondeur (profondeur + 1))))))


depEncoder : ( String, Int ) -> E.Value
depEncoder ( id, version ) =
    E.object [ ( "id", E.string id ), ( "version", E.int version ) ]


defEncoder : Definition -> E.Value
defEncoder d =
    E.object
        [ ( "id", E.string d.id ), ( "version", E.int d.version ), ( "nom", E.string d.nom ), ( "parametres", E.list E.string d.parametres ), ( "entrees", E.list entreeEncoder d.entrees ), ( "conclusion", F.encoder d.conclusion ), ( "certificat", E.list preuveEncoder d.certificat ), ( "dependances", E.list depEncoder d.dependances ) ]


defDecoder : D.Decoder Definition
defDecoder =
    D.map8 Definition
        (D.field "id" D.string)
        (D.field "version" D.int)
        (D.field "nom" D.string)
        (D.field "parametres" (D.list D.string))
        (D.field "entrees" (D.list entreeDecoder))
        (D.field "conclusion" F.decoder)
        (D.field "certificat" (D.list preuveDecoder))
        (D.field "dependances" (D.list (D.map2 Tuple.pair (D.field "id" D.string) (D.field "version" D.int))))


encoder : Document -> E.Value
encoder d =
    E.object
        [ ( "format", E.string "atelier-preuves" ), ( "version", E.int 1 ), ( "premisses", E.list hypEncoder d.premisses ), ( "objectif", F.encoder d.objectif ), ( "preuves", E.list preuveEncoder d.preuves ), ( "bibliotheque", E.list defEncoder d.bibliotheque ), ( "prochain", E.int d.prochain ) ]


decoder : D.Decoder Document
decoder =
    D.map2 Tuple.pair (D.field "format" D.string) (D.field "version" D.int)
        |> D.andThen
            (\( format, version ) ->
                if format /= "atelier-preuves" || version /= 1 then
                    D.fail "Format de sauvegarde inconnu. Le travail actuel est conservé."

                else
                    D.map5 Document
                        (D.field "premisses" (D.list hypDecoder))
                        (D.field "objectif" F.decoder)
                        (D.field "preuves" (D.list preuveDecoder))
                        (D.field "bibliotheque" (D.list defDecoder))
                        (D.field "prochain" D.int)
            )


lire : String -> Result String Document
lire source =
    if String.length source > 2000000 then
        Err "Le fichier dépasse 2 Mo. Le travail actuel est conservé."

    else
        D.decodeString decoder source
            |> Result.mapError D.errorToString
            |> Result.andThen
                (\doc ->
                    N.verifierBibliotheque doc.bibliotheque
                        |> Result.andThen (\_ -> N.controlerIdentites doc.bibliotheque doc.premisses doc.preuves)
                        |> Result.mapError messageProbleme
                        |> Result.andThen
                            (\_ ->
                                let
                                    formes =
                                        doc.objectif :: List.map .formule doc.premisses ++ G.formules doc.preuves

                                    depAbsente =
                                        G.dependances doc.preuves |> List.any (\( id, v ) -> trouverDefinition doc.bibliotheque id v == Nothing)
                                in
                                if doc.prochain < 0 || doc.prochain > 10000000 || List.any (F.parametres >> Set.isEmpty >> not) formes || depAbsente then
                                    Err "Compteur, paramètres libres ou dépendances de document invalides."

                                else
                                    Ok doc
                            )
                )
