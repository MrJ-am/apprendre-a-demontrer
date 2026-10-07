module Atelier.Editeur exposing (..)

import Atelier.Exemples as Ex
import Atelier.Formule as F exposing (Formule(..))
import Atelier.Graphe as G
import Atelier.Noyau as N
import Atelier.Regles as R
import Atelier.Sauvegarde as S
import Atelier.Theoremes as T
import Atelier.Types exposing (..)
import Dict exposing (Dict)
import Json.Decode as D
import Set exposing (Set)


type Source
    = Nouvelle Regle
    | Fait String Formule
    | Deplacement String
    | Proposition Formule


type alias Extraction =
    { nom : String, atomes : Set String, generalises : Set String, versionDe : Maybe String, sequence : Bool }


type alias Modele =
    { document : Document
    , passes : List Document
    , futurs : List Document
    , selection : Maybe String
    , cible : G.Cible
    , source : Maybe String
    , repli : Set String
    , panneau : String
    , message : String
    , exemple : String
    , cibleFormule : Maybe String
    , brouillon : Formule
    , chemin : List Int
    , texteFormule : String
    , nomAtome : String
    , extraction : Maybe Extraction
    , inspection : Maybe Preuve
    , stockageBloque : Bool
    , zoom : Int
    }


type Message
    = Choisir String
    | Placer String
    | Deposer String String
    | Selectionner String
    | ChoisirCavite G.Cible
    | Panneau String
    | Exemple String
    | Charger Bool
    | Annuler
    | Retablir
    | Supprimer
    | Dupliquer
    | Replier
    | PreparerExtraction
    | NomTheoreme String
    | Generaliser String Bool
    | EtendueExtraction Bool
    | VersionDe String
    | EnregistrerTheoreme
    | FermerExtraction
    | Inspecter
    | Developper
    | FermerInspection
    | EditerFormule String
    | TexteFormule String
    | AnalyserFormule
    | Connecteur String
    | NomAtome String
    | InsererAtome
    | CheminFormule (List Int)
    | AppliquerFormule
    | FermerFormule
    | AjouterPremisse
    | RetirerPremisse String
    | Restaurer String
    | ImportRecu String
    | StockageErreur String
    | ReprendreStockage
    | Evenement D.Value
    | Exporter
    | Importer
    | AnnulerGeste
    | AucuneAction
    | Zoomer Int
    | Recentrer


initial : Modele
initial =
    { document = Ex.vide, passes = [], futurs = [], selection = Nothing, cible = { parent = "racine", indice = 0, position = 0 }, source = Nothing, repli = Set.empty, panneau = "construire", message = "Glissez une règle jaune dans l’atelier. Les propositions vertes s’emboîtent dans ses paramètres.", exemple = "vide", cibleFormule = Nothing, brouillon = Atome "A", chemin = [], texteFormule = "A", nomAtome = "A", extraction = Nothing, inspection = Nothing, stockageBloque = False, zoom = 100 }


modifier : Document -> Modele -> Modele
modifier doc modele =
    if doc == modele.document then
        modele

    else
        { modele | document = doc, passes = List.take 80 (modele.document :: modele.passes), futurs = [] }


nouvelId : Document -> String
nouvelId doc =
    let
        tous =
            List.map .id (G.noeuds doc.preuves) ++ List.map .id doc.premisses ++ List.map .id doc.bibliotheque

        chercher n =
            if List.any (\id -> id == "n" ++ String.fromInt n || id == "theoreme-n" ++ String.fromInt n || String.startsWith ("n" ++ String.fromInt n ++ "/") id) tous then
                chercher (n + 1)

            else
                "n" ++ String.fromInt n
    in
    chercher doc.prochain


contexte : Modele -> G.Cible -> Maybe ( Contexte, Formule )
contexte m cible =
    N.contexteCible m.document.bibliotheque m.document.premisses m.document.preuves cible
        |> Maybe.map
            (\( ctx, f ) ->
                ( ctx
                , if cible.parent == "racine" then
                    m.document.objectif

                  else
                    f
                )
            )


selectionnee : Modele -> Maybe ( DonneesBloc, Contexte )
selectionnee m =
    m.selection
        |> Maybe.andThen
            (\id ->
                Maybe.map2 (\b ( ctx, _ ) -> ( b, ctx )) (G.trouver id m.document.preuves) (G.position id m.document.preuves |> Maybe.andThen (contexte m))
            )


formuleCible : Modele -> String -> Maybe Formule
formuleCible m cible =
    case String.split "|" cible of
        [ base, chemin ] ->
            formuleCible m base |> Maybe.andThen (sousFormule (lireChemin chemin))

        _ ->
            formuleSimple m cible


lireChemin : String -> List Int
lireChemin =
    String.split "." >> List.filterMap String.toInt


sousFormule : List Int -> Formule -> Maybe Formule
sousFormule chemin formule =
    case chemin of
        [] ->
            Just formule

        indice :: suite ->
            let
                enfants =
                    case formule of
                        Et a b ->
                            [ a, b ]

                        Ou a b ->
                            [ a, b ]

                        Implique a b ->
                            [ a, b ]

                        Equivalent a b ->
                            [ a, b ]

                        Non a ->
                            [ a ]

                        _ ->
                            []
            in
            List.drop indice enfants |> List.head |> Maybe.andThen (sousFormule suite)


formuleSimple : Modele -> String -> Maybe Formule
formuleSimple m cible =
    case String.split ":" cible of
        [ "objectif" ] ->
            Just m.document.objectif

        [ "brouillon" ] ->
            Just m.brouillon

        [ "premisse", id ] ->
            List.filter (.id >> (==) id) m.document.premisses |> List.head |> Maybe.map .formule

        [ "param", id, p ] ->
            G.trouver id m.document.preuves |> Maybe.andThen (.parametres >> Dict.get p)

        _ ->
            Nothing


lireSource : Modele -> String -> Maybe Source
lireSource m source =
    if String.startsWith "prop:" source then
        formuleCible m (String.dropLeft 5 source) |> Maybe.map Proposition

    else
        case String.split ":" source of
            [ "regle", r ] ->
                Just (Nouvelle (Primitive r))

            [ "theoreme", id, v ] ->
                String.toInt v |> Maybe.map (Application id >> Nouvelle)

            [ "bloc", id ] ->
                Just (Deplacement id)

            [ "fait", id ] ->
                contexte m m.cible |> Maybe.andThen (Tuple.first >> Dict.get id) |> Maybe.map (\v -> Fait id v.conclusion)

            [ "atome", a ] ->
                F.lire a |> Result.toMaybe |> Maybe.map Proposition

            [ "connecteur", r ] ->
                Just (Proposition (connecteur r))

            _ ->
                Nothing


connecteur : String -> Formule
connecteur r =
    case r of
        "et" ->
            Et (Trou "gauche") (Trou "droite")

        "ou" ->
            Ou (Trou "gauche") (Trou "droite")

        "implique" ->
            Implique (Trou "gauche") (Trou "droite")

        "non" ->
            Non (Trou "corps")

        "equivalent" ->
            Equivalent (Trou "gauche") (Trou "droite")

        _ ->
            Faux


{-| L'inférence ajuste seulement des paramètres syntaxiques. Elle ne fournit
aucune preuve et n'assimile jamais deux connecteurs par équivalence sémantique.
-}
inferer : Formule -> Formule -> Dict String Formule -> Maybe (Dict String Formule)
inferer schema objectif substitutions =
    let
        deux a b x y =
            inferer a x substitutions |> Maybe.andThen (inferer b y)
    in
    case ( schema, objectif ) of
        ( Parametre p, _ ) ->
            case Dict.get p substitutions of
                Nothing ->
                    Just (Dict.insert p objectif substitutions)

                Just valeur ->
                    if F.egales valeur objectif then
                        Just substitutions

                    else
                        Nothing

        ( Et a b, Et x y ) ->
            deux a b x y

        ( Ou a b, Ou x y ) ->
            deux a b x y

        ( Implique a b, Implique x y ) ->
            deux a b x y

        ( Non a, Non x ) ->
            inferer a x substitutions

        ( Equivalent a b, Equivalent x y ) ->
            deux a b x y

        _ ->
            if F.egales schema objectif then
                Just substitutions

            else
                Nothing


poser : String -> String -> Modele -> Modele
poser source cible m =
    let
        refus s =
            { m | message = s, source = Nothing }

        doc =
            m.document
    in
    case lireSource m source of
        Nothing ->
            refus "Cet objet n’est plus disponible dans le contexte sélectionné."

        Just (Proposition formule) ->
            if String.startsWith "formule:" cible then
                let
                    destination =
                        String.dropLeft 8 cible
                in
                if String.startsWith "trou:" destination then
                    let
                        chemin =
                            String.dropLeft 5 destination |> String.split "." |> List.filterMap String.toInt

                        nouveau =
                            F.remplacer chemin formule m.brouillon
                    in
                    { m | brouillon = nouveau, texteFormule = F.afficher nouveau, source = Nothing, chemin = chemin, message = "Proposition composée. Cela ne constitue pas une preuve." }

                else
                    appliquer destination formule m

            else
                refus "Une proposition remplit un emplacement de formule ; elle ne démontre pas l’objectif."

        Just objet ->
            if String.startsWith "preuve:" cible then
                case G.lireCible (String.dropLeft 7 cible) of
                    Nothing ->
                        refus "Emplacement de preuve introuvable."

                    Just destination ->
                        case contexte m destination of
                            Nothing ->
                                refus "Ce contexte n’existe plus."

                            Just ( ctx, objectif ) ->
                                let
                                    id =
                                        nouvelId doc

                                    construction =
                                        case objet of
                                            Fait ref f ->
                                                Just (Ex.fait id ref f)

                                            Deplacement ancien ->
                                                G.trouver ancien doc.preuves |> Maybe.map Bloc

                                            Nouvelle r ->
                                                let
                                                    noms =
                                                        R.parametres doc.bibliotheque r

                                                    schema =
                                                        R.creer doc.bibliotheque id r (List.map (\p -> ( p, Parametre p )) noms |> Dict.fromList)

                                                    attendue =
                                                        case schema of
                                                            Bloc n ->
                                                                R.contrat doc.bibliotheque n |> Result.map .conclusion |> Result.withDefault (Trou "sortie")

                                                    inferees =
                                                        inferer attendue objectif Dict.empty |> Maybe.withDefault Dict.empty

                                                    valeurs =
                                                        List.map (\p -> ( p, Dict.get p inferees |> Maybe.withDefault (Atome p) )) noms |> Dict.fromList
                                                in
                                                Just (R.creer doc.bibliotheque id r valeurs)

                                            Proposition _ ->
                                                Nothing

                                    depart =
                                        case objet of
                                            Deplacement ancien ->
                                                G.position ancien doc.preuves

                                            _ ->
                                                Nothing

                                    ajuste =
                                        case depart of
                                            Just origine ->
                                                if origine.parent == destination.parent && origine.indice == destination.indice && origine.position < destination.position then
                                                    { destination | position = destination.position - 1 }

                                                else
                                                    destination

                                            Nothing ->
                                                destination

                                    sans =
                                        case objet of
                                            Deplacement ancien ->
                                                G.retirer ancien doc.preuves

                                            _ ->
                                                doc.preuves

                                    cycle preuve =
                                        G.trouver destination.parent [ preuve ] /= Nothing
                                in
                                case construction of
                                    Nothing ->
                                        refus "Construction absente."

                                    Just preuve ->
                                        if cycle preuve then
                                            refus "Un bloc ne peut pas être placé dans sa propre cavité."

                                        else
                                            case N.verifierBloc doc.bibliotheque ctx preuve of
                                                Err (Erreur message) ->
                                                    refus message

                                                _ ->
                                                    case G.inserer ajuste preuve sans of
                                                        Err message ->
                                                            refus message

                                                        Ok ps ->
                                                            modifier { doc | preuves = ps, prochain = doc.prochain + 1 } m
                                                                |> (\nouveau -> { nouveau | source = Nothing, selection = Just (identifiant preuve), cible = { ajuste | position = ajuste.position + 1 }, message = "Bloc placé. La dernière étape est la conclusion de cette cavité." })

            else
                refus "Cet emplacement attend une proposition, pas une preuve."


appliquer : String -> Formule -> Modele -> Modele
appliquer cible formule m =
    case String.split "|" cible of
        [ base, chemin ] ->
            formuleCible m base
                |> Maybe.map (\origine -> appliquerSimple base (F.remplacer (lireChemin chemin) formule origine) m)
                |> Maybe.withDefault { m | message = "Emplacement de proposition introuvable." }

        _ ->
            appliquerSimple cible formule m


appliquerSimple : String -> Formule -> Modele -> Modele
appliquerSimple cible formule m =
    let
        doc =
            m.document

        change d =
            modifier d m |> (\n -> { n | cibleFormule = Nothing, source = Nothing, message = "Formule modifiée ; toutes les dépendances sont revérifiées." })
    in
    case String.split ":" cible of
        [ "objectif" ] ->
            change { doc | objectif = formule }

        [ "premisse", id ] ->
            change
                { doc
                    | premisses =
                        List.map
                            (\h ->
                                if h.id == id then
                                    { h | formule = formule }

                                else
                                    h
                            )
                            doc.premisses
                }

        [ "param", id, p ] ->
            change
                { doc
                    | preuves =
                        G.transformer
                            (\b ->
                                if b.id == id then
                                    { b | parametres = Dict.insert p formule b.parametres }

                                else
                                    b
                            )
                            doc.preuves
                }

        [ "brouillon" ] ->
            { m | brouillon = formule, texteFormule = F.afficher formule, source = Nothing }

        _ ->
            { m | message = "Emplacement de formule introuvable." }


preparerExtraction : Modele -> Modele
preparerExtraction m =
    case selectionnee m of
        Nothing ->
            { m | message = "Sélectionnez la conclusion d’une construction complète." }

        Just ( b, ctx ) ->
            case N.verifierBloc m.document.bibliotheque ctx (Bloc b) of
                Err p ->
                    { m | message = messageProbleme p }

                Ok v ->
                    let
                        atomes =
                            v.conclusion :: G.formules [ Bloc b ] |> List.foldl (F.atomes >> Set.union) Set.empty
                    in
                    { m | extraction = Just { nom = "Mon théorème", atomes = atomes, generalises = atomes, versionDe = Nothing, sequence = False }, panneau = "inspecter", message = "Vérifiez les paramètres et les entrées nécessaires avant d’enregistrer." }


propositionExtraction : Modele -> Result Probleme Definition
propositionExtraction m =
    case ( m.extraction, selectionnee m ) of
        ( Just e, Just ( b, ctx ) ) ->
            let
                identite =
                    Maybe.withDefault ("theoreme-" ++ nouvelId m.document) e.versionDe

                version =
                    m.document.bibliotheque |> List.filter (.id >> (==) identite) |> List.map .version |> List.maximum |> Maybe.withDefault 0 |> (+) 1
            in
            if e.sequence then
                case G.position b.id m.document.preuves of
                    Nothing ->
                        Err (Erreur "Séquence introuvable.")

                    Just position ->
                        let
                            selection =
                                G.sequence position m.document.preuves |> Maybe.withDefault [] |> List.take (position.position + 1)

                            initialContexte =
                                contexte m { position | position = 0 } |> Maybe.map Tuple.first |> Maybe.withDefault ctx
                        in
                        T.extraire m.document.bibliotheque initialContexte identite version e.nom e.generalises selection

            else
                T.extraire m.document.bibliotheque ctx identite version e.nom e.generalises [ Bloc b ]

        _ ->
            Err (Erreur "Aucune extraction sélectionnée.")


update : Message -> Modele -> Modele
update msg m =
    let
        doc =
            m.document

        avecSelection fn =
            selectionnee m |> Maybe.map fn |> Maybe.withDefault { m | message = "Sélectionnez un bloc." }
    in
    case msg of
        Zoomer ecart ->
            { m | zoom = clamp 50 150 (m.zoom + ecart) }

        Recentrer ->
            { m | zoom = 100 }

        AnnulerGeste ->
            { m | source = Nothing, extraction = Nothing, inspection = Nothing, cibleFormule = Nothing, message = "Geste annulé." }

        AucuneAction ->
            m

        Exporter ->
            { m | message = "Export de la preuve et de tous ses certificats." }

        Importer ->
            m

        Choisir s ->
            { m | source = Just s, message = "Objet sélectionné. Touchez un emplacement ou atteignez-le au clavier pour le placer." }

        Placer cible ->
            case m.source of
                Nothing ->
                    if String.startsWith "preuve:" cible then
                        G.lireCible (String.dropLeft 7 cible) |> Maybe.map (\c -> { m | cible = c, panneau = "faits", message = "Faits disponibles dans cette cavité." }) |> Maybe.withDefault m

                    else
                        m

                Just source ->
                    poser source cible m

        Deposer source cible ->
            poser source cible m

        Selectionner id ->
            { m | selection = Just id, panneau = "inspecter", inspection = Nothing, extraction = Nothing }

        ChoisirCavite c ->
            { m | cible = c, panneau = "faits" }

        Panneau p ->
            { m | panneau = p, cibleFormule = Nothing, extraction = Nothing }

        Exemple e ->
            { m | exemple = e }

        Charger solution ->
            let
                exemple =
                    Ex.charger m.exemple solution
            in
            modifier { exemple | bibliotheque = doc.bibliotheque, prochain = doc.prochain + 1 } m
                |> (\n ->
                        { n
                            | selection = Nothing
                            , cible = { parent = "racine", indice = 0, position = 0 }
                            , source = Nothing
                            , repli = Set.empty
                            , extraction = Nothing
                            , inspection = Nothing
                            , message =
                                if solution && m.exemple == "chaine" then
                                    "Composez deux occurrences de votre transitivité : les certificats personnels restent dans Mes théorèmes."

                                else if solution then
                                    "Solution manipulable chargée. Vous pouvez la modifier et en extraire un théorème."

                                else
                                    "Énoncé chargé. Les prémisses sont déclarées ; les objectifs restent à démontrer."
                        }
                   )

        Annuler ->
            case m.passes of
                ancien :: suite ->
                    { m | document = ancien, passes = suite, futurs = doc :: m.futurs, selection = Nothing, source = Nothing, extraction = Nothing, inspection = Nothing, message = "Modification annulée." }

                [] ->
                    m

        Retablir ->
            case m.futurs of
                suivant :: suite ->
                    { m | document = suivant, passes = doc :: m.passes, futurs = suite, selection = Nothing, source = Nothing, extraction = Nothing, message = "Modification rétablie." }

                [] ->
                    m

        Supprimer ->
            avecSelection (\( b, _ ) -> modifier { doc | preuves = G.retirer b.id doc.preuves } m |> (\n -> { n | selection = Nothing, message = "Bloc retiré. Ses éventuels consommateurs restent visibles et signalés." }))

        Dupliquer ->
            avecSelection
                (\( b, _ ) ->
                    case ( G.dupliquer (nouvelId doc ++ "/copie/") [ Bloc b ] |> List.head, G.position b.id doc.preuves ) of
                        ( Just copie, Just origine ) ->
                            G.inserer { origine | position = origine.position + 1 } copie doc.preuves |> Result.map (\ps -> modifier { doc | preuves = ps, prochain = doc.prochain + 1 } m) |> Result.withDefault m

                        _ ->
                            m
                )

        Replier ->
            case m.selection of
                Just id ->
                    { m
                        | repli =
                            if Set.member id m.repli then
                                Set.remove id m.repli

                            else
                                Set.insert id m.repli
                        , message = "Le repli change l’affichage ; il ne crée aucun théorème."
                    }

                Nothing ->
                    m

        PreparerExtraction ->
            preparerExtraction m

        NomTheoreme nom ->
            { m | extraction = Maybe.map (\e -> { e | nom = String.left 100 nom }) m.extraction }

        Generaliser atome oui ->
            { m
                | extraction =
                    Maybe.map
                        (\e ->
                            { e
                                | generalises =
                                    if oui then
                                        Set.insert atome e.generalises

                                    else
                                        Set.remove atome e.generalises
                            }
                        )
                        m.extraction
            }

        EtendueExtraction oui ->
            let
                selection =
                    m.selection
                        |> Maybe.andThen (\id -> G.position id doc.preuves)
                        |> Maybe.map
                            (\position ->
                                if oui then
                                    G.sequence position doc.preuves |> Maybe.withDefault [] |> List.take (position.position + 1)

                                else
                                    selectionnee m |> Maybe.map (\( b, _ ) -> [ Bloc b ]) |> Maybe.withDefault []
                            )
                        |> Maybe.withDefault []

                atomes =
                    G.formules (G.elaguer selection) |> List.foldl (F.atomes >> Set.union) Set.empty
            in
            { m | extraction = Maybe.map (\e -> { e | sequence = oui, atomes = atomes, generalises = atomes }) m.extraction }

        VersionDe id ->
            { m
                | extraction =
                    Maybe.map
                        (\e ->
                            { e
                                | versionDe =
                                    if id == "nouveau" then
                                        Nothing

                                    else
                                        Just id
                            }
                        )
                        m.extraction
            }

        EnregistrerTheoreme ->
            case propositionExtraction m of
                Err p ->
                    { m | message = messageProbleme p }

                Ok def ->
                    modifier { doc | bibliotheque = doc.bibliotheque ++ [ def ], prochain = doc.prochain + 1 } m |> (\n -> { n | extraction = Nothing, panneau = "theoremes", message = "Théorème certifié : " ++ def.nom ++ ". Il est disponible dans Mes théorèmes." })

        FermerExtraction ->
            { m | extraction = Nothing }

        Inspecter ->
            avecSelection
                (\( b, ctx ) ->
                    case T.developper doc.bibliotheque ctx (Bloc b) of
                        Err p ->
                            { m | message = messageProbleme p }

                        Ok developpee ->
                            { m | inspection = Just developpee }
                )

        Developper ->
            avecSelection
                (\( b, ctx ) ->
                    case T.developper doc.bibliotheque ctx (Bloc b) of
                        Err p ->
                            { m | message = messageProbleme p }

                        Ok (Bloc developpee) ->
                            modifier
                                { doc
                                    | preuves =
                                        G.transformer
                                            (\n ->
                                                if n.id == b.id then
                                                    developpee

                                                else
                                                    n
                                            )
                                            doc.preuves
                                }
                                m
                                |> (\n -> { n | inspection = Nothing, message = "Occurrence développée. La définition et les autres occurrences sont conservées." })
                )

        FermerInspection ->
            { m | inspection = Nothing }

        EditerFormule cible ->
            formuleCible m cible |> Maybe.map (\f -> { m | cibleFormule = Just cible, brouillon = f, texteFormule = F.afficher f, chemin = [], panneau = "formules" }) |> Maybe.withDefault m

        TexteFormule s ->
            { m | texteFormule = String.left 500 s }

        AnalyserFormule ->
            case F.lire m.texteFormule of
                Err erreur ->
                    { m | message = erreur }

                Ok f ->
                    { m | brouillon = f, chemin = [] }

        Connecteur r ->
            let
                f =
                    F.remplacer m.chemin (connecteur r) m.brouillon
            in
            { m | brouillon = f, texteFormule = F.afficher f }

        NomAtome s ->
            { m | nomAtome = String.left 60 s }

        InsererAtome ->
            case F.lire m.nomAtome of
                Ok (Atome nom) ->
                    let
                        f =
                            F.remplacer m.chemin (Atome nom) m.brouillon
                    in
                    { m | brouillon = f, texteFormule = F.afficher f }

                _ ->
                    { m | message = "Donnez un nom d’atome, par exemple A ou Pluie." }

        CheminFormule chemin ->
            { m | chemin = chemin }

        AppliquerFormule ->
            case m.cibleFormule of
                Just cible ->
                    appliquer cible m.brouillon m

                Nothing ->
                    { m | source = Just "prop:brouillon", message = "Proposition sélectionnée : placez-la dans un champ de formule." }

        FermerFormule ->
            { m | cibleFormule = Nothing }

        AjouterPremisse ->
            let
                id =
                    nouvelId doc
            in
            modifier { doc | premisses = doc.premisses ++ [ { id = id, formule = Atome "A" } ], prochain = doc.prochain + 1 } m |> update (EditerFormule ("premisse:" ++ id))

        RetirerPremisse id ->
            modifier { doc | premisses = List.filter (.id >> (/=) id) doc.premisses } m

        Restaurer source ->
            case S.lire source of
                Err erreur ->
                    { m | stockageBloque = True, message = "Sauvegarde locale illisible : " ++ erreur ++ ". Elle est conservée. Exportez le travail courant avant de reprendre la sauvegarde." }

                Ok importe ->
                    { m | document = importe, message = "Travail local restauré et certificats revérifiés." }

        ImportRecu source ->
            case S.lire source of
                Err erreur ->
                    { m | message = "Import refusé : " ++ erreur }

                Ok importe ->
                    modifier importe m |> (\n -> { n | selection = Nothing, cible = { parent = "racine", indice = 0, position = 0 }, source = Nothing, extraction = Nothing, inspection = Nothing, message = "Preuve et bibliothèque importées ; certificats revérifiés." })

        StockageErreur erreur ->
            { m | stockageBloque = True, message = erreur ++ " Le travail courant reste en mémoire. Exportez-le avant de reprendre la sauvegarde." }

        ReprendreStockage ->
            { m | stockageBloque = False, message = "Sauvegarde locale réactivée pour le travail courant." }

        Evenement valeur ->
            let
                dec =
                    D.field "type" D.string
                        |> D.andThen
                            (\genre ->
                                case genre of
                                    "depot" ->
                                        D.map2 Deposer (D.field "source" D.string) (D.field "cible" D.string)

                                    "restaurer" ->
                                        D.map Restaurer (D.field "texte" D.string)

                                    "import" ->
                                        D.map ImportRecu (D.field "texte" D.string)

                                    "erreur-stockage" ->
                                        D.map StockageErreur (D.field "message" D.string)

                                    "annuler" ->
                                        D.succeed Annuler

                                    "retablir" ->
                                        D.succeed Retablir

                                    "echapper" ->
                                        D.succeed AnnulerGeste

                                    _ ->
                                        D.succeed AucuneAction
                            )
            in
            D.decodeValue dec valeur |> Result.map (\message -> update message m) |> Result.withDefault m
