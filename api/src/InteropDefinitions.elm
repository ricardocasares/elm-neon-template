module InteropDefinitions exposing (Flags, FromElm(..), Request, Resolver, Response, ToElm(..), interop)

import Dict exposing (Dict)
import Json.Encode as Encode
import TsJson.Decode as TsDecode exposing (Decoder)
import TsJson.Encode as TsEncode exposing (Encoder)


interop :
    { toElm : Decoder ToElm
    , fromElm : Encoder FromElm
    , flags : Decoder Flags
    }
interop =
    { toElm = toElm
    , fromElm = fromElm
    , flags = flags
    }


type ToElm
    = GotRequest Resolver Request


type FromElm
    = Respond Resolver Response
    | Log String


type alias Flags =
    { databaseUrl : Maybe String
    , neonEndpoint : Maybe String
    }


type Resolver
    = Resolver Encode.Value


type alias Request =
    { method : String
    , path : List String
    , query : Dict String String
    , headers : Dict String String
    , body : String
    }


type alias Response =
    { status : Int
    , headers : List ( String, String )
    , body : String
    }



-- TO ELM


toElm : Decoder ToElm
toElm =
    TsDecode.discriminatedUnion "tag"
        [ ( "Request"
          , TsDecode.map2 GotRequest
                (TsDecode.field "resolve" resolverDecoder)
                (TsDecode.field "request" requestDecoder)
          )
        ]


resolverDecoder : Decoder Resolver
resolverDecoder =
    TsDecode.map Resolver TsDecode.value


requestDecoder : Decoder Request
requestDecoder =
    TsDecode.map5 Request
        (TsDecode.field "method" TsDecode.string)
        (TsDecode.field "path" (TsDecode.list TsDecode.string))
        (TsDecode.field "query" (TsDecode.dict TsDecode.string))
        (TsDecode.field "headers" (TsDecode.dict TsDecode.string))
        (TsDecode.field "body" TsDecode.string)



-- FROM ELM


fromElm : Encoder FromElm
fromElm =
    TsEncode.union
        (\respond log value ->
            case value of
                Respond resolver response ->
                    respond ( resolver, response )

                Log message ->
                    log message
        )
        |> TsEncode.variantObject "Respond"
            [ TsEncode.required "resolve" Tuple.first resolverEncoder
            , TsEncode.required "status" (Tuple.second >> .status) TsEncode.int
            , TsEncode.required "headers"
                (Tuple.second >> .headers)
                (TsEncode.list (TsEncode.tuple TsEncode.string TsEncode.string))
            , TsEncode.required "body" (Tuple.second >> .body) TsEncode.string
            ]
        |> TsEncode.variantObject "Log" [ TsEncode.required "message" identity TsEncode.string ]
        |> TsEncode.buildUnion


resolverEncoder : Encoder Resolver
resolverEncoder =
    TsEncode.map (\(Resolver fn) -> fn) TsEncode.value



-- FLAGS


flags : Decoder Flags
flags =
    TsDecode.map2 Flags
        (TsDecode.field "databaseUrl" (TsDecode.nullable TsDecode.string))
        (TsDecode.field "neonEndpoint" (TsDecode.nullable TsDecode.string))
