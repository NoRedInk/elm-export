module RecursiveRecordType exposing (..)


type RecursiveRecord
    = RecursiveRecord
        { rec : Maybe (RecursiveRecord)
        , otherField : String
        }
