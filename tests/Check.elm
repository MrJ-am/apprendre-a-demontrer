port module Check exposing (main)

import Course
import Exercise
import Json.Decode as D
import Json.Encode as E
import Platform


port finished : E.Value -> Cmd msg


type alias Check =
    { name : String, stepId : String, answer : String, expected : Bool }


decoder : D.Decoder Check
decoder =
    D.map4 Check (D.field "name" D.string) (D.field "stepId" D.string) (D.field "answer" D.string) (D.field "expected" D.bool)


main : Program D.Value () Never
main =
    Platform.worker
        { init =
            \flags ->
                let
                    result =
                        D.decodeValue (D.map2 Tuple.pair (D.field "course" Course.decoder) (D.field "checks" (D.list decoder))) flags
                in
                ( ()
                , finished
                    (case result of
                        Err error ->
                            E.object [ ( "error", E.string (D.errorToString error) ) ]

                        Ok ( course, checks ) ->
                            E.list
                                (\check ->
                                    let
                                        found =
                                            Course.steps course |> List.filter (\step -> step.id == check.stepId) |> List.head

                                        verdict =
                                            found |> Maybe.map (\step -> Exercise.check step check.answer) |> Maybe.withDefault (Err "Exercice introuvable")

                                        correct =
                                            verdict == Ok ()
                                    in
                                    E.object
                                        [ ( "name", E.string check.name )
                                        , ( "passed", E.bool (found /= Nothing && correct == check.expected) )
                                        , ( "correct", E.bool correct )
                                        , ( "feedback"
                                          , E.string
                                                (case verdict of
                                                    Err text ->
                                                        text

                                                    Ok _ ->
                                                        ""
                                                )
                                          )
                                        ]
                                )
                                checks
                    )
                )
        , update = \impossible _ -> never impossible
        , subscriptions = \_ -> Sub.none
        }
