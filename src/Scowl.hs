{-# LANGUAGE OverloadedStrings #-}

module Scowl
  ( loadWordsFromScowl
  , writeWordsToFile
  , filterResults
  , fromInt
  , Size(..)
  ) where

import           Control.Monad
import           Data.List            (sort)
import           Data.Set             as Set
import           System.IO

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

toInt :: Size -> Int
toInt size = read $ drop 1 (show size)

fromInt :: Int -> Size
fromInt int = read $ "S" ++ show int

filterResults :: String -> Set String -> Set String -> [String]
filterResults bq results scowlList = do
  result <- elems results
  let rWords = words result
  let bqWords = words bq
  guard $
    (length rWords <= length bqWords + 1) &&
    (bq == head rWords) &&
    Set.null (fromList (tail rWords) \\ scowlList) &&
    (init result `notElem` results)
  pure result

loadWordsFromScowl :: Size -> IO [Set String]
loadWordsFromScowl size = traverse loadWordsFromFile (enumFromTo S10 size)

loadWordsFromFile :: Size -> IO (Set String)
loadWordsFromFile size = do
  let fileName = "./scowl/final/english-words." ++ show (toInt size)
  fileContents <- readFile fileName
  pure $ fromList $ lines fileContents

writeWordsToFile :: String -> [String] -> IO [()]
writeWordsToFile baseQuery ws =
  sequence $ do
    let fileName = "./output/" ++ baseQuery ++ show (length ws) ++ ".txt"
    word <- sort ws
    pure $ appendFile fileName (word ++ "\n")
