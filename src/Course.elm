module Course exposing (Choice, Course, Kind(..), Lesson, Step, Track, Video, decoder, findLesson, steps)

import Json.Decode as D exposing (Decoder)


type Kind
    = ChoiceQuestion
    | Fill
    | Rewrite


type alias Choice =
    { id : String, label : String, feedback : String }


type alias Video =
    { provider : String, id : String, title : String }


type alias Step =
    { id : String
    , title : String
    , kind : Kind
    , context : String
    , question : String
    , answers : List String
    , choices : List Choice
    , formula : String
    , scene : String
    , source : String
    , rule : String
    , hint : String
    , success : String
    , takeaway : String
    }


type alias Lesson =
    { id : String, title : String, intro : String, video : Video, steps : List Step }


type alias Track =
    { id : String, title : String, shortTitle : String, symbol : String, description : String, lessons : List Lesson }


type alias Course =
    { version : Int, tracks : List Track }


required : String -> Decoder a -> Decoder (a -> b) -> Decoder b
required name dec acc =
    D.map2 (|>) (D.field name dec) acc


kindDecoder : Decoder Kind
kindDecoder =
    D.string
        |> D.andThen
            (\s ->
                case s of
                    "choice" ->
                        D.succeed ChoiceQuestion

                    "fill" ->
                        D.succeed Fill

                    "rewrite" ->
                        D.succeed Rewrite

                    _ ->
                        D.fail "Type d’exercice inconnu"
            )


stepDecoder : Decoder Step
stepDecoder =
    D.succeed Step
        |> required "id" D.string
        |> required "title" D.string
        |> required "kind" kindDecoder
        |> required "context" D.string
        |> required "question" D.string
        |> required "answers" (D.list D.string)
        |> required "choices" (D.list (D.map3 Choice (D.field "id" D.string) (D.field "label" D.string) (D.field "feedback" D.string)))
        |> required "formula" D.string
        |> required "scene" D.string
        |> required "source" D.string
        |> required "rule" D.string
        |> required "hint" D.string
        |> required "success" D.string
        |> required "takeaway" D.string


lessonDecoder : Decoder Lesson
lessonDecoder =
    D.map5 Lesson
        (D.field "id" D.string)
        (D.field "title" D.string)
        (D.field "intro" D.string)
        (D.field "video" (D.map3 Video (D.field "provider" D.string) (D.field "id" D.string) (D.field "title" D.string)))
        (D.field "steps" (D.list stepDecoder))


trackDecoder : Decoder Track
trackDecoder =
    D.map6 Track
        (D.field "id" D.string)
        (D.field "title" D.string)
        (D.field "shortTitle" D.string)
        (D.field "symbol" D.string)
        (D.field "description" D.string)
        (D.field "lessons" (D.list lessonDecoder))


decoder : Decoder Course
decoder =
    D.map2 Course (D.field "version" D.int) (D.field "tracks" (D.list trackDecoder))


findLesson : Course -> String -> String -> Maybe ( Track, Lesson )
findLesson course trackId lessonId =
    course.tracks
        |> List.filter (\t -> t.id == trackId)
        |> List.head
        |> Maybe.andThen (\t -> List.filter (\l -> l.id == lessonId) t.lessons |> List.head |> Maybe.map (Tuple.pair t))


steps : Course -> List Step
steps course =
    List.concatMap (\t -> List.concatMap .steps t.lessons) course.tracks
