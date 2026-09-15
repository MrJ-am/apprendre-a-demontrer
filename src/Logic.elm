module Logic exposing (Formula(..), checkRewrite, isLetter, parse)

import Char
import Dict exposing (Dict)
import Parser as P exposing ((|.), (|=), Parser)
import Set


type Formula
    = Atom String (List String)
    | Not Formula
    | And Formula Formula
    | Or Formula Formula
    | Implies Formula Formula
    | Forall String Formula
    | Exists String Formula


normaliseInput : String -> String
normaliseInput input =
    List.foldl (\( a, b ) s -> String.replace a b s)
        input
        [ ( "\\forall", "∀" )
        , ( "\\exists", "∃" )
        , ( "\\neg", "¬" )
        , ( "\\lnot", "¬" )
        , ( "\\land", "∧" )
        , ( "\\wedge", "∧" )
        , ( "\\lor", "∨" )
        , ( "\\vee", "∨" )
        , ( "\\Rightarrow", "→" )
        , ( "\\rightarrow", "→" )
        , ( "\\implies", "→" )
        , ( "forall ", "∀" )
        , ( "exists ", "∃" )
        , ( "non ", "¬" )
        , ( "not ", "¬" )
        , ( " et ", " ∧ " )
        , ( " and ", " ∧ " )
        , ( " ou ", " ∨ " )
        , ( " or ", " ∨ " )
        , ( "&&", "∧" )
        , ( "||", "∨" )
        , ( "=>", "→" )
        , ( "->", "→" )
        , ( "⇒", "→" )
        , ( "!", "¬" )
        , ( "~", "¬" )
        , ( "&", "∧" )
        , ( "|", "∨" )
        ]


token : String -> Parser ()
token s =
    P.symbol s |. P.spaces


isLetter : Char -> Bool
isLetter char =
    Char.isAlpha char || List.member char (String.toList "ℓαβγδεζηθικλμνξοπρσςτυφχψωΑΒΓΔΕΖΗΘΙΚΛΜΝΞΟΠΡΣΤΥΦΧΨΩ")


identifier : Parser String
identifier =
    P.variable { start = isLetter, inner = \c -> isLetter c || Char.isDigit c || c == '_' || c == '\'', reserved = Set.empty }
        |. P.spaces


expression : Parser Formula
expression =
    disjunction
        |> P.andThen
            (\left ->
                P.oneOf
                    [ P.succeed (Implies left) |. token "→" |= P.lazy (\_ -> expression)
                    , P.succeed left
                    ]
            )


disjunction : Parser Formula
disjunction =
    conjunction |> P.andThen (chain "∨" Or conjunction)


conjunction : Parser Formula
conjunction =
    unary |> P.andThen (chain "∧" And unary)


chain : String -> (Formula -> Formula -> Formula) -> Parser Formula -> Formula -> Parser Formula
chain operator constructor term first =
    P.loop first
        (\left ->
            P.oneOf
                [ P.succeed (\right -> P.Loop (constructor left right)) |. token operator |= term
                , P.succeed (P.Done left)
                ]
        )


quantified : String -> (String -> Formula -> Formula) -> Parser Formula
quantified operator constructor =
    P.succeed constructor
        |. token operator
        |= identifier
        |. P.oneOf [ token ",", token ":", token ".", P.succeed () ]
        |= P.lazy (\_ -> expression)


unary : Parser Formula
unary =
    P.oneOf
        [ P.succeed Not |. token "¬" |= P.lazy (\_ -> unary)
        , quantified "∀" Forall
        , quantified "∃" Exists
        , P.succeed identity |. token "(" |= P.lazy (\_ -> expression) |. token ")"
        , identifier
            |> P.andThen
                (\name ->
                    P.oneOf
                        [ P.map (Atom name) (P.sequence { start = "(", separator = ",", end = ")", spaces = P.spaces, item = identifier, trailing = P.Forbidden }) |. P.spaces
                        , P.succeed (Atom name [])
                        ]
                )
        ]


parse : String -> Result String Formula
parse input =
    if String.length input > 500 then
        Err "La formule est trop longue pour cet exercice."

    else
        P.run (P.succeed identity |. P.spaces |= expression |. P.end) (normaliseInput input)
            |> Result.mapError (\_ -> "Je ne parviens pas à lire cette formule. Utilise les lettres, les connecteurs et des parenthèses. Après ∀x ou ∃x, laisse un espace ; écris les propriétés comme P(x).")


nnf : Bool -> Formula -> Formula
nnf negate formula =
    case formula of
        Atom _ _ ->
            if negate then
                Not formula

            else
                formula

        Not inner ->
            nnf (not negate) inner

        And a b ->
            (if negate then
                Or

             else
                And
            )
                (nnf negate a)
                (nnf negate b)

        Or a b ->
            (if negate then
                And

             else
                Or
            )
                (nnf negate a)
                (nnf negate b)

        Implies a b ->
            nnf negate (Or (Not a) b)

        Forall x inner ->
            (if negate then
                Exists

             else
                Forall
            )
                x
                (nnf negate inner)

        Exists x inner ->
            (if negate then
                Forall

             else
                Exists
            )
                x
                (nnf negate inner)


isNnf : Formula -> Bool
isNnf formula =
    case formula of
        Atom _ _ ->
            True

        Not (Atom _ _) ->
            True

        And a b ->
            isNnf a && isNnf b

        Or a b ->
            isNnf a && isNnf b

        Forall _ body ->
            isNnf body

        Exists _ body ->
            isNnf body

        _ ->
            False


hasImplies : Formula -> Bool
hasImplies formula =
    case formula of
        Implies _ _ ->
            True

        Not a ->
            hasImplies a

        And a b ->
            hasImplies a || hasImplies b

        Or a b ->
            hasImplies a || hasImplies b

        Forall _ body ->
            hasImplies body

        Exists _ body ->
            hasImplies body

        Atom _ _ ->
            False


canonical : Formula -> String
canonical =
    canonicalWithin [] 0


canonicalWithin : List ( String, String ) -> Int -> Formula -> String
canonicalWithin scope depth formula =
    let
        bound name =
            List.filter (\( key, _ ) -> key == name) scope |> List.head |> Maybe.map Tuple.second |> Maybe.withDefault ("free:" ++ name)

        recurse =
            canonicalWithin scope depth

        quantify op x body =
            op ++ canonicalWithin (( x, "bound:" ++ String.fromInt depth ) :: scope) (depth + 1) body

        conjoin op members =
            op ++ "[" ++ String.join ";" (List.sort (List.map recurse members)) ++ "]"
    in
    case formula of
        Atom name args ->
            name ++ "(" ++ String.join "," (List.map bound args) ++ ")"

        Not a ->
            "!" ++ recurse a

        And _ _ ->
            conjoin "and" (andParts formula)

        Or _ _ ->
            conjoin "or" (orParts formula)

        Implies a b ->
            "implies[" ++ recurse a ++ ";" ++ recurse b ++ "]"

        Forall x a ->
            quantify "forall" x a

        Exists x a ->
            quantify "exists" x a


andParts : Formula -> List Formula
andParts f =
    case f of
        And a b ->
            andParts a ++ andParts b

        _ ->
            [ f ]


orParts : Formula -> List Formula
orParts f =
    case f of
        Or a b ->
            orParts a ++ orParts b

        _ ->
            [ f ]


atoms : Formula -> Maybe (List String)
atoms f =
    case f of
        Atom name args ->
            Just
                [ name
                    ++ (if List.isEmpty args then
                            ""

                        else
                            "(" ++ String.join "," args ++ ")"
                       )
                ]

        Not a ->
            atoms a

        And a b ->
            Maybe.map2 (++) (atoms a) (atoms b)

        Or a b ->
            Maybe.map2 (++) (atoms a) (atoms b)

        Implies a b ->
            Maybe.map2 (++) (atoms a) (atoms b)

        _ ->
            Nothing


evaluate : Dict String Bool -> Formula -> Bool
evaluate assignment f =
    case f of
        Atom name args ->
            Dict.get
                (name
                    ++ (if List.isEmpty args then
                            ""

                        else
                            "(" ++ String.join "," args ++ ")"
                       )
                )
                assignment
                |> Maybe.withDefault False

        Not a ->
            not (evaluate assignment a)

        And a b ->
            evaluate assignment a && evaluate assignment b

        Or a b ->
            evaluate assignment a || evaluate assignment b

        Implies a b ->
            not (evaluate assignment a) || evaluate assignment b

        _ ->
            False


assignments : List String -> List (Dict String Bool)
assignments names =
    case names of
        [] ->
            [ Dict.empty ]

        first :: rest ->
            List.concatMap (\a -> [ Dict.insert first True a, Dict.insert first False a ]) (assignments rest)


equivalence : Formula -> Formula -> Result String ()
equivalence a b =
    if canonical (nnf False a) == canonical (nnf False b) then
        Ok ()

    else
        case Maybe.map2 (++) (atoms a) (atoms b) of
            Just names ->
                let
                    unique =
                        Set.toList (Set.fromList names)
                in
                if List.length unique > 8 then
                    Err "Cette formule sort du cadre de l’exercice. Conserve les propositions utilisées dans la question."

                else
                    case assignments unique |> List.filter (\values -> evaluate values a /= evaluate values b) |> List.head of
                        Nothing ->
                            Ok ()

                        Just values ->
                            Err
                                ("Les deux formules ne disent pas la même chose. Essaie avec "
                                    ++ String.join ", "
                                        (List.map
                                            (\( name, value ) ->
                                                name
                                                    ++ (if value then
                                                            " vraie"

                                                        else
                                                            " fausse"
                                                       )
                                            )
                                            (Dict.toList values)
                                        )
                                    ++ " : leurs valeurs de vérité sont différentes."
                                )

            Nothing ->
                Err "La transformation ne conserve pas la structure attendue. Vérifie l’ordre des quantificateurs, les variables et la portée de chaque négation."


checkRewrite : String -> String -> String -> Result String ()
checkRewrite rule expected answer =
    Result.map2 Tuple.pair (parse expected) (parse answer)
        |> Result.andThen
            (\( target, candidate ) ->
                if rule == "structure" then
                    if canonical target == canonical candidate then
                        Ok ()

                    else
                        Err "Quelle est précisément l’hypothèse ouverte, et quelle conclusion as-tu obtenue sous cette hypothèse ?"

                else
                    equivalence target candidate
                        |> Result.andThen
                            (\_ ->
                                if rule == "nnf" && not (isNnf candidate) then
                                    Err "Ta formule est équivalente, mais il reste une négation devant une formule composée, une négation double ou une implication. Fais encore une étape."

                                else if rule == "no-implies" && hasImplies candidate then
                                    Err "Ta formule est équivalente, mais l’implication est encore présente. Remplace-la à l’aide de « ou » et de la négation."

                                else
                                    Ok ()
                            )
            )
