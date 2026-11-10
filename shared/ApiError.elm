module ApiError exposing (decoder, encode)

import Json.Decode as Decode exposing (Decoder)
import Json.Encode as Encode


decoder : Decoder String
decoder =
    Decode.field "error" Decode.string


encode : String -> Encode.Value
encode message =
    Encode.object [ ( "error", Encode.string message ) ]
