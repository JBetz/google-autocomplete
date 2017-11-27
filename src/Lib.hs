{-# LANGUAGE OverloadedStrings #-}

module Lib
  ( autocomplete
  , recursiveAutocomplete
  ) where

import           Control.Concurrent
import           Control.Exception
import           Control.Lens
import           Data.Aeson           (eitherDecode)
import           Data.ByteString.Lazy (ByteString)
import           Data.List            (isSuffixOf, sort, union)
import qualified Data.Set             as S
import           Data.Text            (pack)
import           Network.HTTP.Client  (HttpException)
import           Network.Wreq

alphabet :: String
alphabet = "abcdefghijklmnopqrstuvwxyz"

recursiveAutocomplete :: String -> IO [String]
recursiveAutocomplete query = do
  (_, initialResults) <- autocomplete query
  results <- runRecAutocomplete (query ++ " ")
  pure $ sort (initialResults `union` results)

runRecAutocomplete :: String -> IO [String]
runRecAutocomplete query = do
  print query
  results <- sequence $ fmap autocompleteWithRetry (expandQuery query)
  recResults <- sequence $ fmap runRecAutocomplete (findExpandables results)
  pure $ concatMap snd results `union` concat recResults

autocompleteWithRetry :: String -> IO (String, [String])
autocompleteWithRetry query =
  catch
    (autocomplete query)
    (\e -> do
       print (e :: HttpException)
       msThreadDelay 30000
       autocomplete query)

autocomplete :: String -> IO (String, [String])
autocomplete query = do
  let opts = defaults & param "q" .~ [pack query] & param "client" .~ ["firefox"]
  response <- getWith opts "https://www.google.com/complete/search"
  pure $ parseResponse (response ^. responseBody) query

expandQuery :: String -> [String]
expandQuery baseQuery =
  let isValid q = not ("  " `isSuffixOf` q)
  in filter isValid (fmap (snoc baseQuery) alphabet)

findExpandables :: [(String, [String])] -> [String]
findExpandables results =
  fmap fst (filter (\result -> length (snd result) == 10) results)

parseResponse :: ByteString -> String -> (String, [String])
parseResponse response def =
  case eitherDecode response :: Either String (String, [String]) of
    Left err          -> (def, [])
    Right (key, vals) -> (key, vals)

msThreadDelay :: Int -> IO ()
msThreadDelay ms = threadDelay $ ms * 1000
