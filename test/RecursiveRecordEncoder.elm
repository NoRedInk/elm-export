module RecursiveRecordEncoder exposing (..)

import Json.Encode


encodeRecursiveRecord : RecursiveRecord -> Json.Encode.Value
encodeRecursiveRecord (RecursiveRecord x) =
    Json.Encode.object
        [ ( "rec", (Maybe.withDefault Json.Encode.null << Maybe.map encodeRecursiveRecord) x.rec )
        , ( "otherField", Json.Encode.string x.otherField )
        ]
