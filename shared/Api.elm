module Api exposing
    ( Route(..), Method(..), Problem(..), parse, method, path, toString, methodToString
    , Endpoint, health
    , route, encodeBody, decodeBody, encodeResponse, responseDecoder
    , Health
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


decodeBody : Endpoint body response -> String -> Result String body
decodeBody (Endpoint e) raw =
    case e.body of
        NoBody value ->
            Ok value

        JsonBody codec ->
            Decode.decodeString codec.decoder raw
                |> Result.mapError Decode.errorToString


encodeResponse : Endpoint body response -> response -> Encode.Value
encodeResponse (Endpoint e) =
    e.response.encode


responseDecoder : Endpoint body response -> Decoder response
responseDecoder (Endpoint e) =
    e.response.decoder



-- PAYLOADS


type alias Health =
    { databaseTime : String
    }


healthCodec : Codec Health
healthCodec =
    { encode = \h -> Encode.object [ ( "databaseTime", Encode.string h.databaseTime ) ]
    , decoder = Decode.map Health (Decode.field "databaseTime" Decode.string)
    }
