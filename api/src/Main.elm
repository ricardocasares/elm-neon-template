module Main exposing (Model, Msg, main)

import Api
import Db
import InteropDefinitions as Interop exposing (Request, Response)
import InteropPorts
import Json.Decode as Decode
import Json.Encode as Encode
import Neon
import Task exposing (Task)
import Time


main : Program Decode.Value Model Msg
main =
    Platform.worker
        { init = init
        , update = update
        , subscriptions = \_ -> Sub.map GotInterop InteropPorts.toElm
        }


-- MODEL


type alias Model =
    { db : Result String Neon.Connection
    , release : Api.Release
    }


init : Decode.Value -> ( Model, Cmd Msg )
init flags =
    case InteropPorts.decodeFlags flags of
        Ok config ->
            let
                db =
                    Db.connect config
            in
            ( { db = db
              , release = { releaseId = config.releaseId, releaseUrl = config.releaseUrl, region = config.region }
              }
            , case db of
                Ok connection ->
                    log Interop.Info ("Sending queries to " ++ Neon.endpoint connection)

                Err problem ->
                    log Interop.Warn ("No database, so database routes answer 503: " ++ problem)
            )

        Err problem ->
            ( { db = Err "The server's flags did not decode."
              , release = { releaseId = Nothing, releaseUrl = Nothing, region = Nothing }
              }
            , log Interop.Error ("Bad flags: " ++ Decode.errorToString problem)
            )


log : Interop.Level -> String -> Cmd msg
log level message =
    InteropPorts.fromElm (Interop.Log level message)


-- UPDATE


type Msg
    = GotInterop (Result Decode.Error Interop.ToElm)
    | DatabaseChecked Interop.Resolver ( Int, Result Neon.Error () )


type Reply
    = Now Response
    | Later (Interop.Resolver -> Cmd Msg)


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        GotInterop (Ok (Interop.GotRequest resolver request)) ->
            let
                ( next, reply ) =
                    route model request
            in
            case reply of
                Now response ->
                    ( next, InteropPorts.fromElm (Interop.Respond resolver response) )

                Later toCmd ->
                    ( next, toCmd resolver )

        DatabaseChecked resolver ( latency, Ok () ) ->
            if latency > slowAfter then
                ( model
                , Cmd.batch
                    [ InteropPorts.fromElm
                        (Interop.Respond resolver
                            (health model
                                { status = Api.Warn
                                , latencyMs = Just latency
                                , output = Just ("Slower than " ++ String.fromInt slowAfter ++ " ms.")
                                }
                            )
                        )
                    , log Interop.Warn ("Health check slow: the database took " ++ String.fromInt latency ++ " ms.")
                    ]
                )

            else
                ( model
                , InteropPorts.fromElm
                    (Interop.Respond resolver
                        (health model { status = Api.Pass, latencyMs = Just latency, output = Nothing })
                    )
                )

        DatabaseChecked resolver ( latency, Err problem ) ->
            ( model
            , Cmd.batch
                [ InteropPorts.fromElm
                    (Interop.Respond resolver
                        (health model { status = Api.Fail, latencyMs = Just latency, output = Just (failure problem) })
                    )
                , log Interop.Error ("Health check failed: " ++ Neon.errorToString problem)
                ]
            )

        GotInterop (Err _) ->
            ( model, Cmd.none )


-- ROUTES


route : Model -> Request -> ( Model, Reply )
route model request =
    case Api.parse request.method request.path of
        Ok r ->
            handle model request r

        Err Api.NotFound ->
            ( model, Now (error 404 "Not found.") )

        Err (Api.MethodNotAllowed allowed) ->
            let
                response =
                    error 405 "Method not allowed."
            in
            ( model
            , Now
                { response
                    | headers =
                        ( "allow", String.join ", " (List.map Api.methodToString allowed) )
                            :: response.headers
                }
            )


handle : Model -> Request -> Api.Route -> ( Model, Reply )
handle model _ r =
    case r of
        Api.GetHealth ->
            ( model
            , case model.db of
                Ok db ->
                    Later
                        (\resolver ->
                            Neon.run (Neon.withTimeout healthTimeout db) Db.ping
                                |> timed
                                |> Task.perform (DatabaseChecked resolver)
                        )

                Err problem ->
                    Now (health model { status = Api.Fail, latencyMs = Nothing, output = Just ("Not configured: " ++ problem) })
            )


healthTimeout : Float
healthTimeout =
    5000


slowAfter : Int
slowAfter =
    1000


failure : Neon.Error -> String
failure problem =
    case problem of
        Neon.Timeout ->
            "Timed out after " ++ String.fromFloat healthTimeout ++ " ms."

        Neon.NetworkError ->
            "Unreachable."

        Neon.BadUrl _ ->
            "Unreachable."

        Neon.ServerError status _ ->
            "Neon answered with HTTP " ++ String.fromInt status ++ "."

        Neon.QueryFailed _ ->
            "The query failed."

        Neon.UnexpectedResult _ ->
            "Unexpected result."


timed : Task x a -> Task Never ( Int, Result x a )
timed task =
    Time.now
        |> Task.andThen
            (\start ->
                task
                    |> Task.map Ok
                    |> Task.onError (Err >> Task.succeed)
                    |> Task.andThen
                        (\result ->
                            Time.now
                                |> Task.map (\end -> ( Time.posixToMillis end - Time.posixToMillis start, result ))
                        )
            )



-- RESPONSES


json : Int -> Encode.Value -> Response
json status value =
    { status = status
    , headers = [ ( "content-type", "application/json" ), ( "cache-control", "no-store" ) ]
    , body = Encode.encode 0 value
    }


health : Model -> Api.Check -> Response
health model check =
    let
        report =
            Api.healthOf model.release check
    in
    { status =
        case report.status of
            Api.Pass ->
                200

            Api.Warn ->
                200

            Api.Fail ->
                503
    , headers = [ ( "content-type", "application/health+json" ), ( "cache-control", "no-store" ) ]
    , body = Encode.encode 0 (Api.encodeResponse Api.health report)
    }


error : Int -> String -> Response
error status message =
    json status (Api.encodeError message)
