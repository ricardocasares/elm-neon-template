module Neon exposing
    ( Connection, connect, withEndpoint, endpoint
    , Param, text, int, float, bool, json, null, nullable
    , Query, select, selectOne, execute, map, run
    , Transaction, transaction, with, commit
    , Error(..), PostgresError, errorToString
    )

import Http
import Json.Decode as Decode exposing (Decoder)
import Json.Encode as Encode
import Task exposing (Task)



-- CONNECTING


type Connection
    = Connection
        { connectionString : String
        , endpoint : String
        }


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


withEndpoint : String -> Connection -> Connection
withEndpoint url (Connection c) =
    Connection { c | endpoint = url }


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


apiHost : String -> String
apiHost host =
    case String.indexes "." host of
        first :: _ ->
            "api" ++ String.dropLeft first host

        [] ->
            host



-- PARAMETERS


type Param
    = Param (Maybe String)


text : String -> Param
text value =
    Param (Just value)


int : Int -> Param
int value =
    Param (Just (String.fromInt value))


float : Float -> Param
float value =
    Param (Just (String.fromFloat value))


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


json : Encode.Value -> Param
json value =
    Param (Just (Encode.encode 0 value))


null : Param
null =
    Param Nothing


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


type Query a
    = Query
        { sql : String
        , params : List Param
        , toResult : Result_ -> Result String a
        }


type alias Result_ =
    { rows : Decode.Value
    , rowCount : Maybe Int
    }


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


selectOne : String -> List Param -> Decoder a -> Query (Maybe a)
selectOne sql params decoder =
    select sql params decoder
        |> map List.head


execute : String -> List Param -> Query Int
execute sql params =
    Query
        { sql = sql
        , params = params
        , toResult = \result -> Ok (Maybe.withDefault 0 result.rowCount)
        }


map : (a -> b) -> Query a -> Query b
map f (Query q) =
    Query
        { sql = q.sql
        , params = q.params
        , toResult = q.toResult >> Result.map f
        }


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


type Transaction a
    = Transaction
        { queries : List Encode.Value
        , toResult : List Result_ -> Result String ( a, List Result_ )
        }


transaction : a -> Transaction a
transaction value =
    Transaction
        { queries = []
        , toResult = \results -> Ok ( value, results )
        }


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


commit : Connection -> Transaction a -> Task Error a
commit connection (Transaction t) =
    request connection
        (Encode.object [ ( "queries", Encode.list identity t.queries ) ])
        (Decode.field "results" (Decode.list resultDecoder)
            |> Decode.map (t.toResult >> Result.map Tuple.first)
        )



-- ERRORS


type Error
    = QueryFailed PostgresError
    | ServerError Int String
    | NetworkError
    | Timeout
    | BadUrl String
    | UnexpectedResult String


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
