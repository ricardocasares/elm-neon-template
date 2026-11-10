module Neon exposing
    ( Connection, connect, withEndpoint, endpoint
    , Param, text, int, float, bool, json, null, nullable
    , Query, select, selectOne, execute, map, run
    , Transaction, transaction, with, commit
    , Error(..), PostgresError, errorToString
    )

{-| Query a [Neon](https://neon.com) Postgres database over HTTP, the way Neon's
serverless driver (`@neondatabase/serverless`) does with `neon()`: each query, or each
transaction, is one HTTPS request, so it works where TCP connections don't, like
serverless functions.

    import Json.Decode as Decode
    import Neon

    type alias Todo =
        { id : String, title : String, done : Bool }

    todos : Neon.Query (List Todo)
    todos =
        Neon.select "SELECT id, title, done FROM todos WHERE done = $1"
            [ Neon.bool False ]
            (Decode.map3 Todo
                (Decode.field "id" Decode.string)
                (Decode.field "title" Decode.string)
                (Decode.field "done" Decode.bool)
            )

    load : Neon.Connection -> Cmd Msg
    load connection =
        Neon.run connection todos
            |> Task.attempt GotTodos

Requests go through `elm/http`. In the browser that just works. On a server runtime
without `XMLHttpRequest` (Bun, Node, Vercel Functions), import `api/_ts/xhr.ts` once
before starting Elm.

Keep the connection string on the server: it holds the database password.


# Connecting

@docs Connection, connect, withEndpoint, endpoint


# Parameters

Values for the `$1`, `$2`, ... placeholders. Like the official driver, they are sent as
Postgres text, and Postgres converts them to the column types.

@docs Param, text, int, float, bool, json, null, nullable


# Queries

@docs Query, select, selectOne, execute, map, run


# Transactions

@docs Transaction, transaction, with, commit


# Errors

@docs Error, PostgresError, errorToString

-}

import Http
import Json.Decode as Decode exposing (Decoder)
import Json.Encode as Encode
import Task exposing (Task)



-- CONNECTING


{-| A database to send queries to.
-}
type Connection
    = Connection
        { connectionString : String
        , endpoint : String
        }


{-| Read a connection string, like the `DATABASE_URL` Neon gives you:

    Neon.connect "postgresql://alex:secret@ep-cool-lake-123456.eu-central-1.aws.neon.tech/neondb?sslmode=require"

Queries go to the HTTP endpoint the official driver uses: the host with its first label
swapped for `api`, here `https://api.eu-central-1.aws.neon.tech/sql`.

-}
connect : String -> Result String Connection
connect connectionString =
    case hostOf connectionString of
        Just host ->
            Ok
                (Connection
                    { connectionString = connectionString
                    , endpoint = "https://" ++ apiHost host ++ "/sql"
                    }
                )

        Nothing ->
            Err "Expected a connection string like postgresql://user:password@host/database"


{-| Send queries to another endpoint, such as a local Neon proxy in development:

    Neon.connect "postgres://postgres:postgres@db.localtest.me:5432/main"
        |> Result.map (Neon.withEndpoint "http://db.localtest.me:4444/sql")

-}
withEndpoint : String -> Connection -> Connection
withEndpoint url (Connection c) =
    Connection { c | endpoint = url }


{-| The URL queries are sent to.
-}
endpoint : Connection -> String
endpoint (Connection c) =
    c.endpoint


hostOf : String -> Maybe String
hostOf connectionString =
    let
        rest =
            if String.startsWith "postgresql://" connectionString then
                Just (String.dropLeft 13 connectionString)

            else if String.startsWith "postgres://" connectionString then
                Just (String.dropLeft 11 connectionString)

            else
                Nothing

        authority =
            rest
                |> Maybe.andThen (String.split "/" >> List.head)
                |> Maybe.andThen (String.split "?" >> List.head)

        hostAndPort =
            authority
                |> Maybe.map (String.split "@" >> List.reverse >> List.head >> Maybe.withDefault "")
    in
    hostAndPort
        |> Maybe.andThen (String.split ":" >> List.head)
        |> Maybe.andThen
            (\host ->
                if String.isEmpty host then
                    Nothing

                else
                    Just host
            )


{-| `ep-cool-lake-123456.eu-central-1.aws.neon.tech` becomes
`api.eu-central-1.aws.neon.tech`, as in the official driver.
-}
apiHost : String -> String
apiHost host =
    case String.indexes "." host of
        first :: _ ->
            "api" ++ String.dropLeft first host

        [] ->
            host



-- PARAMETERS


{-| A query parameter.
-}
type Param
    = Param (Maybe String)


{-| -}
text : String -> Param
text value =
    Param (Just value)


{-| -}
int : Int -> Param
int value =
    Param (Just (String.fromInt value))


{-| -}
float : Float -> Param
float value =
    Param (Just (String.fromFloat value))


{-| -}
bool : Bool -> Param
bool value =
    Param
        (Just
            (if value then
                "true"

             else
                "false"
            )
        )


{-| For `json` and `jsonb` columns.
-}
json : Encode.Value -> Param
json value =
    Param (Just (Encode.encode 0 value))


{-| SQL `NULL`.
-}
null : Param
null =
    Param Nothing


{-| `NULL` for `Nothing`:

    Neon.nullable Neon.text todo.note

-}
nullable : (a -> Param) -> Maybe a -> Param
nullable toParam maybe =
    case maybe of
        Just value ->
            toParam value

        Nothing ->
            null


encodeParam : Param -> Encode.Value
encodeParam (Param value) =
    case value of
        Just string ->
            Encode.string string

        Nothing ->
            Encode.null



-- QUERIES


{-| A statement with its parameters, and what to make of its result.
-}
type Query a
    = Query
        { sql : String
        , params : List Param
        , toResult : Result_ -> Result String a
        }


{-| The parts of a result that queries read.
-}
type alias Result_ =
    { rows : Decode.Value
    , rowCount : Maybe Int
    }


{-| Every row, decoded. Each row is a JSON object with a field per column, so a decoder
you already have for the same shape works as is:

    Neon.select "SELECT id, title, done FROM todos" [] Todo.decoder

Neon converts the values to JSON:

  - `boolean` is a JSON boolean.
  - `smallint`, `integer`, `real` and `double precision` are numbers.
  - `json` and `jsonb` are the JSON they hold.
  - Arrays are JSON arrays.
  - `NULL` is `null`: use `Decode.nullable`.
  - Everything else is a string as Postgres prints it, including `bigint` and
    `numeric`, so they stay exact, and `timestamptz`.

If two columns have the same name, the row keeps the last one, so rename them with `AS`.

-}
select : String -> List Param -> Decoder a -> Query (List a)
select sql params decoder =
    Query
        { sql = sql
        , params = params
        , toResult =
            \result ->
                Decode.decodeValue (Decode.list decoder) result.rows
                    |> Result.mapError Decode.errorToString
        }


{-| The first row, if there is one.
-}
selectOne : String -> List Param -> Decoder a -> Query (Maybe a)
selectOne sql params decoder =
    select sql params decoder
        |> map List.head


{-| A statement run for its effect, like `INSERT`, `UPDATE` or `CREATE TABLE`. Gives the
number of rows it affected.
-}
execute : String -> List Param -> Query Int
execute sql params =
    Query
        { sql = sql
        , params = params
        , toResult = \result -> Ok (Maybe.withDefault 0 result.rowCount)
        }


{-| -}
map : (a -> b) -> Query a -> Query b
map f (Query q) =
    Query
        { sql = q.sql
        , params = q.params
        , toResult = q.toResult >> Result.map f
        }


{-| Send one query.
-}
run : Connection -> Query a -> Task Error a
run connection (Query q) =
    request connection
        (encodeQuery (Query q))
        (resultDecoder |> Decode.map q.toResult)


encodeQuery : Query a -> Encode.Value
encodeQuery (Query q) =
    Encode.object
        [ ( "query", Encode.string q.sql )
        , ( "params", Encode.list encodeParam q.params )
        ]


resultDecoder : Decoder Result_
resultDecoder =
    Decode.map2 Result_
        (Decode.field "rows" Decode.value)
        (Decode.maybe (Decode.field "rowCount" Decode.int))



-- TRANSACTIONS


{-| Queries that run together in one transaction: all of them commit, or none do.
-}
type Transaction a
    = Transaction
        { queries : List Encode.Value
        , toResult : List Result_ -> Result String ( a, List Result_ )
        }


{-| Start a transaction with a function that receives each query's result, in order:

    Neon.transaction (\_ todo -> todo)
        |> Neon.with (Neon.execute "UPDATE stats SET created = created + 1" [])
        |> Neon.with (Neon.selectOne "INSERT INTO todos (title) VALUES ($1) RETURNING id, title" [ Neon.text "Ship it" ] todoDecoder)
        |> Neon.commit connection

-}
transaction : a -> Transaction a
transaction value =
    Transaction
        { queries = []
        , toResult = \results -> Ok ( value, results )
        }


{-| Add a query to the transaction.
-}
with : Query a -> Transaction (a -> b) -> Transaction b
with (Query q) (Transaction t) =
    Transaction
        { queries = t.queries ++ [ encodeQuery (Query q) ]
        , toResult =
            \results ->
                t.toResult results
                    |> Result.andThen
                        (\( f, rest ) ->
                            case rest of
                                result :: remaining ->
                                    q.toResult result
                                        |> Result.map (\a -> ( f a, remaining ))

                                [] ->
                                    Err "The transaction returned fewer results than it had queries."
                        )
        }


{-| Send the transaction. If any query fails, Postgres rolls back all of them.
-}
commit : Connection -> Transaction a -> Task Error a
commit connection (Transaction t) =
    request connection
        (Encode.object [ ( "queries", Encode.list identity t.queries ) ])
        (Decode.field "results" (Decode.list resultDecoder)
            |> Decode.map (t.toResult >> Result.map Tuple.first)
        )



-- ERRORS


{-| -}
type Error
    = QueryFailed PostgresError
    | ServerError Int String
    | NetworkError
    | Timeout
    | BadUrl String
    | UnexpectedResult String


{-| Postgres rejected the query. `code` is the
[SQLSTATE](https://www.postgresql.org/docs/current/errcodes-appendix.html), like
`23505` for a unique violation.
-}
type alias PostgresError =
    { message : String
    , code : Maybe String
    , severity : Maybe String
    , detail : Maybe String
    , hint : Maybe String
    , table : Maybe String
    , column : Maybe String
    , constraint : Maybe String
    }


{-| -}
errorToString : Error -> String
errorToString error =
    case error of
        QueryFailed e ->
            e.message
                ++ (e.code |> Maybe.map (\code -> " (" ++ code ++ ")") |> Maybe.withDefault "")
                ++ (e.detail |> Maybe.map (\detail -> ". " ++ detail) |> Maybe.withDefault "")

        ServerError status body ->
            "Neon answered with HTTP " ++ String.fromInt status ++ ": " ++ body

        NetworkError ->
            "Could not reach Neon."

        Timeout ->
            "Neon took too long to answer."

        BadUrl url ->
            "Bad Neon endpoint: " ++ url

        UnexpectedResult message ->
            "Unexpected result: " ++ message


postgresErrorDecoder : Decoder PostgresError
postgresErrorDecoder =
    let
        optional name =
            Decode.maybe (Decode.field name Decode.string)
    in
    Decode.map8 PostgresError
        (Decode.field "message" Decode.string)
        (optional "code")
        (optional "severity")
        (optional "detail")
        (optional "hint")
        (optional "table")
        (optional "column")
        (optional "constraint")



-- HTTP


request : Connection -> Encode.Value -> Decoder (Result String a) -> Task Error a
request (Connection c) body decoder =
    Http.task
        { method = "POST"
        , headers =
            [ Http.header "Neon-Connection-String" c.connectionString
            , Http.header "Neon-Raw-Text-Output" "false"
            , Http.header "Neon-Array-Mode" "false"
            ]
        , url = c.endpoint
        , body = Http.jsonBody body
        , resolver = Http.stringResolver (resolve decoder)
        , timeout = Nothing
        }


resolve : Decoder (Result String a) -> Http.Response String -> Result Error a
resolve decoder response =
    case response of
        Http.GoodStatus_ _ body ->
            case Decode.decodeString decoder body of
                Ok (Ok value) ->
                    Ok value

                Ok (Err message) ->
                    Err (UnexpectedResult message)

                Err error ->
                    Err (UnexpectedResult (Decode.errorToString error))

        Http.BadStatus_ metadata body ->
            if metadata.statusCode == 400 then
                Decode.decodeString postgresErrorDecoder body
                    |> Result.map QueryFailed
                    |> Result.withDefault (ServerError 400 body)
                    |> Err

            else
                Err (ServerError metadata.statusCode body)

        Http.NetworkError_ ->
            Err NetworkError

        Http.Timeout_ ->
            Err Timeout

        Http.BadUrl_ url ->
            Err (BadUrl url)
