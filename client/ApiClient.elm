module ApiClient exposing (request)

import Api exposing (Endpoint)
import ApiError
import Http
import Json.Decode as Decode


request : Endpoint body response -> body -> (Result String response -> msg) -> Cmd msg
request endpoint body toMsg =
    let
        route =
            Api.route endpoint
    in
    Http.request
        { method = Api.methodToString (Api.method route)
        , headers = []
        , url = Api.toString route
        , body =
            case Api.encodeBody endpoint body of
                Just value ->
                    Http.jsonBody value

                Nothing ->
                    Http.emptyBody
        , expect = expect toMsg (Api.responseDecoder endpoint)
        , timeout = Nothing
        , tracker = Nothing
        }


expect : (Result String a -> msg) -> Decode.Decoder a -> Http.Expect msg
expect toMsg decoder =
    Http.expectStringResponse toMsg <|
        \response ->
            case response of
                Http.BadUrl_ url ->
                    Err ("Bad URL: " ++ url)

                Http.Timeout_ ->
                    Err "The server took too long to answer."

                Http.NetworkError_ ->
                    Err "Could not reach the server. Start both apps with `bun dev`."

                Http.BadStatus_ metadata body ->
                    Decode.decodeString ApiError.decoder body
                        |> Result.withDefault
                            ("The server answered with status "
                                ++ String.fromInt metadata.statusCode
                                ++ ". Is it running? Start both apps with `bun dev`."
                            )
                        |> Err

                Http.GoodStatus_ _ body ->
                    Decode.decodeString decoder body
                        |> Result.mapError (\error -> "Unexpected response: " ++ Decode.errorToString error)
