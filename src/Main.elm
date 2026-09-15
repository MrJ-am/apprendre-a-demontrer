port module Main exposing (main)

import Browser
import Browser.Navigation as Nav
import Char
import Course exposing (Choice, Course, Kind(..), Lesson, Step, Track)
import Dict exposing (Dict)
import Exercise
import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (onClick, onInput, onSubmit)
import Json.Decode as D
import Json.Encode as E
import Url exposing (Url)


port reportState : E.Value -> Cmd msg


port agentAction : (D.Value -> msg) -> Sub msg


port focusElement : String -> Cmd msg


type alias Response =
    { value : String, verdict : Maybe (Result String ()), hint : Bool }


type alias Model =
    { course : Result String Course
    , key : Nav.Key
    , url : Url
    , responses : Dict String Response
    , recap : Bool
    , pending : Maybe String
    }


type Msg
    = LinkClicked Browser.UrlRequest
    | UrlChanged Url
    | Edit String
    | AppendSymbol String
    | Verify
    | Hint
    | Previous
    | Next
    | Review
    | SelectLesson String
    | Agent D.Value


type alias Position =
    { track : Track, lesson : Lesson, index : Int, step : Step }


emptyResponse : Response
emptyResponse =
    { value = "", verdict = Nothing, hint = False }


main : Program D.Value Model Msg
main =
    Browser.application
        { init = init
        , view = view
        , update = update
        , subscriptions = \_ -> agentAction Agent
        , onUrlRequest = LinkClicked
        , onUrlChange = UrlChanged
        }


init : D.Value -> Url -> Nav.Key -> ( Model, Cmd Msg )
init flags url key =
    let
        model =
            { course = D.decodeValue Course.decoder flags |> Result.mapError D.errorToString, key = key, url = url, responses = Dict.empty, recap = False, pending = Nothing }
    in
    ( model, emit model )


route : Model -> List String
route model =
    model.url.fragment |> Maybe.withDefault "" |> String.split "/" |> List.filter (not << String.isEmpty)


position : Model -> Maybe Position
position model =
    Result.toMaybe model.course
        |> Maybe.andThen
            (\course ->
                let
                    first =
                        course.tracks |> List.head |> Maybe.andThen (\t -> List.head t.lessons |> Maybe.map (Tuple.pair t))

                    located =
                        case route model of
                            trackId :: lessonId :: _ ->
                                Course.findLesson course trackId lessonId

                            [] ->
                                first

                            _ ->
                                Nothing

                    requested =
                        route model |> List.drop 2 |> List.head |> Maybe.andThen String.toInt |> Maybe.withDefault 1
                in
                located
                    |> Maybe.andThen
                        (\( t, l ) ->
                            let
                                index =
                                    clamp 0 (List.length l.steps - 1) (requested - 1)
                            in
                            l.steps |> List.drop index |> List.head |> Maybe.map (\s -> { track = t, lesson = l, index = index, step = s })
                        )
            )


response : Model -> Step -> Response
response model step =
    Dict.get step.id model.responses |> Maybe.withDefault emptyResponse


isCorrect : Response -> Bool
isCorrect r =
    r.verdict == Just (Ok ())


completed : Model -> List Step -> Int
completed model =
    List.filter (response model >> isCorrect) >> List.length


lessonUrl : Track -> Lesson -> Int -> String
lessonUrl track lesson index =
    "#/" ++ track.id ++ "/" ++ lesson.id ++ "/" ++ String.fromInt (index + 1)


navigate : Model -> String -> ( Model, Cmd Msg )
navigate model url =
    ( model, Nav.pushUrl model.key url )


save : Model -> Step -> Response -> Model
save model step value =
    { model | responses = Dict.insert step.id value model.responses }


submit : Model -> Position -> String -> Model
submit model pos answer =
    let
        old =
            response model pos.step
    in
    save model pos.step { old | value = answer, verdict = Just (Exercise.check pos.step answer) }


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    let
        withPosition fn =
            position model |> Maybe.map fn |> Maybe.withDefault ( model, Cmd.none )

        changed updated =
            ( updated, emit updated )
    in
    case msg of
        LinkClicked (Browser.Internal url) ->
            if url.fragment == Just "lesson-heading" then
                ( model, focusElement "lesson-heading" )

            else
                navigate model (Url.toString url)

        LinkClicked (Browser.External url) ->
            ( model, Nav.load url )

        UrlChanged url ->
            let
                updated =
                    { model | url = url, recap = False }
            in
            ( { updated | pending = Nothing }, Cmd.batch [ emit updated, focusElement "lesson-heading" ] )

        Edit value ->
            withPosition
                (\pos ->
                    let
                        old =
                            response model pos.step
                    in
                    changed (save model pos.step { old | value = String.left 500 value, verdict = Nothing })
                )

        AppendSymbol symbol ->
            withPosition
                (\pos ->
                    let
                        old =
                            response model pos.step
                    in
                    ( save model pos.step { old | value = String.left 500 (old.value ++ symbol), verdict = Nothing }, Cmd.batch [ emit (save model pos.step { old | value = String.left 500 (old.value ++ symbol), verdict = Nothing }), focusElement "answer-input" ] )
                )

        Verify ->
            withPosition
                (\pos ->
                    let
                        updated =
                            submit model pos (response model pos.step).value
                    in
                    ( updated, Cmd.batch [ emit updated, focusElement "feedback" ] )
                )

        Hint ->
            withPosition
                (\pos ->
                    let
                        old =
                            response model pos.step
                    in
                    changed (save model pos.step { old | hint = not old.hint })
                )

        Previous ->
            withPosition (\pos -> navigate model (lessonUrl pos.track pos.lesson (Basics.max 0 (pos.index - 1))))

        Next ->
            withPosition
                (\pos ->
                    if not (isCorrect (response model pos.step)) then
                        update Verify model

                    else if pos.index < List.length pos.lesson.steps - 1 then
                        navigate model (lessonUrl pos.track pos.lesson (pos.index + 1))

                    else
                        let
                            updated =
                                { model | recap = True }
                        in
                        ( updated, Cmd.batch [ emit updated, focusElement "lesson-heading" ] )
                )

        Review ->
            withPosition
                (\pos ->
                    let
                        missing =
                            pos.lesson.steps |> List.indexedMap Tuple.pair |> List.filter (\( _, s ) -> not (isCorrect (response model s))) |> List.head |> Maybe.map Tuple.first |> Maybe.withDefault 0
                    in
                    navigate { model | recap = False } (lessonUrl pos.track pos.lesson missing)
                )

        SelectLesson lessonId ->
            withPosition
                (\pos ->
                    pos.track.lessons
                        |> List.filter (\l -> l.id == lessonId)
                        |> List.head
                        |> Maybe.map (\l -> navigate model (lessonUrl pos.track l 0))
                        |> Maybe.withDefault ( model, Cmd.none )
                )

        Agent value ->
            let
                commandDecoder =
                    D.map4 (\request action answer target -> { request = request, action = action, answer = answer, target = target })
                        (D.field "requestId" D.string)
                        (D.field "action" D.string)
                        (D.oneOf [ D.field "answer" D.string, D.succeed "" ])
                        (D.oneOf [ D.field "route" D.string, D.succeed "" ])
            in
            case D.decodeValue commandDecoder value of
                Err _ ->
                    ( model, Cmd.none )

                Ok { request, action, answer, target } ->
                    if action == "answer" then
                        withPosition
                            (\pos ->
                                let
                                    updated =
                                        submit { model | pending = Just request } pos (String.left 500 answer)
                                in
                                ( { updated | pending = Nothing }, Cmd.batch [ emit updated, focusElement "feedback" ] )
                            )

                    else if action == "navigate" then
                        let
                            parts =
                                String.split "/" target |> List.filter (\s -> not (String.isEmpty s) && s /= "#")
                        in
                        case ( Result.toMaybe model.course, parts ) of
                            ( Just course, t :: l :: index :: [] ) ->
                                case ( Course.findLesson course t l, String.toInt index ) of
                                    ( Just ( tr, le ), Just n ) ->
                                        if n >= 1 && n <= List.length le.steps then
                                            navigate { model | pending = Just request } (lessonUrl tr le (n - 1))

                                        else
                                            ( model, reportState (E.object [ ( "requestId", E.string request ), ( "error", E.string "Étape introuvable." ) ]) )

                                    _ ->
                                        ( model, reportState (E.object [ ( "requestId", E.string request ), ( "error", E.string "Leçon introuvable." ) ]) )

                            _ ->
                                ( model, reportState (E.object [ ( "requestId", E.string request ), ( "error", E.string "Parcours introuvable." ) ]) )

                    else
                        ( model, Cmd.none )


emit : Model -> Cmd Msg
emit model =
    let
        request =
            ( "requestId", Maybe.map E.string model.pending |> Maybe.withDefault E.null )

        information =
            case position model of
                Nothing ->
                    [ ( "page", E.string "parcours" ) ]

                Just pos ->
                    let
                        r =
                            response model pos.step
                    in
                    [ ( "page"
                      , E.string
                            (if model.recap then
                                "bilan"

                             else
                                "exercice"
                            )
                      )
                    , ( "trackId", E.string pos.track.id )
                    , ( "lessonId", E.string pos.lesson.id )
                    , ( "step", E.int (pos.index + 1) )
                    , ( "stepCount", E.int (List.length pos.lesson.steps) )
                    , ( "stepId", E.string pos.step.id )
                    , ( "title", E.string pos.step.title )
                    , ( "context", E.string pos.step.context )
                    , ( "question", E.string pos.step.question )
                    , ( "formula", E.string pos.step.formula )
                    , ( "value", E.string r.value )
                    , ( "correct", E.bool (isCorrect r) )
                    , ( "feedback"
                      , E.string
                            (case r.verdict of
                                Just (Ok _) ->
                                    pos.step.success

                                Just (Err e) ->
                                    e

                                Nothing ->
                                    ""
                            )
                      )
                    , ( "kind"
                      , E.string
                            (case pos.step.kind of
                                ChoiceQuestion ->
                                    "choice"

                                Fill ->
                                    "fill"

                                Rewrite ->
                                    "rewrite"
                            )
                      )
                    , ( "choices", E.list (\c -> E.object [ ( "id", E.string c.id ), ( "label", E.string c.label ) ]) pos.step.choices )
                    ]
    in
    reportState (E.object (request :: information))


richInline : String -> List (Html Msg)
richInline source =
    source
        |> String.split "$"
        |> List.indexedMap
            (\i segment ->
                if modBy 2 i == 0 then
                    text segment

                else
                    node "math-tex" [ attribute "formula" segment ] []
            )


rich : String -> Html Msg
rich source =
    span [ class "rich" ] (richInline source)


math : String -> Html Msg
math source =
    node "math-tex" [ attribute "formula" source, attribute "display-mode" "true" ] []


role : String -> Attribute msg
role =
    attribute "role"


icon : String -> Html Msg
icon value =
    span [ class "icon", attribute "aria-hidden" "true" ] [ text value ]


view : Model -> Browser.Document Msg
view model =
    { title = position model |> Maybe.map (\p -> p.lesson.title ++ " · Apprendre à démontrer") |> Maybe.withDefault "Apprendre à démontrer"
    , body =
        [ div [ class "app" ]
            [ a [ class "skip-link", href "#lesson-heading" ] [ text "Aller au contenu" ]
            , header [ class "topbar" ]
                [ a [ class "brand", href "#/parcours", attribute "aria-label" "Apprendre à démontrer — tous les parcours" ]
                    [ span [ class "brand-mark", attribute "aria-hidden" "true" ] [ text "⊢" ], span [] [ text "Apprendre à ", strong [] [ text "démontrer" ] ] ]
                , a [ class "catalog-link", href "#/parcours" ] [ icon "☷", text "Les parcours" ]
                ]
            , case model.course of
                Err _ ->
                    main_ [ class "error-page" ] [ h1 [] [ text "Le parcours n’a pas pu s’ouvrir." ], p [] [ text "Rechargez la page pour réessayer." ] ]

                Ok course ->
                    if route model == [ "parcours" ] then
                        catalog model course

                    else
                        case position model of
                            Nothing ->
                                main_ [ class "error-page" ] [ h1 [] [ text "Cette leçon est introuvable." ], a [ href "#/parcours", class "primary" ] [ text "Voir les parcours" ] ]

                            Just pos ->
                                div [ class "workspace" ]
                                    [ sidebar model course pos
                                    , main_ [ class "lesson" ]
                                        [ if model.recap then
                                            recapView model pos

                                          else
                                            lessonView model pos
                                        , videoView pos.lesson
                                        ]
                                    ]
            , footer [ class "site-footer" ] [ text "Apprendre à démontrer", span [] [ text "Un cours de Jean-Christophe Jameux" ] ]
            ]
        ]
    }


sidebar : Model -> Course -> Position -> Html Msg
sidebar model course pos =
    aside [ class "sidebar", attribute "aria-label" "Navigation dans les parcours" ]
        [ p [ class "sidebar-label" ] [ text "VOTRE PARCOURS" ]
        , nav [ class "track-nav" ]
            (List.map
                (\t ->
                    let
                        url =
                            List.head t.lessons |> Maybe.map (\l -> lessonUrl t l 0) |> Maybe.withDefault "#/parcours"
                    in
                    a
                        [ href url
                        , classList [ ( "track-link", True ), ( "active", t.id == pos.track.id ) ]
                        , attribute "aria-current"
                            (if t.id == pos.track.id then
                                "true"

                             else
                                "false"
                            )
                        ]
                        [ span [ class "track-number" ] [ text t.symbol ]
                        , span [] [ text t.shortTitle ]
                        , if t.id == pos.track.id then
                            icon "·"

                          else
                            text ""
                        ]
                )
                course.tracks
            )
        , div [ class "lesson-nav-heading" ] [ text pos.track.shortTitle, span [] [ text (String.fromInt (List.length pos.track.lessons) ++ " leçons") ] ]
        , nav [ class "lesson-nav", attribute "aria-label" "Leçons" ]
            (List.indexedMap
                (\i l ->
                    let
                        done =
                            completed model l.steps == List.length l.steps
                    in
                    a
                        [ href (lessonUrl pos.track l 0)
                        , classList [ ( "lesson-link", True ), ( "current", l.id == pos.lesson.id ) ]
                        , attribute "aria-current"
                            (if l.id == pos.lesson.id then
                                "page"

                             else
                                "false"
                            )
                        ]
                        [ span [ classList [ ( "lesson-dot", True ), ( "done", done ) ] ]
                            [ text
                                (if done then
                                    "✓"

                                 else
                                    String.fromInt (i + 1)
                                )
                            ]
                        , span [] [ text l.title ]
                        ]
                )
                pos.track.lessons
            )
        , label [ class "mobile-lesson-select" ]
            [ span [] [ text "Leçon" ], select [ value pos.lesson.id, onInput SelectLesson ] (List.indexedMap (\i l -> option [ value l.id ] [ text (String.fromInt (i + 1) ++ " · " ++ l.title) ]) pos.track.lessons) ]
        , div [ class "sidebar-progress" ]
            [ p [] [ text "Étapes vérifiées", strong [] [ text (String.fromInt (completed model (Course.steps course)) ++ " / " ++ String.fromInt (List.length (Course.steps course))) ] ]
            , progress [ Html.Attributes.max (String.fromInt (List.length (Course.steps course))), value (String.fromInt (completed model (Course.steps course))), attribute "aria-label" "Progression dans les trois parcours" ] []
            ]
        ]


lessonView : Model -> Position -> Html Msg
lessonView model pos =
    let
        r =
            response model pos.step
    in
    div [ class "lesson-content" ]
        [ div [ class "lesson-kicker" ] [ span [ class "eyebrow" ] [ text pos.track.title ], span [ class "step-fraction" ] [ text (String.fromInt (pos.index + 1) ++ " / " ++ String.fromInt (List.length pos.lesson.steps)) ] ]
        , h1 [ id "lesson-heading", tabindex -1 ] [ text pos.lesson.title ]
        , p [ class "intro" ] [ text pos.lesson.intro ]
        , nav [ class "stepper", attribute "aria-label" "Étapes de la leçon" ]
            (List.indexedMap
                (\i s ->
                    a
                        [ href (lessonUrl pos.track pos.lesson i)
                        , classList [ ( "step", True ), ( "current", i == pos.index ), ( "complete", isCorrect (response model s) ) ]
                        , attribute "aria-label" ("Étape " ++ String.fromInt (i + 1) ++ " : " ++ s.title)
                        , attribute "aria-current"
                            (if i == pos.index then
                                "step"

                             else
                                "false"
                            )
                        ]
                        [ span []
                            [ text
                                (if isCorrect (response model s) then
                                    "✓"

                                 else
                                    String.fromInt (i + 1)
                                )
                            ]
                        ]
                )
                pos.lesson.steps
            )
        , section [ class "problem-context", attribute "aria-label" "Situation" ]
            [ p [ class "step-title" ] [ text pos.step.title ]
            , p [] [ rich pos.step.context ]
            , if pos.step.scene == "witness" && not r.hint && r.verdict == Nothing then
                text ""

              else
                sceneView pos.step
            , if String.isEmpty pos.step.formula then
                text ""

              else
                div [ class "formula" ] [ math pos.step.formula ]
            ]
        , section [ class "exercise", attribute "aria-labelledby" "question-heading" ]
            [ p [ class "exercise-label" ] [ span [ class "pencil-mark", attribute "aria-hidden" "true" ] [ text "↳" ], text "À VOUS DE JOUER" ]
            , h2 [ id "question-heading" ] (richInline pos.step.question)
            , Html.form [ id "answer-form", onSubmit Verify ]
                [ case pos.step.kind of
                    ChoiceQuestion ->
                        div [ class "choices", role "radiogroup", attribute "aria-labelledby" "question-heading" ] (List.indexedMap (choiceView r) pos.step.choices)

                    _ ->
                        div [ class "input-section" ]
                            [ label [ for "answer-input", class "sr-only" ] [ text "Votre réponse" ]
                            , div [ class "answer-field" ]
                                [ input
                                    [ id "answer-input"
                                    , type_ "text"
                                    , value r.value
                                    , onInput Edit
                                    , maxlength 500
                                    , autocomplete False
                                    , spellcheck False
                                    , attribute "autocapitalize" "off"
                                    , attribute "aria-describedby"
                                        (if pos.step.kind == Rewrite then
                                            "syntax-help"

                                         else
                                            "answer-help"
                                        )
                                    , placeholder
                                        (if pos.step.kind == Rewrite then
                                            "Votre formule…"

                                         else
                                            "Votre réponse…"
                                        )
                                    , classList [ ( "valid", isCorrect r ) ]
                                    ]
                                    []
                                , if isCorrect r then
                                    span [ class "input-check", attribute "aria-hidden" "true" ] [ text "✓" ]

                                  else
                                    text ""
                                ]
                            , if pos.step.kind == Rewrite then
                                div [ class "formula-tools" ]
                                    [ div [ class "symbol-keyboard", attribute "aria-label" "Symboles logiques" ] (List.map (\( labelText, insertion ) -> button [ type_ "button", onClick (AppendSymbol insertion), attribute "aria-label" ("Ajouter " ++ labelText) ] [ text labelText ]) [ ( "¬", "¬" ), ( "∧", " ∧ " ), ( "∨", " ∨ " ), ( "→", " → " ), ( "∀x", "∀x " ), ( "∃x", "∃x " ), ( "(", "(" ), ( ")", ")" ) ])
                                    , p [ id "syntax-help", class "input-help" ] [ text "Vous pouvez aussi écrire : non A, A et B, A ou B, A -> B." ]
                                    ]

                              else
                                p [ id "answer-help", class "input-help" ]
                                    [ text
                                        (if pos.step.rule == "fresh" then
                                            "Saisissez une lettre disponible."

                                         else
                                            "Complétez avec le nombre, la lettre ou l’expression demandée."
                                        )
                                    ]
                            ]
                , div [ class "hint-row" ]
                    [ button
                        [ class "hint-button"
                        , type_ "button"
                        , onClick Hint
                        , attribute "aria-expanded"
                            (if r.hint then
                                "true"

                             else
                                "false"
                            )
                        , attribute "aria-controls" "hint-content"
                        ]
                        [ icon "?"
                        , text
                            (if r.hint then
                                "Masquer l’indice"

                             else
                                "Un indice"
                            )
                        ]
                    ]
                , if r.hint then
                    div [ class "hint-content", id "hint-content" ] [ rich pos.step.hint ]

                  else
                    text ""
                ]
            , feedbackView pos.step r
            ]
        , div [ class "lesson-actions" ]
            [ button [ class "quiet previous", onClick Previous, disabled (pos.index == 0), type_ "button" ] [ icon "←", text "Précédent" ]
            , if isCorrect r then
                button [ class "primary", onClick Next, type_ "button" ]
                    [ text
                        (if pos.index == List.length pos.lesson.steps - 1 then
                            "Faire le point"

                         else
                            "Continuer"
                        )
                    , icon "→"
                    ]

              else
                button [ class "primary", type_ "submit", attribute "form" "answer-form", disabled (String.isEmpty (String.trim r.value)) ] [ text "Vérifier", icon "→" ]
            ]
        ]


choiceView : Response -> Int -> Choice -> Html Msg
choiceView r i choice =
    label
        [ classList
            [ ( "choice", True )
            , ( "selected", r.value == choice.id )
            , ( "correct", r.value == choice.id && isCorrect r )
            , ( "retry"
              , r.value
                    == choice.id
                    && (case r.verdict of
                            Just (Err _) ->
                                True

                            _ ->
                                False
                       )
              )
            ]
        ]
        [ input [ type_ "radio", name "answer", value choice.id, checked (r.value == choice.id), onInput (\_ -> Edit choice.id) ] []
        , span [ class "choice-letter", attribute "aria-hidden" "true" ]
            [ text
                (if r.value == choice.id && isCorrect r then
                    "✓"

                 else
                    String.fromChar (Char.fromCode (65 + i))
                )
            ]
        , span [ class "choice-text" ] (richInline choice.label)
        ]


feedbackView : Step -> Response -> Html Msg
feedbackView step r =
    case r.verdict of
        Nothing ->
            text ""

        Just verdict ->
            div [ id "feedback", tabindex -1, role "status", attribute "aria-live" "polite", classList [ ( "feedback", True ), ( "success", isCorrect r ), ( "try-again", not (isCorrect r) ) ] ]
                [ div [ class "feedback-heading" ]
                    [ icon
                        (if isCorrect r then
                            "✓"

                         else
                            "↺"
                        )
                    , strong []
                        [ text
                            (if isCorrect r then
                                "Oui, c’est cela."

                             else
                                "Reprenons ce point."
                            )
                        ]
                    ]
                , p []
                    [ rich
                        (case verdict of
                            Ok _ ->
                                step.success

                            Err message ->
                                message
                        )
                    ]
                , if isCorrect r then
                    p [ class "takeaway" ] [ rich step.takeaway ]

                  else
                    text ""
                ]


sceneView : Step -> Html Msg
sceneView step =
    case step.scene of
        "witness" ->
            div [ class "witness-scene", attribute "aria-label" "Deux nombres pairs peuvent avoir des moitiés différentes" ]
                [ div [] [ span [ class "scene-label" ] [ text "Un premier entier pair" ], math "a=2", span [ class "scene-detail" ] [ text "sa moitié : 1" ] ]
                , span [ class "scene-separator", attribute "aria-hidden" "true" ] [ text "≠" ]
                , div [] [ span [ class "scene-label" ] [ text "Un second entier pair" ], math "b=4", span [ class "scene-detail" ] [ text "sa moitié : 2" ] ]
                ]

        "forall" ->
            finiteScene True

        "exists" ->
            finiteScene False

        "scope" ->
            scopeScene False

        "scope-closed" ->
            scopeScene True

        "cases" ->
            div [ class "cases-scene", attribute "aria-label" "Les deux branches doivent atteindre la même conclusion C" ]
                [ div [ class "case-branch" ] [ span [] [ text "Si A" ], span [] [ text "↓" ], strong [] [ text "C" ] ]
                , span [ class "case-union" ] [ text "A ∨ B" ]
                , div [ class "case-branch" ] [ span [] [ text "Si B" ], span [] [ text "↓" ], strong [] [ text "C" ] ]
                ]

        _ ->
            text ""


finiteScene : Bool -> Html Msg
finiteScene universal =
    div [ class "finite-scene" ]
        [ div [ class "finite-heading" ]
            [ math
                (if universal then
                    "\\forall x\\in D,\\ x^2=1"

                 else
                    "\\exists x\\in D,\\ x^2=1"
                )
            , span [ classList [ ( "truth-badge", True ), ( "false", universal ) ] ]
                [ text
                    (if universal then
                        "Faux"

                     else
                        "Vrai"
                    )
                ]
            ]
        , div [ class "finite-grid" ]
            (List.intersperse
                (span [ class "finite-connective" ]
                    [ text
                        (if universal then
                            "et"

                         else
                            "ou"
                        )
                    ]
                )
                (List.map
                    (\( n, valid ) ->
                        div [ classList [ ( "finite-element", True ), ( "fails", not valid ) ] ]
                            [ span [] [ text ("x = " ++ n) ]
                            , math
                                (if n == "−1" then
                                    "(-1)^2=1"

                                 else
                                    n ++ "^2="
                                        ++ (if valid then
                                                "1"

                                            else
                                                "0"
                                           )
                                )
                            , span [ class "element-verdict" ]
                                [ text
                                    (if valid then
                                        "vérifie la propriété"

                                     else
                                        "ne la vérifie pas"
                                    )
                                ]
                            ]
                    )
                    [ ( "−1", True ), ( "0", False ), ( "1", True ) ]
                )
            )
        ]


scopeScene : Bool -> Html Msg
scopeScene closed =
    div [ classList [ ( "scope-scene", True ), ( "closed", closed ) ] ]
        [ div [ class "scope-outside" ] [ text "Soit x un réel." ]
        , div [ class "scope-block" ]
            [ span [ class "scope-tag" ]
                [ text
                    (if closed then
                        "HYPOTHÈSE DÉCHARGÉE"

                     else
                        "HYPOTHÈSE OUVERTE"
                    )
                ]
            , p [] [ rich "Supposons $x>2$." ]
            , p [] [ text "⋮" ]
            , p [] [ rich "On obtient $x^2>4$." ]
            ]
        , if closed then
            div [ class "scope-outside conclusion" ] [ rich "Donc $x>2\\Rightarrow x^2>4$." ]

          else
            text ""
        ]


videoView : Lesson -> Html Msg
videoView lesson =
    details [ class "video-section" ]
        [ summary []
            [ span [ class "video-icon", attribute "aria-hidden" "true" ] [ text "▷" ]
            , span [] [ text "La leçon en vidéo" ]
            , span [ class "video-status" ]
                [ text
                    (if lesson.video.provider == "placeholder" then
                        "À venir"

                     else
                        "Regarder"
                    )
                ]
            , icon "+"
            ]
        , div [ class "video-content" ]
            [ if lesson.video.provider == "placeholder" then
                div [ class "video-placeholder" ]
                    [ span [ class "video-proof-mark", attribute "aria-hidden" "true" ] [ text "⊢" ]
                    , strong [] [ text lesson.video.title ]
                    , p [] [ text "La vidéo sera ajoutée ici. Tous les exercices sont déjà disponibles." ]
                    ]

              else
                iframe [ title lesson.video.title, src (videoUrl lesson.video), attribute "loading" "lazy", attribute "allow" "accelerometer; autoplay; encrypted-media; gyroscope; picture-in-picture; fullscreen", attribute "allowfullscreen" "", attribute "referrerpolicy" "strict-origin-when-cross-origin" ] []
            ]
        ]


videoUrl : Course.Video -> String
videoUrl video =
    if video.provider == "youtube" then
        "https://www.youtube-nocookie.com/embed/" ++ video.id

    else
        case String.split "/" video.id of
            clip :: hash :: [] ->
                "https://player.vimeo.com/video/" ++ clip ++ "?h=" ++ hash

            _ ->
                "https://player.vimeo.com/video/" ++ video.id


recapView : Model -> Position -> Html Msg
recapView model pos =
    let
        done =
            completed model pos.lesson.steps

        nextLesson =
            pos.track.lessons |> List.indexedMap Tuple.pair |> List.filter (\( _, l ) -> l.id == pos.lesson.id) |> List.head |> Maybe.andThen (\( i, _ ) -> pos.track.lessons |> List.drop (i + 1) |> List.head)
    in
    section [ class "recap" ]
        [ p [ class "eyebrow" ] [ text pos.track.shortTitle ]
        , div [ class "recap-symbol", attribute "aria-hidden" "true" ] [ text "⊢" ]
        , h1 [ id "lesson-heading", tabindex -1 ] [ text "Ce qu’on vient de construire." ]
        , p [ class "intro" ] [ text (String.fromInt done ++ " étapes vérifiées sur " ++ String.fromInt (List.length pos.lesson.steps) ++ ".") ]
        , ul [ class "takeaways" ]
            (List.map
                (\s ->
                    li []
                        [ span [ classList [ ( "recap-check", True ), ( "pending", not (isCorrect (response model s)) ) ] ]
                            [ text
                                (if isCorrect (response model s) then
                                    "✓"

                                 else
                                    "·"
                                )
                            ]
                        , rich s.takeaway
                        ]
                )
                pos.lesson.steps
            )
        , div [ class "recap-actions" ]
            [ button [ onClick Review, class "secondary" ]
                [ text
                    (if done < List.length pos.lesson.steps then
                        "Reprendre les étapes restantes"

                     else
                        "Revoir la leçon"
                    )
                ]
            , case nextLesson of
                Just l ->
                    a [ href (lessonUrl pos.track l 0), class "primary" ] [ text "Leçon suivante", icon "→" ]

                Nothing ->
                    a [ href "#/parcours", class "primary" ] [ text "Explorer les parcours", icon "→" ]
            ]
        ]


catalog : Model -> Course -> Html Msg
catalog model course =
    main_ [ class "catalog" ]
        [ p [ class "eyebrow" ] [ text "TROIS PORTES D’ENTRÉE" ]
        , h1 [ id "lesson-heading", tabindex -1 ] [ text "Apprendre à démontrer." ]
        , p [ class "intro" ] [ text "Choisissez un parcours. Chacun se construit par des questions, des essais et des raisons de recommencer." ]
        , div [ class "track-catalog" ]
            (List.map
                (\t ->
                    section [ class "catalog-track" ]
                        [ div [ class "catalog-track-heading" ] [ span [ class "catalog-number" ] [ text t.symbol ], span [ class "catalog-progress" ] [ text (String.fromInt (completed model (List.concatMap .steps t.lessons)) ++ " / " ++ String.fromInt (List.length (List.concatMap .steps t.lessons)) ++ " étapes") ] ]
                        , h2 [] [ text t.title ]
                        , p [] [ text t.description ]
                        , ol []
                            (List.map
                                (\l ->
                                    li []
                                        [ a [ href (lessonUrl t l 0) ]
                                            [ span [] [ text l.title ]
                                            , icon
                                                (if completed model l.steps == List.length l.steps then
                                                    "✓"

                                                 else
                                                    "→"
                                                )
                                            ]
                                        ]
                                )
                                t.lessons
                            )
                        ]
                )
                course.tracks
            )
        ]
