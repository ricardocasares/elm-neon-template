module Main exposing (Model, Msg, main)

import Api
import ApiClient
import Browser
import Html exposing (Html, div, li, p, span, text, ul)
import Html.Attributes exposing (attribute, class)
import Html.Events exposing (onClick)
import InteropDefinitions as Interop exposing (Theme)
import InteropPorts
import Json.Decode as Decode
import Phosphor exposing (IconWeight(..))
import UI.Button as Button
import UI.Card as Card
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
    = Checking
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
      , health = Checking
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
            ( { model | health = Checking }, checkHealth )

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
                Checking ->
                    viewRows [ row "animate-pulse bg-muted-foreground" "Checking…" Nothing Nothing ]

                Unreachable message ->
                    viewRows [ row "bg-red-500" "Server" Nothing (Just message) ]

                Checked report ->
                    viewRows (List.map viewCheck (Api.checks report))
            ]
        |> Card.toHtml [ class "w-full max-w-sm" ]


viewRows : List (Html Msg) -> Html Msg
viewRows rows =
    ul [ class "flex flex-col gap-3", attribute "role" "status" ] rows


viewCheck : ( String, Api.Check ) -> Html Msg
viewCheck ( name, check ) =
    row (statusDot check.status) name check.latencyMs check.output


statusDot : Api.Status -> String
statusDot status =
    case status of
        Api.Pass ->
            "bg-green-500"

        Api.Warn ->
            "bg-yellow-500"

        Api.Fail ->
            "bg-red-500"


row : String -> String -> Maybe Int -> Maybe String -> Html Msg
row dot name latencyMs output =
    li [ class "flex flex-wrap items-center gap-x-3 gap-y-1" ]
        [ span [ class ("size-3 shrink-0 rounded-full " ++ dot) ] []
        , span [ class "font-medium" ] [ text name ]
        , span [ class "ml-auto text-sm text-muted-foreground tabular-nums" ]
            [ text (Maybe.withDefault "" (Maybe.map (\ms -> String.fromInt ms ++ " ms") latencyMs)) ]
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
