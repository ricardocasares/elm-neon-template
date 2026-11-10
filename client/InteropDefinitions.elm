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
    = CopyToClipboard String
    | ReadFromLocalStorage String
    | WriteToLocalStorage { key : String, value : String }


type ToElm
    = SystemThemeChanged Bool
    | LocalStorageError { key : String, message : String }
    | ClipboardError String


{-| `theme` is what the user last chose, if anything.
-}
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
        (\copyToClipboard readFromLocalStorage writeToLocalStorage value ->
            case value of
                CopyToClipboard text ->
                    copyToClipboard text

                ReadFromLocalStorage key ->
                    readFromLocalStorage key

                WriteToLocalStorage entry ->
                    writeToLocalStorage entry
        )
        |> TsEncode.variantTagged "CopyToClipboard" TsEncode.string
        |> TsEncode.variantTagged "ReadFromLocalStorage" TsEncode.string
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
        [ ( "SystemThemeChanged", TsDecode.map SystemThemeChanged (TsDecode.field "dark" TsDecode.bool) )
        , ( "LocalStorageError"
          , TsDecode.map2 (\key message -> LocalStorageError { key = key, message = message })
                (TsDecode.field "key" TsDecode.string)
                (TsDecode.field "message" TsDecode.string)
          )
        , ( "ClipboardError", TsDecode.map ClipboardError (TsDecode.field "message" TsDecode.string) )
        ]


themeDecoder : Decoder Theme
themeDecoder =
    TsDecode.stringUnion [ ( "light", Light ), ( "dark", Dark ), ( "system", System ) ]


flags : Decoder Flags
flags =
    TsDecode.map2 Flags
        (TsDecode.field "theme" (TsDecode.nullable themeDecoder))
        (TsDecode.field "systemDark" TsDecode.bool)
