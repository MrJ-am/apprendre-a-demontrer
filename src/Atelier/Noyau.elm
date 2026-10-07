module Atelier.Noyau exposing (ajouterHypotheses, contexteCible, contexteInitial, controlerIdentites, verifier, verifierBibliotheque, verifierBloc, verifierDefinition, verifierSequence)

{-| Noyau pur de déduction naturelle. La disponibilité est une relation de portée
et d'ordre, jamais une coordonnée graphique. Chaque branche reçoit une copie du
contexte extérieur ; seules ses propres hypothèses sont ajoutées. Les sorties
certifiées transportent les dépendances effectivement utilisées et la provenance
classique transitive. Les règles dérivées sont revérifiées depuis leur certificat.
-}

import Atelier.Formule as F exposing (Formule(..))
import Atelier.Graphe as G
import Atelier.Regles as R
import Atelier.Types exposing (..)
import Dict exposing (Dict)
import Set exposing (Set)


contexteInitial : List Hypothese -> Contexte
contexteInitial =
    List.foldl (\h -> Dict.insert h.id { conclusion = h.formule, libres = Dict.singleton h.id h.formule, classique = False }) Dict.empty


ajouterHypotheses : List Hypothese -> Contexte -> Contexte
ajouterHypotheses hs contexte =
    Dict.union (contexteInitial hs) contexte


traverser : (a -> Result Probleme b) -> List a -> Result Probleme (List b)
traverser fn =
    List.foldr (\x acc -> Result.map2 (::) (fn x) acc) (Ok [])


exiger : Bool -> String -> Result Probleme ()
exiger condition message =
    if condition then
        Ok ()

    else
        Err (Erreur message)


attendre : Formule -> Verdict -> Result Probleme Verdict
attendre objectif verdict =
    if not (F.complete objectif) then
        Err (Incomplet "Une proposition reste à compléter.")

    else if F.egales objectif verdict.conclusion then
        Ok { verdict | conclusion = objectif }

    else
        Err (Erreur ("Cet emplacement attend une preuve de " ++ F.afficher objectif ++ ", et ce bloc démontre " ++ F.afficher verdict.conclusion ++ "."))


controlerIdentites : Bibliotheque -> List Hypothese -> List Preuve -> Result Probleme ()
controlerIdentites bibliotheque hypotheses preuves =
    let
        ns =
            G.noeuds preuves

        ids =
            List.map .id hypotheses ++ List.concatMap (\b -> b.id :: (R.contrat bibliotheque b |> Result.map (.entrees >> List.concatMap .hypotheses >> List.map .id) |> Result.withDefault [])) ns
    in
    exiger (List.length ns <= 1500 && List.length ids == Set.size (Set.fromList ids) && List.all (\s -> not (String.isEmpty s) && String.length s < 600 && not (String.contains "|" s)) ids)
        "Identités dupliquées, invalides ou preuve trop volumineuse. Les lieurs doivent rester distincts."


verifier : Bibliotheque -> List Hypothese -> Formule -> List Preuve -> Result Probleme Verdict
verifier bibliotheque hypotheses objectif preuves =
    controlerIdentites bibliotheque hypotheses preuves
        |> Result.andThen
            (\_ ->
                if List.all (.formule >> F.complete) hypotheses then
                    Ok ()

                else
                    Err (Incomplet "Une prémisse reste à compléter.")
            )
        |> Result.andThen (\_ -> verifierSequence bibliotheque (contexteInitial hypotheses) preuves)
        |> Result.andThen (attendre objectif)


verifierSequence : Bibliotheque -> Contexte -> List Preuve -> Result Probleme Verdict
verifierSequence bibliotheque =
    sequenceAvec Set.empty [] bibliotheque


verifierBloc : Bibliotheque -> Contexte -> Preuve -> Result Probleme Verdict
verifierBloc bibliotheque =
    blocAvec Set.empty [] bibliotheque


sequenceAvec : Set String -> List Port -> Bibliotheque -> Contexte -> List Preuve -> Result Probleme Verdict
sequenceAvec pile ports bibliotheque contexte preuves =
    case preuves of
        [] ->
            Err (Incomplet "Il reste une preuve à construire dans cette cavité.")

        preuve :: suite ->
            blocAvec pile ports bibliotheque contexte preuve
                |> Result.andThen
                    (\v ->
                        if List.isEmpty suite then
                            Ok v

                        else
                            sequenceAvec pile ports bibliotheque (Dict.insert (identifiant preuve) v contexte) suite
                                |> Result.map (\fin -> { fin | classique = fin.classique || v.classique })
                    )


blocAvec : Set String -> List Port -> Bibliotheque -> Contexte -> Preuve -> Result Probleme Verdict
blocAvec pile ports bibliotheque contexte (Bloc b) =
    case b.regle of
        Reference ref ->
            if not (List.isEmpty b.entrees) then
                Err (Erreur "Une référence ne contient pas de sous-preuve.")

            else
                Dict.get ref contexte
                    |> Maybe.map (\v -> R.contrat bibliotheque b |> Result.andThen (\c -> attendre c.conclusion v))
                    |> Maybe.withDefault (Err (Erreur ("Ce fait n’est pas disponible ici (" ++ ref ++ "). Il appartient peut-être à une autre branche, ou dépend d’une étape ultérieure.")))

        Argument index ->
            case List.drop index ports |> List.head of
                Nothing ->
                    Err (Erreur "Entrée formelle absente ou utilisée hors d’un certificat.")

                Just entree ->
                    if index < 0 || not (List.isEmpty b.entrees) then
                        Err (Erreur "Argument formel mal formé.")

                    else
                        traverser (\h -> Dict.get h.id contexte |> Maybe.map (attendre h.formule) |> Maybe.withDefault (Err (Erreur "L’argument hypothétique est utilisé hors de son contexte."))) entree.hypotheses
                            |> Result.map (\_ -> { conclusion = entree.conclusion, libres = Dict.insert ("@entree:" ++ String.fromInt index) entree.conclusion (List.map (\h -> ( h.id, h.formule )) entree.hypotheses |> Dict.fromList), classique = False })

        _ ->
            let
                certifie =
                    case b.regle of
                        Application id version ->
                            trouverDefinition bibliotheque id version
                                |> Maybe.map
                                    (\d ->
                                        exiger (Dict.keys b.parametres |> Set.fromList |> (==) (Set.fromList d.parametres)) "L’instanciation doit fournir exactement les paramètres du théorème."
                                            |> Result.andThen (\_ -> definitionAvec pile bibliotheque d)
                                            |> Result.map .classique
                                    )
                                |> Maybe.withDefault (Err (Erreur "Dépendance de théorème manquante."))

                        Primitive "RA" ->
                            Ok True

                        _ ->
                            Ok False
            in
            certifie
                |> Result.andThen
                    (\classique ->
                        R.contrat bibliotheque b
                            |> Result.andThen
                                (\c ->
                                    if not (F.complete c.conclusion && List.all (\e -> F.complete e.conclusion && List.all (.formule >> F.complete) e.hypotheses) c.entrees) then
                                        Err (Incomplet "Il reste une proposition à compléter dans le contrat.")

                                    else if List.length c.entrees /= List.length b.entrees then
                                        Err (Erreur "Le nombre de cavités ne correspond pas au contrat de la règle.")

                                    else
                                        List.map2
                                            (\e ps ->
                                                sequenceAvec pile ports bibliotheque (ajouterHypotheses e.hypotheses contexte) ps
                                                    |> Result.andThen (attendre e.conclusion)
                                                    |> Result.map (\v -> { v | libres = List.foldl (\h -> Dict.remove h.id) v.libres e.hypotheses })
                                            )
                                            c.entrees
                                            b.entrees
                                            |> traverser identity
                                            |> Result.map (\vs -> { conclusion = c.conclusion, libres = List.foldl (\v -> Dict.union v.libres) Dict.empty vs, classique = classique || List.any .classique vs })
                                )
                    )


verifierDefinition : Bibliotheque -> Definition -> Result Probleme Verdict
verifierDefinition =
    definitionAvec Set.empty


definitionAvec : Set String -> Bibliotheque -> Definition -> Result Probleme Verdict
definitionAvec pile bibliotheque def =
    let
        identite =
            cle def.id def.version

        toutesFormules =
            def.conclusion :: G.formules def.certificat ++ List.concatMap (\e -> e.conclusion :: List.map .formule e.hypotheses) def.entrees

        paramsUtilises =
            List.foldl (F.parametres >> Set.union) Set.empty toutesFormules

        hypPorts =
            List.concatMap .hypotheses def.entrees

        hypCert =
            G.noeuds def.certificat |> List.concatMap (\b -> R.contrat bibliotheque b |> Result.map (.entrees >> List.concatMap .hypotheses) |> Result.withDefault [])
    in
    if Set.member identite pile || Set.size pile > 40 then
        Err (Erreur "Cycle de dépendances entre théorèmes, ou profondeur excessive.")

    else
        exiger (def.version > 0 && not (String.isEmpty def.id) && List.length def.parametres == Set.size (Set.fromList def.parametres)) "Identité, version ou paramètres de définition invalides."
            |> Result.andThen (\_ -> exiger (List.all F.complete toutesFormules && Set.isEmpty (Set.diff paramsUtilises (Set.fromList def.parametres))) "Certificat incomplet ou paramètre non déclaré.")
            |> Result.andThen (\_ -> exiger (Set.fromList def.dependances == Set.fromList (G.dependances def.certificat)) "Les dépendances versionnées ne correspondent pas au certificat.")
            |> Result.andThen (\_ -> exiger (List.all (\h -> List.any (\k -> h.id == k.id && F.egales h.formule k.formule) hypCert) hypPorts) "Un port hypothétique ne correspond à aucun lieur du certificat.")
            |> Result.andThen (\_ -> controlerIdentites bibliotheque [] def.certificat)
            |> Result.andThen (\_ -> sequenceAvec (Set.insert identite pile) def.entrees bibliotheque Dict.empty def.certificat)
            |> Result.andThen (attendre def.conclusion)
            |> Result.andThen (\v -> exiger (Set.fromList (Dict.keys v.libres) == Set.fromList (List.indexedMap (\i _ -> "@entree:" ++ String.fromInt i) def.entrees)) "Le certificat capture une hypothèse extérieure ou déclare une entrée qui ne contribue pas à sa conclusion." |> Result.map (\_ -> v))


verifierBibliotheque : Bibliotheque -> Result Probleme ()
verifierBibliotheque bibliotheque =
    exiger (List.length bibliotheque <= 100 && Set.size (Set.fromList (List.map (\d -> cle d.id d.version) bibliotheque)) == List.length bibliotheque) "Bibliothèque trop grande ou identités de versions dupliquées."
        |> Result.andThen (\_ -> traverser (verifierDefinition bibliotheque) bibliotheque)
        |> Result.map (\_ -> ())


{-| Contexte inspectable d'un point d'insertion. Un résultat incomplet n'entre
jamais dans les faits disponibles ; les étapes suivantes restent visibles.
-}
contexteCible : Bibliotheque -> List Hypothese -> List Preuve -> G.Cible -> Maybe ( Contexte, Formule )
contexteCible bibliotheque hypotheses preuves cible =
    let
        parcourir parent indice attendu contexte suite =
            if cible.parent == parent && cible.indice == indice then
                Just ( List.take cible.position suite |> List.foldl (\p ctx -> verifierBloc bibliotheque ctx p |> Result.map (\v -> Dict.insert (identifiant p) v ctx) |> Result.withDefault ctx) contexte, attendu )

            else
                chercher contexte suite

        chercher contexte suite =
            case suite of
                [] ->
                    Nothing

                (Bloc b) :: suivants ->
                    let
                        dedans =
                            R.contrat bibliotheque b
                                |> Result.toMaybe
                                |> Maybe.andThen
                                    (\c ->
                                        List.map2 (\( i, e ) ps -> parcourir b.id i e.conclusion (ajouterHypotheses e.hypotheses contexte) ps) (List.indexedMap Tuple.pair c.entrees) b.entrees |> List.filterMap identity |> List.head
                                    )

                        suivant =
                            verifierBloc bibliotheque contexte (Bloc b) |> Result.map (\v -> Dict.insert b.id v contexte) |> Result.withDefault contexte
                    in
                    case dedans of
                        Just trouve ->
                            Just trouve

                        Nothing ->
                            chercher suivant suivants
    in
    parcourir "racine" 0 (Trou "objectif") (contexteInitial hypotheses) preuves
