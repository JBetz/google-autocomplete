{-# LANGUAGE OverloadedStrings #-}

module Scowl
  ( loadWordSets
  , filterResults
  , findExceptionalResults
  , fromInt
  , Size(..)
  ) where

import Control.Monad
import Data.Set (Set, (\\), fromList, null)
import Model
import Prelude hiding (null)

data Size
  = S10
  | S20
  | S35
  | S40
  | S50
  | S55
  | S60
  | S70
  | S80
  | S95
  deriving (Read, Enum, Show)

wordSetNames :: [String]
wordSetNames = ["english-words", "american-words", "british-words"]

toInt :: Size -> Int
toInt size = read $ drop 1 (show size)

fromInt :: Int -> Size
fromInt int = read $ "S" ++ show int

filterResults :: Query -> [String] -> Size -> IO [[String]]
filterResults bq results size = do
  scowlSets <- loadWordSets size
  pure $ fmap (filterResultsWith bq results) scowlSets

filterResultsWith :: Query -> [String] -> Set String -> [String]
filterResultsWith bq results scowlSet =
  let bqWords = words (show bq)
  in do result <- results
        guard $
          ((length . words) result <= length bqWords + 1) &&
          (bq `matches` result) &&
          null (fromList (difference bq result) \\ scowlSet) &&
          (init result `notElem` results)
        pure result

findExceptionalResults :: Query -> [(String, String)] -> [String] -> [String]
findExceptionalResults bq allResults filteredResults =
  snd <$>
  filter
    (\(query, result) ->
       let rWords = words result
       in (bq `matches` result) &&
          length rWords == 2 &&
          length query <= 2 && 
          result `notElem` filteredResults
    )
    allResults

loadWordSets :: Size -> IO [Set String]
loadWordSets size = traverse loadWordSet (enumFromTo S10 size)

loadWordSet :: Size -> IO (Set String)
loadWordSet size = do
  let fileNames =
        fmap
          (\name -> "./scowl/final/" ++ name ++ "." ++ show (toInt size))
          wordSetNames
  fileContents <- traverse readFile fileNames
  pure $ fromList (join $ fmap lines fileContents)
