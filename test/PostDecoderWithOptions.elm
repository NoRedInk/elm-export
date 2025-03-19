module PostDecoderWithOptions exposing (..)

import CommentDecoder exposing (..)
import Json.Decode exposing (..)
import Json.Decode.Pipeline exposing (..)
import PostType exposing (..)


decodePost : Decoder Post
decodePost =
    succeed Post
        |> required "postId" int
        |> required "postName" string
        |> optional "postAge" (nullable float) Nothing
        |> optional "postComments" (list decodeComment) []
        |> required "postPromoted" (nullable decodeComment)
        |> optional "postAuthor" (nullable string) Nothing
