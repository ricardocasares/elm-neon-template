module Main exposing (Model, Msg, main)

import Api
import ApiError
import Db
import InteropDefinitions as Interop exposing (Request, Response)
import InteropPorts
import Json.Decode as Decode
import Json.Encode as Encode
import Neon
import Task exposing (Task)


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
    }


init : Decode.Value -> ( Model, Cmd Msg )
init flags =
    let
        config =
            InteropPorts.decodeFlags flags
                |> Result.withDefault { databaseUrl = Nothing, neonEndpoint = Nothing }
    in
    ( { db = Db.connect config }
    , Cmd.none
    )



-- UPDATE


type Msg
    = GotInterop (Result Decode.Error Interop.ToElm)
    | Answered Interop.Resolver (Result Neon.Error Response)


type Reply
    = Now Response
    | Later (Task Neon.Error Response)


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

                Later task ->
                    ( next, Task.attempt (Answered resolver) task )

        Answered resolver (Ok response) ->
            ( model, InteropPorts.fromElm (Interop.Respond resolver response) )

        Answered resolver (Err problem) ->
            ( model
            , Cmd.batch
                [ InteropPorts.fromElm (Interop.Respond resolver (error 500 "Database error."))
                , InteropPorts.fromElm (Interop.Log ("Database error: " ++ Neon.errorToString problem))
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
            , withDb model <|
                \db ->
                    Neon.run db Db.now
                        |> Task.map
                            (\found ->
                                case found of
                                    Just time ->
                                        ok Api.health { databaseTime = time }

                                    Nothing ->
                                        error 500 "The database returned no rows."
                            )
            )


withDb : Model -> (Neon.Connection -> Task Neon.Error Response) -> Reply
withDb model query =
    case model.db of
        Ok db ->
            Later (query db)

        Err problem ->
            Now (error 503 ("The database is not configured: " ++ problem))



-- RESPONSES


json : Int -> Encode.Value -> Response
json status value =
    { status = status
    , headers = [ ( "content-type", "application/json" ), ( "cache-control", "no-store" ) ]
    , body = Encode.encode 0 value
    }


ok : Api.Endpoint body response -> response -> Response
ok =
    respond 200


respond : Int -> Api.Endpoint body response -> response -> Response
respond status endpoint value =
    json status (Api.encodeResponse endpoint value)


error : Int -> String -> Response
error status message =
    json status (ApiError.encode message)
