{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeFamilies #-}

module Storage
  ( ResultsField(..)
  , createQueriesTable
  , createResultsTable
  , connStr
  , insertResultList
  , selectAllResults
  , selectUniqueResults
  , selectQueryResults
  , ranQuery
  , writeFilteredWordsToFile
  , writeExceptionalWordsToFile
  ) where

import Config
import Control.Monad.Reader
import Data.Char (isAscii)
import Data.List (sort)
import Data.Map (assocs, fromList)
import Data.String (fromString)
import Data.Text (Text, unpack)
import Data.Tuple (swap)
import Database.SQLite.Simple as SQL hiding (Query)
import Filter
import Model hiding (fromString)
import System.Directory (createDirectoryIfMissing)


-- DATABASE
data QueriesField =
  QueriesField Int
               Text
               Text
               Text
  deriving (Show)

data ResultsField =
  ResultsField Int
               Text
               Text
  deriving (Show)

instance FromRow ResultsField where
  fromRow = ResultsField <$> field <*> field <*> field

instance ToRow ResultsField where
  toRow (ResultsField id_ q r) = toRow (id_, q, r)

instance FromRow QueriesField where
  fromRow = QueriesField <$> field <*> field <*> field <*> field

connStr :: String
connStr = "file:./output/database.db"

createQueriesTable :: App ()
createQueriesTable = do
  (Config bq conn) <- ask
  liftIO $
    execute_
      conn
      (fromString $
       "CREATE TABLE IF NOT EXISTS " ++
       show_ bq ++
       "_queries (id INTEGER PRIMARY KEY, structure TEXT, base TEXT, expansion TEXT UNIQUE)")

createResultsTable :: App ()
createResultsTable = do
  (Config bq conn) <- ask
  liftIO $
    execute_
      conn
      (fromString $
       "CREATE TABLE IF NOT EXISTS " ++
       show_ bq ++
       "_results (id INTEGER PRIMARY KEY, query TEXT, result TEXT)")

insertResultList :: (Query, [String]) -> App [()]
insertResultList result = do
  _ <- insertQuery (fst result)
  traverse (insertResult (fst result)) (snd result)

insertQuery :: Query -> App ()
insertQuery (Query b e s) = do
  (Config bq conn) <- ask
  liftIO $
    execute
      conn
      (fromString $
       "INSERT OR IGNORE INTO " ++
       show_ bq ++ "_queries (structure, base, expansion) VALUES (?, ?, ?)")
      [show s, b, e]

insertResult :: Query -> String -> App ()
insertResult q result = do
  (Config bq conn) <- ask
  liftIO $
    execute
      conn
      (fromString $
       "INSERT OR IGNORE INTO " ++
       show_ bq ++ "_results (query, result) VALUES (?, ?)")
      [show q, result]

selectUniqueResults :: App [(String, String)]
selectUniqueResults = do
  totalResults <- selectAllResults
  let resultPairs = fmap (\(ResultsField _ eq v) -> (unpack eq, unpack v)) totalResults
  let resultMap = fromList $ fmap swap resultPairs
  pure $ fmap swap (assocs resultMap)

selectAllResults :: App [ResultsField]
selectAllResults = do
  (Config bq conn) <- ask
  liftIO $ query_ conn (fromString $ "SELECT * FROM " ++ show_ bq ++ "_results")

ranQuery :: Query -> App Bool
ranQuery (Query _ e _) = do
  (Config bq conn) <- ask
  liftIO $ do
    res <-
      SQL.query
        conn
        (fromString $ "SELECT * FROM " ++ show_ bq ++ "_queries WHERE expansion = ?")
        [e] :: IO [QueriesField]
    pure $ not (null res)

selectQueryResults :: Query -> App (Query, [String])
selectQueryResults q = do
  (Config bq conn) <- ask
  liftIO $ do
    res <-
      SQL.query
        conn
        (fromString $ "SELECT * FROM " ++ show_ bq ++ "_results WHERE query = ?")
        [show q] :: IO [ResultsField]
    pure (q, fmap (\(ResultsField _ _ v) -> unpack v) res)

-- FILE 
writeFilteredWordsToFile :: Query -> [FilteredResultSet] -> IO [[()]]
writeFilteredWordsToFile q frs = do
  _ <- createDirectoryIfMissing False ("./output/" ++ show_ q)
  traverse (writeFilteredResultSetToFile q) frs

writeFilteredResultSetToFile :: Query -> FilteredResultSet -> IO [()]
writeFilteredResultSetToFile q (FilteredResultSet rl ss ws) =
  let filePath =
        outputFilePath
          q
          ("length=" ++ show rl)
          [ ("scowlSize", show ss)
          , ("count", show (length ws))
          ]
  in do 
    _ <- createDirectoryIfMissing False ("./output/" ++ show_ q ++ "/length=" ++ show rl)
    writeWordsToFile filePath ws

writeExceptionalWordsToFile :: Query -> [String] -> IO [()]
writeExceptionalWordsToFile q ws =
  let filePath = outputFilePath q "exceptional" [("count", show (length ws))]
  in do 
    _ <- createDirectoryIfMissing False ("./output/" ++ show_ q ++ "/exceptional")
    writeWordsToFile filePath ws

writeWordsToFile :: String -> [String] -> IO [()]
writeWordsToFile filePath ws =
  sequence $ do
    word <- sort ws
    pure $ appendFile filePath (filter isAscii word ++ "\n")

outputFilePath :: Query -> String -> [(String, String)] -> String
outputFilePath q subDir metaData =
  "./output/" ++
  show_ q ++
  "/" ++ 
  subDir ++
  "/" ++
  show_ q ++
  "-" ++
  tail (concatMap (\(k, v) -> "_" ++ k ++ "=" ++ v) metaData) ++ ".txt"
