{-# LANGUAGE OverloadedStrings #-}

module Elm.Common where

import Control.Monad.RWS
import Data.Set (Set)
import qualified Data.Set as S
import Data.Text (Text)
import qualified Data.Text.Lazy as LT
import Formatting hiding (text)
import Text.PrettyPrint.Leijen.Text hiding ((<$>))

data Options = Options
  { fieldLabelModifier :: Text -> Text,
    -- | When True, decoders are tolerant of missing list fields and
    -- | will default them to an empty list []. This is helpful in supporting
    -- | third-party APIs that remove empty fields from the response.
    optionalListFields :: Bool
  }

defaultOptions :: Options
defaultOptions =
  Options
    { fieldLabelModifier = id,
      optionalListFields = False
    }

cr :: Format r r
cr = now "\n"

mintercalate
  :: Monoid m
  => m -> [m] -> m
mintercalate _ [] = mempty
mintercalate _ [x] = x
mintercalate seperator (x:xs) = x <> seperator <> mintercalate seperator xs

pprinter :: Doc -> Text
pprinter = LT.toStrict . displayT . renderPretty 0.4 100

stext :: Data.Text.Text -> Doc
stext = text . LT.fromStrict

spaceparens :: Doc -> Doc
spaceparens doc = "(" <+> doc <+> ")"

-- | Parentheses of which the right parenthesis exists on a new line
newlineparens :: Doc -> Doc
newlineparens doc = "(" <> doc <$$> ")"

-- | An empty line, regardless of current indentation
emptyline :: Doc
emptyline = nest minBound linebreak

-- | Like <$$>, but with an empty line in between
(<$+$>) :: Doc -> Doc -> Doc
l <$+$> r = l <> emptyline <$$> r

--
type RenderM = RWS Options (Set Text -- The set of required imports
                            , [Text] -- Generated declarations
                            ) Text

{-| Add an import to the set.
-}
require :: Text -> RenderM ()
require dep = tell (S.singleton dep, [])

{-| Take the result of a RenderM computation and put it into the Writer's
declarations.
-}
collectDeclaration :: RenderM Doc -> RenderM ()
collectDeclaration =
  mapRWS ((\(defn, s, (imports, _)) -> ((), s, (imports, [pprinter defn]))))

squarebracks :: Doc -> Doc
squarebracks doc = "[" <+> doc <+> "]"

pair :: Doc -> Doc -> Doc
pair l r = spaceparens $ l <> comma <+> r

letIn :: [(Text, Doc)] -> Doc -> Doc
letIn vars body =
  align $
    vsep
      [ "let",
        indent 4 $ vsep $ renderVariable <$> vars,
        "in",
        body
      ]
  where
    renderVariable :: (Text, Doc) -> Doc
    renderVariable (name, value) =
      vsep
        [ pretty name <+> "=",
          indent 4 value
        ]
