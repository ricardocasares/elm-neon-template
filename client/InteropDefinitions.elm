module InteropDefinitions exposing (Flags, FromElm(..), Theme(..), ToElm(..), interop, themeToString)

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


type Theme
    = Light
    | Dark
    | System


type FromElm
    = WriteToLocalStorage { key : String, value : String }


type ToElm
    = SystemThemeChanged Bool


type alias Flags =
    { theme : Maybe Theme
    , systemDark : Bool
    }


themeToString : Theme -> String
themeToString theme =
    case theme of
        Light ->
            "light"

        Dark ->
            "dark"

        System ->
            "system"


fromElm : Encoder FromElm
fromElm =
    TsEncode.union
        (\writeToLocalStorage value ->
            case value of
                WriteToLocalStorage entry ->
                    writeToLocalStorage entry
        )
        |> TsEncode.variantTagged "WriteToLocalStorage"
            (TsEncode.object
                [ TsEncode.required "key" .key TsEncode.string
                , TsEncode.required "value" .value TsEncode.string
                ]
            )
        |> TsEncode.buildUnion


toElm : Decoder ToElm
toElm =
    TsDecode.discriminatedUnion "tag"
        [ ( "SystemThemeChanged", TsDecode.map SystemThemeChanged (TsDecode.field "dark" TsDecode.bool) ) ]


themeDecoder : Decoder Theme
themeDecoder =
    TsDecode.stringUnion [ ( "light", Light ), ( "dark", Dark ), ( "system", System ) ]


flags : Decoder Flags
flags =
    TsDecode.map2 Flags
        (TsDecode.field "theme" (TsDecode.nullable themeDecoder))
        (TsDecode.field "systemDark" TsDecode.bool)
