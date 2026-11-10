module Db exposing (connect, now)

import Json.Decode as Decode
import Neon


connect : { a | databaseUrl : Maybe String, neonEndpoint : Maybe String } -> Result String Neon.Connection
connect config =
    case config.databaseUrl of
        Nothing ->
            Err "DATABASE_URL is not set."

        Just url ->
            Neon.connect url
                |> Result.map
                    (\connection ->
                        config.neonEndpoint
                            |> Maybe.map (\endpoint -> Neon.withEndpoint endpoint connection)
                            |> Maybe.withDefault connection
                    )


now : Neon.Query (Maybe String)
now =
    Neon.selectOne "SELECT now()::text AS now" [] (Decode.field "now" Decode.string)
