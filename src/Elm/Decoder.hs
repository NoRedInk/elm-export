{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE InstanceSigs #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeOperators #-}

module Elm.Decoder
  ( toElmDecoderRef,
    toElmDecoderRefWith,
    toElmDecoderSource,
    toElmDecoderSourceWith,
    renderDecoder,
  )
where

import Control.Monad.RWS
import qualified Data.Text as T
import Elm.Common
import qualified Elm.Sorter as Sorter
import Elm.Type
import Text.PrettyPrint.Leijen.Text hiding ((<$>))

class HasDecoder a where
  render :: a -> RenderM Doc

class HasDecoderRef a where
  renderRef :: a -> RenderM Doc

instance HasDecoder ElmDatatype where
  render d@(ElmDatatype name constructor) = do
    fnName <- renderRef d
    put (displayTStrict $ renderCompact fnName)
    ctor <- render constructor
    return $
      (fnName <+> ": Decoder" <+> stext name)
        <$$> (fnName <+> "=" <$$> indent 4 ctor)
  render (ElmPrimitive primitive) = renderRef primitive
  render (CreatedInElm _) = pure $ stext ""

instance HasDecoderRef ElmDatatype where
  renderRef (ElmDatatype name _) = do
    let decoderFunctionName = "decode" <> name
    topFunctionName <- get
    if topFunctionName == decoderFunctionName
      then pure ("(lazy (\\() -> " <> stext topFunctionName <> "))")
      else pure $ stext decoderFunctionName
  renderRef (ElmPrimitive primitive) = renderRef primitive
  renderRef (CreatedInElm elmRefData) = pure $ stext (decoderFunction elmRefData)

instance HasDecoder ElmConstructor where
  render (NamedConstructor name ElmEmpty) =
    return $ "succeed" <+> stext name
  render (NamedConstructor name value) = do
    dv <- render value
    return $ dv <$$> indent 4 ("|> map" <+> stext name)
  render (RecordConstructor name value False) = do
    dv <- render value
    return $ "succeed" <+> stext name <$$> indent 4 dv
  render (RecordConstructor name value True) = do
    dv <- render value
    return $ "succeed" <+> "(" <> printRecordConstructorFunction name value <> ")" <$$> indent 4 dv
  render mc@(MultipleConstructors constrs) = do
    cstrs <- mapM renderSum constrs
    pure $
      constructorName
        <$$> indent
          4
          ( "|> andThen"
              <$$> indent
                4
                ( newlineparens
                    ( "\\x ->"
                        <$$> ( indent 4 $
                                 "case x of"
                                   <$$> ( indent 4 $
                                            foldl1 (<$+$>) cstrs
                                              <$+$> "_ ->"
                                              <$$> indent 4 "fail \"Constructor not matched\""
                                        )
                             )
                    )
                )
          )
    where
      constructorName :: Doc
      constructorName =
        if isEnumeration mc then "string" else "field \"tag\" string"

listRecordConstructors :: ElmValue -> [T.Text]
listRecordConstructors (ElmField name _) = [name]
listRecordConstructors (Values x y) = listRecordConstructors x ++ listRecordConstructors y
listRecordConstructors _ = []

printRecordConstructorFunction :: T.Text -> ElmValue -> Doc
printRecordConstructorFunction name value =
  "\\" <> hsep (stext <$> listRecordConstructors value) <+> "->" <+> stext name <+> braces (hsep $ punctuate "," (printField <$> listRecordConstructors value))
  where
    printField :: T.Text -> Doc
    printField field = stext field <+> "=" <+> stext field

-- | required "contents"
requiredContents :: Doc
requiredContents = "required" <+> dquotes "contents"

-- | "<name>" -> decode <name>
renderSumCondition :: T.Text -> Doc -> RenderM Doc
renderSumCondition name contents =
  pure $
    dquotes (stext name) <+> "->"
      <$$> indent
        4
        ("succeed" <+> stext name <$$> indent 4 contents)

-- | Render a sum type constructor in context of a data type with multiple
-- constructors.
renderSum :: ElmConstructor -> RenderM Doc
renderSum (NamedConstructor name ElmEmpty) = renderSumCondition name mempty
renderSum (NamedConstructor name v@(Values _ _)) = do
  (_, val) <- renderConstructorArgs 0 v
  renderSumCondition name val
renderSum (NamedConstructor name value) = do
  val <- render value
  renderSumCondition name $ "|>" <+> requiredContents <+> val
renderSum (RecordConstructor name value _) = do
  val <- render value
  renderSumCondition name val
renderSum (MultipleConstructors constrs) =
  foldl1 (<$+$>) <$> mapM renderSum constrs

-- | Render the decoding of a constructor's arguments. Note the constructor must
-- be from a data type with multiple constructors and that it has multiple
-- constructors itself.
renderConstructorArgs :: Int -> ElmValue -> RenderM (Int, Doc)
renderConstructorArgs i (Values l r) = do
  (iL, rndrL) <- renderConstructorArgs i l
  (iR, rndrR) <- renderConstructorArgs (iL + 1) r
  pure (iR, rndrL <$$> rndrR)
renderConstructorArgs i val = do
  rndrVal <- case val of
    ElmPrimitiveRef (ESortDict {}) -> do
      rnd <- render val
      pure $ linebreak <> indent 4 rnd
    _ -> do
      rnd <- render val
      pure $ space <> rnd
  let index = parens $ "index" <+> int i <> rndrVal
  pure (i, "|>" <+> requiredContents <+> index)

instance HasDecoder ElmValue where
  render (ElmRef elmRefData) = do
    topFunctionName <- get
    let decoderFunctionName = decoderFunction elmRefData
    if topFunctionName == decoderFunctionName
      then pure ("(lazy (\\() -> " <> stext topFunctionName <> "))")
      else pure $ stext decoderFunctionName
  render (ElmPrimitiveRef primitive) = renderRef primitive
  render (Values x y) = do
    dx <- render x
    dy <- render y
    return $ dx <$$> dy
  render (ElmField name value) = do
    fieldModifier <- asks fieldLabelModifier
    optionalListFields' <- asks optionalListFields
    dv <- render value
    let isList = case value of
          (ElmPrimitiveRef (EList value'))
            | value' /= (ElmPrimitive EChar) -> True
          _ -> False
    if isList && optionalListFields'
      then return $ "|> optional" <+> dquotes (stext (fieldModifier name)) <+> dv <+> "[]"
      else return $ "|> required" <+> dquotes (stext (fieldModifier name)) <+> dv
  render ElmEmpty = pure (stext "")

instance HasDecoderRef ElmPrimitive where
  renderRef :: ElmPrimitive -> RenderM Doc
  renderRef (EList (ElmPrimitive EChar)) = pure "string"
  renderRef (EList datatype) = do
    dt <- renderRef datatype
    return . parens $ "list" <+> dt
  renderRef (EDict EString value) = do
    require "Dict"
    d <- renderRef value
    return . parens $ "dict" <+> d
  renderRef (EDict EInt value) = do
    require "Dict"
    require "Json.Decode.Extra"
    d <- renderRef value
    return . parens $ "Json.Decode.Extra.dict2 int" <+> d
  renderRef (EDict EFloat value) = do
    require "Dict"
    require "Json.Decode.Extra"
    d <- renderRef value
    return . parens $ "Json.Decode.Extra.dict2 float" <+> d
  renderRef (EDict key value) = do
    require "Dict"
    d <- renderRef (EList (ElmPrimitive (ETuple2 (ElmPrimitive key) value)))
    return . parens $ "map Dict.fromList" <+> d
  renderRef (ESortDict sorter encoding key value) = do
    require "Sort.Dict"
    require "Sort.Dict.Extra" -- This is from our monolith, should we move it to an elm-package?
    keyDecoder <- renderRef key
    valueDecoder <- renderRef value
    pure $
      parens
        ( letIn
            [renderedSorter]
            (decodingFunction <+> "sorter" <+> parens keyDecoder <+> parens valueDecoder)
        )
    where
      renderedSorter =
        ("sorter", Sorter.render sorter)
      decodingFunction :: Doc
      decodingFunction =
        case encoding of
          List -> "Sort.Dict.Extra.decode"
          Object -> "Sort.Dict.Extra.decodeFromObject"
  renderRef (ESet datatype) = do
    require "Set"
    d <- renderRef (EList (ElmPrimitive datatype))
    return . parens $ "map Set.fromList" <+> d
  renderRef (ESortSet sorter datatype) = do
    require "Sort.Set"
    dd <- renderRef (EList datatype)
    pure $
      parens
        ( letIn
            [renderedSorter]
            ("map (Sorter.Set.fromList sorter)" <+> dd)
        )
    where
      renderedSorter =
        ("sorter", Sorter.render sorter)
  renderRef (EMaybe datatype) = do
    dt <- renderRef datatype
    return . parens $ "nullable" <+> dt
  renderRef (ETuple2 x y) = do
    dx <- renderRef x
    dy <- renderRef y
    return . parens $
      "map2 Tuple.pair" <+> parens ("index 0" <+> dx) <+> parens ("index 1" <+> dy)
  renderRef EUnit = pure $ parens "succeed ()"
  renderRef ETimePosix = pure "Iso8601.decoder"
  renderRef EInt = pure "int"
  renderRef EBool = pure "bool"
  renderRef EChar = pure "char"
  renderRef EFloat = pure "float"
  renderRef EString = pure "string"
  renderRef EJsonValue = pure "value"

toElmDecoderRefWith ::
  (ElmType a) =>
  Options ->
  a ->
  T.Text
toElmDecoderRefWith options x =
  pprinter . fst $ evalRWS (renderRef (toElmType x)) options ""

toElmDecoderRef ::
  (ElmType a) =>
  a ->
  T.Text
toElmDecoderRef = toElmDecoderRefWith defaultOptions

toElmDecoderSourceWith ::
  (ElmType a) =>
  Options ->
  a ->
  T.Text
toElmDecoderSourceWith options x =
  pprinter . fst $ evalRWS (render (toElmType x)) options ""

toElmDecoderSource ::
  (ElmType a) =>
  a ->
  T.Text
toElmDecoderSource = toElmDecoderSourceWith defaultOptions

renderDecoder ::
  (ElmType a) =>
  a ->
  RenderM ()
renderDecoder x = do
  require "Json.Decode exposing (..)"
  require "Json.Decode.Pipeline exposing (..)"
  collectDeclaration . render . toElmType $ x
