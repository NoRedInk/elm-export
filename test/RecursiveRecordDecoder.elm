module RecursiveRecordDecoder exposing (..)

import CommentDecoder exposing (..)
import Json.Decode exposing (..)
import Json.Decode.Pipeline exposing (..)


decodeRecursiveRecord : Decoder RecursiveRecord
decodeRecursiveRecord =
    succeed (\rec otherField -> RecursiveRecord {rec = rec, otherField = otherField})
        |> required "rec" (nullable decodeRecursiveRecord)
        |> required "otherField" string
