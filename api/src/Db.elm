module Db exposing (connect, ping)

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


ping : Neon.Query ()
ping =
    Neon.execute "SELECT 1" []
        |> Neon.map (always ())
