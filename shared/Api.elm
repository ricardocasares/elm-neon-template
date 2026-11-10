module Api exposing
    ( Route(..), Method(..), Problem(..), parse, method, path, toString, methodToString
    , Endpoint, health
    , route, encodeBody, encodeResponse, responseDecoder
    , encodeError, errorDecoder
    , Health, Check, Status(..), Release, healthOf, checks, checkNames
    )

import Json.Decode as Decode exposing (Decoder)
import Json.Encode as Encode
import Url



-- ROUTES


type Route
    = GetHealth


type Method
    = Get
    | Post


type Problem
    = NotFound
    | MethodNotAllowed (List Method)


method : Route -> Method
method r =
    case r of
        GetHealth ->
            Get


path : Route -> List String
path r =
    "api" :: segments r


segments : Route -> List String
segments r =
    case r of
        GetHealth ->
            [ "health" ]


toString : Route -> String
toString r =
    "/" ++ String.join "/" (List.map Url.percentEncode (path r))


methodToString : Method -> String
methodToString m =
    case m of
        Get ->
            "GET"

        Post ->
            "POST"


parse : String -> List String -> Result Problem Route
parse methodName pathSegments =
    let
        candidates =
            case pathSegments of
                "api" :: rest ->
                    routesAt rest

                _ ->
                    []
    in
    case List.filter (\r -> methodToString (method r) == methodName) candidates of
        r :: _ ->
            Ok r

        [] ->
            if List.isEmpty candidates then
                Err NotFound

            else
                Err (MethodNotAllowed (List.map method candidates))


routesAt : List String -> List Route
routesAt rest =
    case rest of
        [ "health" ] ->
            [ GetHealth ]

        _ ->
            []



-- ENDPOINTS


type Endpoint body response
    = Endpoint
        { route : Route
        , body : Body body
        , response : Codec response
        }


type Body a
    = NoBody a
    | JsonBody (Codec a)


type alias Codec a =
    { encode : a -> Encode.Value
    , decoder : Decoder a
    }


health : Endpoint () Health
health =
    Endpoint { route = GetHealth, body = NoBody (), response = healthCodec }


route : Endpoint body response -> Route
route (Endpoint e) =
    e.route


encodeBody : Endpoint body response -> body -> Maybe Encode.Value
encodeBody (Endpoint e) value =
    case e.body of
        NoBody _ ->
            Nothing

        JsonBody codec ->
            Just (codec.encode value)


encodeResponse : Endpoint body response -> response -> Encode.Value
encodeResponse (Endpoint e) =
    e.response.encode


responseDecoder : Endpoint body response -> Decoder response
responseDecoder (Endpoint e) =
    e.response.decoder



encodeError : String -> Encode.Value
encodeError message =
    Encode.object [ ( "error", Encode.string message ) ]


errorDecoder : Decoder String
errorDecoder =
    Decode.field "error" Decode.string



-- PAYLOADS


type Status
    = Pass
    | Warn
    | Fail


type alias Check =
    { status : Status
    , latencyMs : Maybe Int
    , output : Maybe String
    }


type alias Release =
    { releaseId : Maybe String
    , releaseUrl : Maybe String
    , region : Maybe String
    }


type alias Health =
    { status : Status
    , release : Release
    , database : Check
    }


healthOf : Release -> Check -> Health
healthOf release database =
    { status = database.status, release = release, database = database }


checks : Health -> List ( String, Check )
checks health_ =
    List.map (\( name, check ) -> ( name, check health_ )) namedChecks


checkNames : List String
checkNames =
    List.map Tuple.first namedChecks


namedChecks : List ( String, Health -> Check )
namedChecks =
    [ ( "Database", .database ) ]


healthCodec : Codec Health
healthCodec =
    { encode =
        \h ->
            Encode.object
                (List.filterMap identity
                    [ Just ( "status", encodeStatus h.status )
                    , Maybe.map (\id -> ( "releaseId", Encode.string id )) h.release.releaseId
                    , Maybe.map (\region -> ( "region", Encode.string region )) h.release.region
                    , Maybe.map (\url -> ( "links", Encode.object [ ( "release", Encode.string url ) ] )) h.release.releaseUrl
                    , Just ( "checks", Encode.object [ ( "database", encodeCheck h.database ) ] )
                    ]
                )
    , decoder =
        Decode.map3 Health
            (Decode.field "status" statusDecoder)
            (Decode.map3 Release
                (Decode.maybe (Decode.field "releaseId" Decode.string))
                (Decode.maybe (Decode.at [ "links", "release" ] Decode.string))
                (Decode.maybe (Decode.field "region" Decode.string))
            )
            (Decode.at [ "checks", "database" ] checkDecoder)
    }


encodeCheck : Check -> Encode.Value
encodeCheck check =
    Encode.object
        (List.filterMap identity
            [ Just ( "status", encodeStatus check.status )
            , Maybe.map (\ms -> ( "latencyMs", Encode.int ms )) check.latencyMs
            , Maybe.map (\output -> ( "output", Encode.string output )) check.output
            ]
        )


checkDecoder : Decoder Check
checkDecoder =
    Decode.map3 Check
        (Decode.field "status" statusDecoder)
        (Decode.maybe (Decode.field "latencyMs" Decode.int))
        (Decode.maybe (Decode.field "output" Decode.string))


encodeStatus : Status -> Encode.Value
encodeStatus status =
    case status of
        Pass ->
            Encode.string "pass"

        Warn ->
            Encode.string "warn"

        Fail ->
            Encode.string "fail"


statusDecoder : Decoder Status
statusDecoder =
    Decode.string
        |> Decode.andThen
            (\status ->
                case status of
                    "pass" ->
                        Decode.succeed Pass

                    "warn" ->
                        Decode.succeed Warn

                    "fail" ->
                        Decode.succeed Fail

                    _ ->
                        Decode.fail ("Unknown health status: " ++ status)
            )
