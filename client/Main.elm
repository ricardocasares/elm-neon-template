module Main exposing (Model, Msg, main)

import Api
import ApiClient
import Browser
import Html exposing (Html, div, p, span, text)
import Html.Attributes exposing (attribute, class)
import Html.Events exposing (onClick)
import InteropDefinitions as Interop exposing (Theme)
import InteropPorts
import Json.Decode as Decode
import UI.Button as Button
import UI.Card as Card


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
        [ div [ class "flex min-h-screen items-center justify-center bg-background p-6 text-foreground" ]
            [ viewHealth model.health ]
        ]


viewHealth : Health -> Html Msg
viewHealth health =
    let
        { dot, label, detail } =
            describe health
    in
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
            [ div [ class "flex items-center gap-3", attribute "role" "status" ]
                [ span [ class ("size-3 shrink-0 rounded-full " ++ dot) ] []
                , span [ class "font-medium" ] [ text label ]
                , span [ class "ml-auto text-sm text-muted-foreground tabular-nums" ] [ text detail.latency ]
                ]
            , case detail.output of
                Just output ->
                    p [ class "mt-2 text-sm text-muted-foreground" ] [ text output ]

                Nothing ->
                    text ""
            ]
        |> Card.toHtml [ class "w-full max-w-sm" ]


describe : Health -> { dot : String, label : String, detail : { latency : String, output : Maybe String } }
describe health =
    case health of
        Checking ->
            { dot = "animate-pulse bg-muted-foreground"
            , label = "Checking…"
            , detail = { latency = "", output = Nothing }
            }

        Unreachable message ->
            { dot = "bg-red-500"
            , label = "Unreachable"
            , detail = { latency = "", output = Just message }
            }

        Checked report ->
            let
                detail =
                    { latency =
                        report.database.latencyMs
                            |> Maybe.map (\ms -> String.fromInt ms ++ " ms")
                            |> Maybe.withDefault ""
                    , output = report.database.output
                    }
            in
            case report.status of
                Api.Pass ->
                    { dot = "bg-green-500", label = "Healthy", detail = detail }

                Api.Warn ->
                    { dot = "bg-yellow-500", label = "Degraded", detail = detail }

                Api.Fail ->
                    { dot = "bg-red-500", label = "Unhealthy", detail = detail }
