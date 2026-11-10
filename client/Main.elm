module Main exposing (Model, Msg, main)

import Api
import ApiClient
import Browser
import Html exposing (Html, code, div, h1, p, span, text)
import Html.Attributes exposing (class)
import Html.Events exposing (onClick)
import InteropDefinitions as Interop exposing (Theme)
import InteropPorts
import Json.Decode as Decode
import Process
import Task
import UI.Badge as Badge
import UI.Button as Button
import UI.Card as Card
import UI.Spinner as Spinner


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
    , copied : Bool
    , error : Maybe String
    , health : Health
    }


type Health
    = Checking
    | Healthy Api.Health
    | Unhealthy String


init : Decode.Value -> ( Model, Cmd Msg )
init flags =
    let
        { theme, systemDark } =
            InteropPorts.decodeFlags flags
                |> Result.withDefault { theme = Nothing, systemDark = False }
    in
    ( { theme = Maybe.withDefault Interop.System theme
      , systemDark = systemDark
      , copied = False
      , error = Nothing
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
    = ThemeSelected Theme
    | CopyClicked
    | CopiedReset
    | GotInterop (Result Decode.Error Interop.ToElm)
    | GotHealth (Result String Api.Health)
    | CheckHealth


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        ThemeSelected theme ->
            ( { model | theme = theme }
            , InteropPorts.fromElm
                (Interop.WriteToLocalStorage
                    { key = "theme"
                    , value = Interop.themeToString theme
                    }
                )
            )

        CopyClicked ->
            ( { model | copied = True }
            , Cmd.batch
                [ InteropPorts.fromElm (Interop.CopyToClipboard "bunx --bun shadcn@latest add ricardocasares/elmcn/button")
                , Task.perform (\_ -> CopiedReset) (Process.sleep 1500)
                ]
            )

        CopiedReset ->
            ( { model | copied = False }, Cmd.none )

        GotInterop (Ok (Interop.SystemThemeChanged systemDark)) ->
            ( { model | systemDark = systemDark }, Cmd.none )

        GotInterop (Ok (Interop.LocalStorageError error)) ->
            ( { model | error = Just (error.key ++ ": " ++ error.message) }, Cmd.none )

        GotInterop (Ok (Interop.ClipboardError message)) ->
            ( { model | copied = False, error = Just message }, Cmd.none )

        GotInterop (Err _) ->
            ( model, Cmd.none )

        GotHealth (Ok health) ->
            ( { model | health = Healthy health }, Cmd.none )

        GotHealth (Err message) ->
            ( { model | health = Unhealthy message }, Cmd.none )

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
        [ div [ class "flex min-h-screen flex-col items-center justify-center gap-6 bg-background p-6 text-foreground" ]
            [ h1 [ class "text-2xl font-semibold" ] [ text "elm-neon-template" ]
            , div [ class "flex gap-2" ]
                [ themeButton model Interop.Light "Light"
                , themeButton model Interop.Dark "Dark"
                , themeButton model Interop.System "System"
                ]
            , p [ class "text-sm text-muted-foreground" ]
                [ text "Your choice is saved in localStorage." ]
            , Button.new
                |> Button.text
                    (if model.copied then
                        "Copied"

                     else
                        "Copy install command"
                    )
                |> Button.secondary
                |> Button.toHtml [ onClick CopyClicked ]
            , viewHealth model.health
            , case model.error of
                Just message ->
                    code [ class "text-sm text-destructive" ] [ text message ]

                Nothing ->
                    text ""
            ]
        ]


themeButton : Model -> Theme -> String -> Html Msg
themeButton model theme label =
    Button.new
        |> Button.text label
        |> (if model.theme == theme then
                identity

            else
                Button.outline
           )
        |> Button.toHtml [ onClick (ThemeSelected theme) ]


viewHealth : Health -> Html Msg
viewHealth health =
    Card.new
        |> Card.title [ text "Health" ]
        |> Card.description [ text "Served by the Elm server at /api/health." ]
        |> Card.action
            (Button.new
                |> Button.text "Check again"
                |> Button.outline
                |> Button.small
                |> Button.toHtml [ onClick CheckHealth ]
            )
        |> Card.content []
            [ case health of
                Checking ->
                    div [ class "flex justify-center py-4" ]
                        [ Spinner.view [ class "size-6 text-muted-foreground" ] ]

                Healthy report ->
                    viewCheck "Database" report.database

                Unhealthy message ->
                    p [ class "text-sm text-destructive" ] [ text message ]
            ]
        |> Card.toHtml [ class "w-full max-w-sm" ]


viewCheck : String -> Api.Check -> Html Msg
viewCheck name check =
    div [ class "flex flex-wrap items-center gap-2 text-sm" ]
        [ span [ class "mr-auto" ] [ text name ]
        , case check.latencyMs of
            Just ms ->
                span [ class "text-muted-foreground" ] [ text (String.fromInt ms ++ " ms") ]

            Nothing ->
                text ""
        , case check.status of
            Api.Pass ->
                Badge.new
                    |> Badge.text "pass"
                    |> Badge.secondary
                    |> Badge.toHtml []

            Api.Fail ->
                Badge.new
                    |> Badge.text "fail"
                    |> Badge.destructive
                    |> Badge.toHtml []
        , case check.output of
            Just output ->
                p [ class "w-full text-destructive" ] [ text output ]

            Nothing ->
                text ""
        ]
