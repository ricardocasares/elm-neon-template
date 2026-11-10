module Main exposing (Model, Msg, main)

import Api
import ApiClient
import Browser
import Html exposing (Html, a, div, li, p, span, text, ul)
import Html.Attributes exposing (attribute, class, href, rel, target)
import Html.Events exposing (onClick)
import InteropDefinitions as Interop exposing (Theme)
import InteropPorts
import Json.Decode as Decode
import Phosphor exposing (IconWeight(..))
import UI.Button as Button
import UI.Card as Card
import UI.Skeleton as Skeleton
import UI.Tabs as Tabs


main : Program Decode.Value Model Msg
main =
    Browser.element
        { init = init
        , update = update
        , view = view
        , subscriptions = \_ -> Sub.map GotInterop InteropPorts.toElm
        }



-- MODEL


type alias Model =
    { theme : Theme
    , systemDark : Bool
    , health : Health
    }


type Health
    = Checking (Maybe Api.Health)
    | Checked Api.Health
    | Unreachable String


init : Decode.Value -> ( Model, Cmd Msg )
init flags =
    let
        { theme, systemDark } =
            InteropPorts.decodeFlags flags
                |> Result.withDefault { theme = Nothing, systemDark = False }
    in
    ( { theme = Maybe.withDefault Interop.System theme
      , systemDark = systemDark
      , health = Checking Nothing
      }
    , checkHealth
    )


checkHealth : Cmd Msg
checkHealth =
    ApiClient.request Api.health () GotHealth


isDark : Model -> Bool
isDark model =
    case model.theme of
        Interop.Light ->
            False

        Interop.Dark ->
            True

        Interop.System ->
            model.systemDark



-- UPDATE


type Msg
    = GotInterop (Result Decode.Error Interop.ToElm)
    | GotHealth (Result String Api.Health)
    | CheckHealth
    | ThemeSelected Theme


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        GotInterop (Ok (Interop.SystemThemeChanged systemDark)) ->
            ( { model | systemDark = systemDark }, Cmd.none )

        GotInterop _ ->
            ( model, Cmd.none )

        GotHealth (Ok health) ->
            ( { model | health = Checked health }, Cmd.none )

        GotHealth (Err message) ->
            ( { model | health = Unreachable message }, Cmd.none )

        CheckHealth ->
            ( { model | health = Checking (lastReport model.health) }, checkHealth )

        ThemeSelected theme ->
            ( { model | theme = theme }
            , InteropPorts.fromElm
                (Interop.WriteToLocalStorage
                    { key = "theme"
                    , value = Interop.themeToString theme
                    }
                )
            )



-- VIEW


view : Model -> Html Msg
view model =
    div
        [ class
            (if isDark model then
                "dark"

             else
                ""
            )
        ]
        [ div [ class "flex min-h-screen flex-col items-center justify-center gap-4 bg-background p-6 text-foreground" ]
            [ viewHealth model.health
            , viewThemeTabs model.theme
            ]
        ]


viewHealth : Health -> Html Msg
viewHealth health =
    Card.new
        |> Card.title [ text "Server" ]
        |> Card.description [ text "GET /api/health" ]
        |> Card.action
            (Button.new
                |> Button.text "Refresh"
                |> Button.outline
                |> Button.small
                |> Button.toHtml [ onClick CheckHealth ]
            )
        |> Card.content []
            [ case health of
                Checking Nothing ->
                    viewRows (List.map (\name -> row pendingDot name latencySkeleton Nothing) Api.checkNames)

                Checking (Just report) ->
                    viewRows (List.map (viewCheck (always pendingDot)) (Api.checks report))

                Checked report ->
                    viewRows (List.map (viewCheck statusDot) (Api.checks report))

                Unreachable message ->
                    viewRows [ row "bg-red-500" "Server" (text "") (Just message) ]
            ]
        |> Card.footer [ class "text-xs text-muted-foreground" ] (viewRelease health)
        |> Card.toHtml [ class "w-full max-w-sm" ]


pendingDot : String
pendingDot =
    "animate-pulse bg-muted-foreground"


lastReport : Health -> Maybe Api.Health
lastReport health =
    case health of
        Checking report ->
            report

        Checked report ->
            Just report

        Unreachable _ ->
            Nothing


viewRelease : Health -> List (Html Msg)
viewRelease health =
    case ( health, Maybe.map .release (lastReport health) ) of
        ( Checking Nothing, _ ) ->
            [ div [ class "flex items-center gap-2", attribute "aria-hidden" "true" ]
                [ Skeleton.view [ class "h-4 w-24" ]
                , Skeleton.view [ class "h-4 w-20" ]
                ]
            ]

        ( _, Just release ) ->
            case
                List.filterMap identity
                    [ Maybe.map (viewReleaseId release.releaseUrl) release.releaseId
                    , Maybe.map (\region -> [ text ("Region " ++ region) ]) release.region
                    ]
            of
                [] ->
                    [ placeholder ]

                parts ->
                    [ span [] (List.concat (List.intersperse [ text " · " ] parts)) ]

        ( _, Nothing ) ->
            [ placeholder ]


placeholder : Html Msg
placeholder =
    span [ class "invisible", attribute "aria-hidden" "true" ] [ text "Release" ]


viewReleaseId : Maybe String -> String -> List (Html Msg)
viewReleaseId url id =
    case url of
        Just href_ ->
            [ text "Release "
            , a
                [ href href_
                , target "_blank"
                , rel "noopener noreferrer"
                , class "font-mono underline underline-offset-2 hover:text-foreground"
                ]
                [ text (shortRelease id) ]
            ]

        Nothing ->
            [ text ("Release " ++ shortRelease id) ]


shortRelease : String -> String
shortRelease id =
    if String.startsWith "dpl_" id then
        id

    else
        String.left 7 id


viewRows : List (Html Msg) -> Html Msg
viewRows rows =
    ul [ class "flex flex-col gap-3", attribute "role" "status" ] rows


viewCheck : (Api.Status -> String) -> ( String, Api.Check ) -> Html Msg
viewCheck toDot ( name, check ) =
    row (toDot check.status) name (latency check.latencyMs) check.output


latency : Maybe Int -> Html Msg
latency ms =
    text (Maybe.withDefault "" (Maybe.map (\n -> String.fromInt n ++ " ms") ms))


latencySkeleton : Html Msg
latencySkeleton =
    Skeleton.view [ class "h-4 w-12", attribute "aria-hidden" "true" ]


statusDot : Api.Status -> String
statusDot status =
    case status of
        Api.Pass ->
            "bg-green-500"

        Api.Warn ->
            "bg-yellow-500"

        Api.Fail ->
            "bg-red-500"


row : String -> String -> Html Msg -> Maybe String -> Html Msg
row dot name measured output =
    li [ class "flex flex-wrap items-center gap-x-3 gap-y-1" ]
        [ span [ class ("size-3 shrink-0 rounded-full " ++ dot) ] []
        , span [ class "font-medium" ] [ text name ]
        , div [ class "ml-auto text-sm text-muted-foreground tabular-nums" ] [ measured ]
        , case output of
            Just message ->
                p [ class "w-full pl-6 text-sm text-muted-foreground" ] [ text message ]

            Nothing ->
                text ""
        ]


viewThemeTabs : Theme -> Html Msg
viewThemeTabs theme =
    Tabs.new
        |> Tabs.id "theme"
        |> Tabs.onSelect ThemeSelected
        |> Tabs.value theme
        |> Tabs.tabs
            [ themeTab Interop.Light Phosphor.sun "Light"
            , themeTab Interop.Dark Phosphor.moon "Dark"
            , themeTab Interop.System Phosphor.monitor "System"
            ]
        |> Tabs.toHtml [ attribute "aria-label" "Theme" ]


themeTab : Theme -> Phosphor.Icon -> String -> Tabs.Tab Theme Msg
themeTab theme icon label =
    Tabs.tab theme
        [ icon Regular |> Phosphor.toHtml [ attribute "aria-hidden" "true" ]
        , span [ class "sr-only" ] [ text label ]
        ]
        []
