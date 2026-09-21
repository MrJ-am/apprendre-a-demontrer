port module Main exposing (main)

import Browser
import Browser.Dom
import Browser.Events
import Browser.Navigation as Nav
import Char
import Course exposing (Choice, Course, Kind(..), Lesson, Step, Track)
import Dict exposing (Dict)
import Element as UI exposing (Element)
import Element.Region as Region
import Exercise
import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (onClick, onInput, onSubmit)
import Json.Decode as D
import Json.Encode as E
import MrJam
import Task
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
    , largeur : Int
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
    | Dimensionne Int


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
        , subscriptions = \_ -> Sub.batch [ agentAction Agent, Browser.Events.onResize (\largeur _ -> Dimensionne largeur) ]
        , onUrlRequest = LinkClicked
        , onUrlChange = UrlChanged
        }


init : D.Value -> Url -> Nav.Key -> ( Model, Cmd Msg )
init flags url key =
    let
        model =
            { course = D.decodeValue Course.decoder flags |> Result.mapError D.errorToString, key = key, url = url, responses = Dict.empty, recap = False, pending = Nothing, largeur = 0 }
    in
    ( model, Cmd.batch [ emit model, Task.perform (\dimensions -> Dimensionne (round dimensions.viewport.width)) Browser.Dom.getViewport ] )


route : Model -> List String
route model =
    model.url.fragment |> Maybe.withDefault "" |> String.split "/" |> List.filter (not << String.isEmpty)


isVideoPage : Model -> Bool
isVideoPage model =
    List.isEmpty (route model) || (route model |> List.drop 2 |> List.head) == Just "video"


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
                        route model
                            |> List.drop
                                (if isVideoPage model then
                                    3

                                 else
                                    2
                                )
                            |> List.head
                            |> Maybe.andThen String.toInt
                in
                located
                    |> Maybe.andThen
                        (\( t, l ) ->
                            let
                                index =
                                    clamp 0 (List.length l.steps - 1) (Maybe.map (\n -> n - 1) requested |> Maybe.withDefault (resumeIndex model l))
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


resumeIndex : Model -> Lesson -> Int
resumeIndex model lesson =
    lesson.steps |> List.indexedMap Tuple.pair |> List.filter (\( _, s ) -> not (isCorrect (response model s))) |> List.head |> Maybe.map Tuple.first |> Maybe.withDefault 0


lessonEntryUrl : Track -> Lesson -> String
lessonEntryUrl track lesson =
    "#/" ++ track.id ++ "/" ++ lesson.id ++ "/video"


lessonVideoUrl : Position -> String
lessonVideoUrl pos =
    lessonEntryUrl pos.track pos.lesson ++ "/" ++ String.fromInt (pos.index + 1)


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
        Dimensionne largeur ->
            ( { model | largeur = largeur }, Cmd.none )

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
                            resumeIndex model pos.lesson
                    in
                    navigate { model | recap = False } (lessonUrl pos.track pos.lesson missing)
                )

        SelectLesson lessonId ->
            withPosition
                (\pos ->
                    pos.track.lessons
                        |> List.filter (\l -> l.id == lessonId)
                        |> List.head
                        |> Maybe.map (\l -> navigate model (lessonEntryUrl pos.track l))
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
                        if isVideoPage model || model.recap then
                            ( model, reportState (E.object [ ( "requestId", E.string request ), ( "error", E.string "Ouvrez d’abord un exercice." ) ]) )

                        else
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
                                case
                                    ( Course.findLesson course t l
                                    , if index == "video" then
                                        Just 0

                                      else
                                        String.toInt index
                                    )
                                of
                                    ( Just ( tr, le ), Just n ) ->
                                        if index == "video" then
                                            navigate { model | pending = Just request } (lessonEntryUrl tr le)

                                        else if n >= 1 && n <= List.length le.steps then
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
                    [ ( "trackId", E.string pos.track.id )
                    , ( "lessonId", E.string pos.lesson.id )
                    , ( "step", E.int (pos.index + 1) )
                    , ( "stepCount", E.int (List.length pos.lesson.steps) )
                    ]
                        ++ (if isVideoPage model && not model.recap then
                                [ ( "page", E.string "video" )
                                , ( "title", E.string pos.lesson.video.title )
                                , ( "videoAvailable", E.bool (pos.lesson.video.provider /= "placeholder") )
                                ]

                            else
                                [ ( "page"
                                  , E.string
                                        (if model.recap then
                                            "bilan"

                                         else
                                            "exercice"
                                        )
                                  )
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
                           )
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


{-| Les compositions pédagogiques restent ici. Les contrôles ordinaires
appellent MrJam ; seules les saisies historiques attendent les composants
riches de la bibliothèque, sans changer la révision commune imposée.
-}
view : Model -> Browser.Document Msg
view model =
    { title = position model |> Maybe.map (\p -> p.lesson.title ++ " · Apprendre à démontrer") |> Maybe.withDefault "Apprendre à démontrer"
    , body =
        [ a [ class "skip-link", href "#lesson-heading" ] [ text "Aller au contenu" ]
        , MrJam.page "Apprendre à démontrer"
            [ MrJam.lien "Les parcours" "#/parcours"
            , case model.course of
                Err _ ->
                    repere "lesson-heading" <|
                        MrJam.section "Le parcours n’a pas pu s’ouvrir."
                            [ MrJam.paragraphe "Rechargez la page pour réessayer." ]

                Ok course ->
                    if route model == [ "parcours" ] then
                        catalog model course

                    else
                        case position model of
                            Nothing ->
                                repere "lesson-heading" <|
                                    MrJam.section "Cette leçon est introuvable."
                                        [ MrJam.lien "Voir les parcours" "#/parcours" ]

                            Just pos ->
                                let
                                    contenu =
                                        if model.recap then
                                            recapView model pos

                                        else
                                            lessonView model pos
                                in
                                if model.largeur >= 1000 then
                                    UI.row [ UI.width UI.fill, UI.spacing 24, UI.alignTop ]
                                        [ UI.el [ UI.width (UI.px 260), UI.alignTop ] (sidebar model course pos)
                                        , UI.el [ UI.width (UI.minimum 0 UI.fill), UI.alignTop ] contenu
                                        ]

                                else
                                    MrJam.pile [ sidebar model course pos, contenu ]
            , MrJam.texteSecondaire "Un cours de Jean-Christophe Jameux. Toute utilisation du logo et de la signature est strictement réservée."
            ]
        ]
    }


repere : String -> Element Msg -> Element Msg
repere identifiant =
    UI.el [ UI.width UI.fill, UI.htmlAttribute (id identifiant), UI.htmlAttribute (tabindex -1) ]


texteRiche : String -> Element Msg
texteRiche contenu =
    UI.paragraph [ UI.width UI.fill, UI.spacing 6 ] (List.map UI.html (richInline contenu))


formule : String -> Element Msg
formule contenu =
    UI.el [ UI.width (UI.minimum 0 UI.fill) ] (UI.html (math contenu))


navigation : String -> List (Element Msg) -> Element Msg
navigation libelle contenu =
    UI.el [ UI.width UI.fill, UI.htmlAttribute (role "navigation"), UI.htmlAttribute (attribute "aria-label" libelle) ] (MrJam.actions contenu)


sidebar : Model -> Course -> Position -> Element Msg
sidebar model course pos =
    let
        liensParcours =
            navigation "Parcours" <|
                List.map
                    (\parcours ->
                        MrJam.lien
                            ((if parcours.id == pos.track.id then
                                "▸ "

                              else
                                ""
                             )
                                ++ parcours.shortTitle
                            )
                            (List.head parcours.lessons |> Maybe.map (lessonEntryUrl parcours) |> Maybe.withDefault "#/parcours")
                    )
                    course.tracks

        lecons =
            if model.largeur < 1000 then
                UI.html <|
                    label [ class "selection-historique" ]
                        [ span [] [ text "Leçon" ]
                        , select [ value pos.lesson.id, onInput SelectLesson ]
                            (List.indexedMap (\i lecon -> option [ value lecon.id ] [ text (String.fromInt (i + 1) ++ " · " ++ lecon.title) ]) pos.track.lessons)
                        ]

            else
                UI.el [ UI.width UI.fill, UI.htmlAttribute (role "navigation"), UI.htmlAttribute (attribute "aria-label" "Leçons") ] <|
                    MrJam.pile <|
                        List.indexedMap
                            (\i lecon ->
                                MrJam.lien
                                    ((if lecon.id == pos.lesson.id then
                                        "▸ "

                                      else
                                        ""
                                     )
                                        ++ String.fromInt (i + 1)
                                        ++ " · "
                                        ++ lecon.title
                                        ++ (if completed model lecon.steps == List.length lecon.steps then
                                                " ✓"

                                            else
                                                ""
                                           )
                                    )
                                    (lessonEntryUrl pos.track lecon)
                            )
                            pos.track.lessons
    in
    MrJam.carte
        [ liensParcours
        , lecons
        , MrJam.texteSecondaire (String.fromInt (completed model (Course.steps course)) ++ " / " ++ String.fromInt (List.length (Course.steps course)) ++ " étapes vérifiées")
        ]


lessonView : Model -> Position -> Element Msg
lessonView model pos =
    MrJam.pile
        [ MrJam.texteSecondaire (pos.track.title ++ " · " ++ String.fromInt (completed model pos.lesson.steps) ++ " / " ++ String.fromInt (List.length pos.lesson.steps) ++ " étapes")
        , repere "lesson-heading" (MrJam.sousTitre pos.lesson.title)
        , MrJam.paragraphe pos.lesson.intro
        , navigation "Dans cette leçon"
            [ MrJam.lien
                ((if isVideoPage model then
                    "▸ "

                  else
                    ""
                 )
                    ++ "Comprendre en vidéo"
                )
                (lessonVideoUrl pos)
            , MrJam.lien
                ((if isVideoPage model then
                    ""

                  else
                    "▸ "
                 )
                    ++ "À vous de jouer"
                )
                (lessonUrl pos.track pos.lesson pos.index)
            ]
        , if isVideoPage model then
            videoView model pos

          else
            exerciseView model pos
        ]


exerciseView : Model -> Position -> Element Msg
exerciseView model pos =
    let
        r =
            response model pos.step
    in
    MrJam.pile
        [ navigation "Étapes de la leçon"
            (List.indexedMap
                (\i etape ->
                    MrJam.lien
                        ((if i == pos.index then
                            "▸ "

                          else
                            ""
                         )
                            ++ String.fromInt (i + 1)
                            ++ (if isCorrect (response model etape) then
                                    " ✓"

                                else
                                    ""
                               )
                        )
                        (lessonUrl pos.track pos.lesson i)
                )
                pos.lesson.steps
            )
        , MrJam.carte
            [ MrJam.sousTitre pos.step.title
            , texteRiche pos.step.context
            , if pos.step.scene == "witness" && not r.hint && r.verdict == Nothing then
                UI.none

              else
                sceneView pos.step
            , if String.isEmpty pos.step.formula then
                UI.none

              else
                formule pos.step.formula
            ]
        , MrJam.carte
            [ MrJam.texteSecondaire "À VOUS DE JOUER"
            , UI.paragraph [ UI.width UI.fill, Region.heading 2, UI.htmlAttribute (id "question-heading") ] (List.map UI.html (richInline pos.step.question))
            , UI.el [ UI.width (UI.minimum 0 UI.fill) ] (UI.html (saisieHistorique pos.step r))
            , if pos.step.kind == Rewrite then
                navigation "Symboles logiques"
                    (List.map (\( libelle, insertion ) -> MrJam.boutonSecondaire libelle (AppendSymbol insertion))
                        [ ( "¬", "¬" ), ( "∧", " ∧ " ), ( "∨", " ∨ " ), ( "→", " → " ), ( "∀x", "∀x " ), ( "∃x", "∃x " ), ( "(", "(" ), ( ")", ")" ) ]
                    )

              else
                UI.none
            , if pos.step.kind == ChoiceQuestion then
                UI.none

              else
                UI.el
                    [ UI.width UI.fill
                    , UI.htmlAttribute
                        (id
                            (if pos.step.kind == Rewrite then
                                "syntax-help"

                             else
                                "answer-help"
                            )
                        )
                    ]
                <|
                    MrJam.texteSecondaire
                        (if pos.step.kind == Rewrite then
                            "Vous pouvez aussi écrire : non A, A et B, A ou B, A -> B."

                         else if pos.step.rule == "fresh" then
                            "Saisissez une lettre disponible."

                         else
                            "Complétez avec le nombre, la lettre ou l’expression demandée."
                        )
            , MrJam.boutonSecondaire
                (if r.hint then
                    "Masquer l’indice"

                 else
                    "Un indice"
                )
                Hint
            , if r.hint then
                UI.el [ UI.width UI.fill, UI.htmlAttribute (id "hint-content"), Region.announce ] (texteRiche pos.step.hint)

              else
                UI.none
            , feedbackView pos.step r
            ]
        , MrJam.actions
            [ if pos.index == 0 then
                MrJam.boutonInactif "Précédent"

              else
                MrJam.boutonSecondaire "Précédent" Previous
            , if isCorrect r then
                MrJam.bouton
                    (if pos.index == List.length pos.lesson.steps - 1 then
                        "Faire le point"

                     else
                        "Continuer"
                    )
                    Next

              else if String.isEmpty (String.trim r.value) then
                MrJam.boutonInactif "Vérifier"

              else
                MrJam.bouton "Vérifier" Verify
            ]
        ]


{-| Îlot conservé, non réécrit : libellés KaTeX, radio natif, saisie bornée,
identifiants de focus et soumission Entrée. Il sera remplacé par les composants
communs riches après validation coordonnée de leur nouvelle révision.
-}
saisieHistorique : Step -> Response -> Html Msg
saisieHistorique etape reponse =
    Html.form [ id "answer-form", class "saisies-historiques", onSubmit Verify ]
        [ case etape.kind of
            ChoiceQuestion ->
                div [ class "choices", role "radiogroup", attribute "aria-labelledby" "question-heading" ]
                    (List.indexedMap (choiceView reponse) etape.choices)

            _ ->
                div []
                    [ label [ for "answer-input", class "sr-only" ] [ text "Votre réponse" ]
                    , div [ class "answer-field" ]
                        [ input
                            [ id "answer-input"
                            , type_ "text"
                            , value reponse.value
                            , onInput Edit
                            , maxlength 500
                            , autocomplete False
                            , spellcheck False
                            , attribute "autocapitalize" "off"
                            , attribute "aria-describedby"
                                (if etape.kind == Rewrite then
                                    "syntax-help"

                                 else
                                    "answer-help"
                                )
                            , placeholder
                                (if etape.kind == Rewrite then
                                    "Votre formule…"

                                 else
                                    "Votre réponse…"
                                )
                            , classList [ ( "valid", isCorrect reponse ) ]
                            ]
                            []
                        ]
                    ]
        , button [ type_ "submit", hidden True, tabindex -1 ] [ text "Vérifier" ]
        ]


feedbackView : Step -> Response -> Element Msg
feedbackView step r =
    case r.verdict of
        Nothing ->
            UI.none

        Just verdict ->
            repere "feedback" <|
                UI.el [ UI.width UI.fill, UI.htmlAttribute (role "status"), UI.htmlAttribute (attribute "aria-live" "polite") ] <|
                    MrJam.pile
                        [ MrJam.avis
                            (if isCorrect r then
                                MrJam.Succes

                             else
                                MrJam.Avertissement
                            )
                            (if isCorrect r then
                                "Oui, c’est cela."

                             else
                                "Reprenons ce point."
                            )
                        , texteRiche
                            (case verdict of
                                Ok _ ->
                                    step.success

                                Err message ->
                                    message
                            )
                        , if isCorrect r then
                            texteRiche step.takeaway

                          else
                            UI.none
                        ]


sceneView : Step -> Element Msg
sceneView step =
    case step.scene of
        "witness" ->
            MrJam.pile
                [ MrJam.texteSecondaire "Deux nombres pairs peuvent avoir des moitiés différentes."
                , MrJam.actions
                    [ MrJam.carte [ MrJam.paragraphe "Un premier entier pair", formule "a=2", MrJam.texteSecondaire "sa moitié : 1" ]
                    , MrJam.carte [ MrJam.paragraphe "Un second entier pair", formule "b=4", MrJam.texteSecondaire "sa moitié : 2" ]
                    ]
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
            MrJam.carte
                [ MrJam.paragraphe "Les deux branches doivent atteindre la même conclusion C."
                , formule "A\\lor B"
                , MrJam.actions [ texteRiche "Si $A$ : $C$.", texteRiche "Si $B$ : $C$." ]
                ]

        _ ->
            UI.none


finiteScene : Bool -> Element Msg
finiteScene universal =
    MrJam.pile
        [ formule
            (if universal then
                "\\forall x\\in D,\\ x^2=1"

             else
                "\\exists x\\in D,\\ x^2=1"
            )
        , MrJam.paragraphe
            (if universal then
                "Faux : toutes les propriétés doivent être vérifiées."

             else
                "Vrai : une propriété vérifiée suffit."
            )
        , UI.wrappedRow [ UI.width UI.fill, UI.spacing 12 ]
            (List.intersperse
                (UI.text
                    (if universal then
                        "et"

                     else
                        "ou"
                    )
                )
                (List.map
                    (\( nombre, valide ) ->
                        UI.el [ UI.width (UI.minimum 120 UI.fill) ] <|
                            MrJam.carte
                                [ MrJam.paragraphe ("x = " ++ nombre)
                                , formule
                                    (if nombre == "−1" then
                                        "(-1)^2=1"

                                     else
                                        nombre
                                            ++ "^2="
                                            ++ (if valide then
                                                    "1"

                                                else
                                                    "0"
                                               )
                                    )
                                , MrJam.texteSecondaire
                                    (if valide then
                                        "vérifie la propriété"

                                     else
                                        "ne la vérifie pas"
                                    )
                                ]
                    )
                    [ ( "−1", True ), ( "0", False ), ( "1", True ) ]
                )
            )
        ]


scopeScene : Bool -> Element Msg
scopeScene closed =
    MrJam.pile
        [ MrJam.paragraphe "Soit x un réel."
        , MrJam.carte
            [ MrJam.texteSecondaire
                (if closed then
                    "HYPOTHÈSE DÉCHARGÉE"

                 else
                    "HYPOTHÈSE OUVERTE"
                )
            , texteRiche "Supposons $x>2$."
            , MrJam.paragraphe "⋮"
            , texteRiche "On obtient $x^2>4$."
            ]
        , if closed then
            texteRiche "Donc $x>2\\Rightarrow x^2>4$."

          else
            UI.none
        ]


videoView : Model -> Position -> Element Msg
videoView model pos =
    let
        video =
            pos.lesson.video

        started =
            pos.index > 0 || List.any (\etape -> not (String.isEmpty (response model etape).value)) pos.lesson.steps
    in
    MrJam.carte
        [ MrJam.sousTitre video.title
        , if video.duration > 0 then
            MrJam.texteSecondaire (clock video.duration)

          else
            UI.none
        , if String.isEmpty video.focus then
            UI.none

          else
            texteRiche video.focus
        , if video.provider == "placeholder" then
            MrJam.pile
                [ MrJam.avis MrJam.Information "VIDÉO À VENIR"
                , MrJam.paragraphe "La vidéo de cette leçon arrive bientôt. Vous pouvez déjà explorer les questions."
                ]

          else
            UI.el [ UI.width (UI.minimum 0 UI.fill) ] <|
                UI.html <|
                    div [ class "video-integration" ]
                        [ if video.provider == "vimeo" then
                            node "course-video"
                                [ attribute "video-title" video.title
                                , attribute "src" (videoUrl video)
                                , attribute "poster" video.poster
                                , attribute "start" (String.fromInt video.start)
                                , attribute "watch-url" (videoWatchUrl video)
                                ]
                                []

                          else
                            iframe [ title video.title, src (videoUrl video), attribute "loading" "lazy", attribute "allow" "autoplay; encrypted-media; picture-in-picture; fullscreen", attribute "allowfullscreen" "", attribute "referrerpolicy" "strict-origin-when-cross-origin" ] []
                        ]
        , MrJam.texteSecondaire
            (if video.start > 0 then
                "Passage conseillé à " ++ clock video.start ++ " · La vidéo reste accessible en entier."

             else
                "Une idée à regarder, puis à mettre à l’épreuve."
            )
        , if video.provider == "placeholder" then
            UI.none

          else
            UI.html (a [ href (videoWatchUrl video), target "_blank", rel "noopener noreferrer", class "video-external" ] [ text "Ouvrir la vidéo ↗" ])
        , MrJam.separateur
        , MrJam.texteSecondaire
            (if started then
                "ON REPREND LE FIL"

             else
                "ENSUITE, À VOUS"
            )
        , MrJam.paragraphe pos.step.title
        , MrJam.paragraphe "Une question à la fois. Des indices pour avancer."
        , MrJam.lien
            (if started then
                "Reprendre l’exercice"

             else
                "Commencer les exercices"
            )
            (lessonUrl pos.track pos.lesson pos.index)
        ]


recapView : Model -> Position -> Element Msg
recapView model pos =
    let
        done =
            completed model pos.lesson.steps

        nextLesson =
            pos.track.lessons |> List.indexedMap Tuple.pair |> List.filter (\( _, lecon ) -> lecon.id == pos.lesson.id) |> List.head |> Maybe.andThen (\( i, _ ) -> pos.track.lessons |> List.drop (i + 1) |> List.head)
    in
    MrJam.carte
        [ repere "lesson-heading" (MrJam.sousTitre "Ce qu’on vient de construire.")
        , MrJam.texteSecondaire pos.track.shortTitle
        , MrJam.paragraphe (String.fromInt done ++ " étapes vérifiées sur " ++ String.fromInt (List.length pos.lesson.steps) ++ ".")
        , MrJam.pile
            (List.map
                (\etape ->
                    texteRiche
                        ((if isCorrect (response model etape) then
                            "✓ "

                          else
                            "À reprendre · "
                         )
                            ++ etape.takeaway
                        )
                )
                pos.lesson.steps
            )
        , MrJam.actions
            [ MrJam.boutonSecondaire
                (if done < List.length pos.lesson.steps then
                    "Reprendre les étapes restantes"

                 else
                    "Revoir la leçon"
                )
                Review
            , case nextLesson of
                Just lecon ->
                    MrJam.lien "Leçon suivante" (lessonEntryUrl pos.track lecon)

                Nothing ->
                    MrJam.lien "Explorer les parcours" "#/parcours"
            ]
        ]


catalog : Model -> Course -> Element Msg
catalog model course =
    MrJam.pile
        [ repere "lesson-heading" (MrJam.sousTitre "Trois portes d’entrée")
        , MrJam.paragraphe "Choisissez un parcours. Chacun se construit par des questions, des essais et des raisons de recommencer."
        , MrJam.pile
            (List.map
                (\parcours ->
                    MrJam.section (parcours.symbol ++ " · " ++ parcours.title)
                        [ MrJam.texteSecondaire (String.fromInt (completed model (List.concatMap .steps parcours.lessons)) ++ " / " ++ String.fromInt (List.length (List.concatMap .steps parcours.lessons)) ++ " étapes")
                        , MrJam.paragraphe parcours.description
                        , MrJam.pile
                            (List.map
                                (\lecon ->
                                    MrJam.lien
                                        (lecon.title
                                            ++ (if completed model lecon.steps == List.length lecon.steps then
                                                    " ✓"

                                                else
                                                    ""
                                               )
                                        )
                                        (lessonEntryUrl parcours lecon)
                                )
                                parcours.lessons
                            )
                        ]
                )
                course.tracks
            )
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


clock : Int -> String
clock seconds =
    String.fromInt (seconds // 60) ++ ":" ++ String.padLeft 2 '0' (String.fromInt (modBy 60 seconds))


videoWatchUrl : Course.Video -> String
videoWatchUrl video =
    if not (String.isEmpty video.watchUrl) then
        video.watchUrl

    else if video.provider == "youtube" then
        "https://www.youtube.com/watch?v=" ++ video.id

    else
        "https://vimeo.com/" ++ video.id


videoUrl : Course.Video -> String
videoUrl video =
    if video.provider == "youtube" then
        "https://www.youtube-nocookie.com/embed/" ++ video.id ++ "?start=" ++ String.fromInt video.start

    else
        case String.split "/" video.id of
            clip :: hash :: [] ->
                "https://player.vimeo.com/video/" ++ clip ++ "?h=" ++ hash

            _ ->
                "https://player.vimeo.com/video/" ++ video.id
