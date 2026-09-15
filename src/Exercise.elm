module Exercise exposing (check)

import Course exposing (Kind(..), Step)
import Logic


normalise : String -> String
normalise =
    String.trim >> String.toLower >> String.replace "−" "-" >> String.replace " " ""


matches : String -> String -> Bool
matches expected actual =
    normalise expected
        == normalise actual
        || (case ( String.toFloat expected, String.toFloat (normalise actual) ) of
                ( Just a, Just b ) ->
                    a == b

                _ ->
                    False
           )


check : Step -> String -> Result String ()
check step answer =
    if String.isEmpty (String.trim answer) then
        Err "Ajoute une réponse avant de la vérifier."

    else
        case step.kind of
            ChoiceQuestion ->
                if List.member answer step.answers then
                    Ok ()

                else
                    step.choices
                        |> List.filter (\c -> c.id == answer)
                        |> List.head
                        |> Maybe.map
                            (\c ->
                                Err
                                    (if String.isEmpty c.feedback then
                                        "Reprends la question avec l’indice proposé."

                                     else
                                        c.feedback
                                    )
                            )
                        |> Maybe.withDefault (Err "Choisis l’une des réponses proposées.")

            Fill ->
                if step.rule == "fresh" then
                    case String.toList (String.trim answer) of
                        [ letter ] ->
                            if not (Logic.isLetter letter) then
                                Err "Choisis une lettre pour nommer cet entier."

                            else if List.member (String.fromChar letter) [ "a", "b", "k" ] then
                                Err "Ce nom est déjà utilisé. Il ferait désigner au même nom deux objets qui ne sont pas nécessairement égaux."

                            else
                                Ok ()

                        _ ->
                            Err "Une seule lettre disponible suffit ici."

                else if List.any (\a -> matches a answer) step.answers then
                    Ok ()

                else
                    Err "Ce choix ne convient pas encore. Remplace le blanc par ta réponse et vérifie ce que devient l’affirmation."

            Rewrite ->
                Logic.checkRewrite step.rule (List.head step.answers |> Maybe.withDefault "") answer
