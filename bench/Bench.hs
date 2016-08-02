{-# LANGUAGE OverloadedStrings #-}
module Main
    ( main
    ) where

import Control.Monad (replicateM_, void)
import Control.Concurrent.Async (async, wait)
import Control.Concurrent.STM ( STM, TVar, atomically, modifyTVar
                              , newTVarIO, readTVar, retry
                              )
import Criterion.Main ( Benchmark, defaultMain, bgroup, bench
                      , env, nf, whnfIO
                      )
import Data.Attoparsec.ByteString.Char8 (IResult (..), Result, parse)
import Data.ByteString.Lazy.Builder (lazyByteString, toLazyByteString)

import Network.Nats
import Network.Nats.Message.Message (Message (..))
import Network.Nats.Message.Parser (parseMessage)
import Network.Nats.Message.Writer (writeMessage)

import qualified Data.ByteString.Char8 as BS
import qualified Data.ByteString.Lazy.Char8 as LBS

main :: IO ()
main = defaultMain suite

suite :: [Benchmark]
suite =
    [ bgroup "pub-writer"
        [ env smallPubMessages $ \xs ->
            bench "million * 48 bytes" $ nf writePubs xs

        , env mediumPubMessages $ \xs ->
            bench "million * 480 bytes" $ nf writePubs xs

        , env largePubMessages $ \xs ->
            bench "million * 4800 bytes" $ nf writePubs xs
        ]
    , bgroup "msg-parser"
        [ env smallMsgMessages $ \xs ->
            bench "million * 48 bytes" $ nf parseMsgs xs

        , env mediumMsgMessages $ \xs ->
            bench "million * 480 bytes" $ nf parseMsgs xs

        , env largeMsgMessages $ \xs ->
            bench "million * 4800 bytes" $ nf parseMsgs xs
        ]
    , bgroup "pubsub-nats"
        [ bench "million pub" $ whnfIO (pubPerf million)
        , bench "100000 pubsub/queue" $ whnfIO (pubSubPerf a100000)
        , bench "100000 pubsub/async" $ whnfIO (pubSubAsyncPerf a100000)
        ]
    ]

-- | Write a list of Pub messages to a list of lazy ByteStrings.
writePubs :: [Message] -> [LBS.ByteString]
writePubs = map writeMessage

-- | Parse a list of ByteStrings to a list of Msg messages.
parseMsgs :: [BS.ByteString] -> [Message]
parseMsgs = map (fromResult . parse parseMessage)
    where
      fromResult :: Result Message -> Message
      fromResult (Done _ msg)   = msg
      fromResult (Partial cont) = fromResult (cont "")
      fromResult _              = error "Shall not happen"

-- | Send the given number of Pub messages containing the payload "hello".
-- This benchmark requires a running NATS server.
pubPerf :: Int -> IO ()
pubPerf rep =
    withNats defaultManagerSettings [defaultURI] $ \nats ->
        replicateM_ rep $ publish nats "bench" Nothing "hello"

pubSubPerf :: Int -> IO ()
pubSubPerf rep =
    withNats defaultManagerSettings [defaultURI] $ \nats -> do
        (_, queue) <- subscribe nats "bench" Nothing
        rec <- async $ receiver queue rep

        replicateM_ rep $ publish nats "bench" Nothing "hello"
        wait rec

receiver :: MsgQueue -> Int -> IO ()
receiver queue limit = go 0
    where
      go :: Int -> IO ()
      go cnt
        | cnt == limit = return ()
        | otherwise    = do
            void $ nextMsg queue
            go (cnt + 1)

-- | Send the given number of Pub messages containing the payload "hello"
-- Subscribe to and receive - using asyncronous subscription - the 
-- same number of messages.
-- This benchmark requires a running NATS server.
pubSubAsyncPerf :: Int -> IO ()
pubSubAsyncPerf rep =
    withNats defaultManagerSettings [defaultURI] $ \nats -> do
        cnt <- newTVarIO 0
        void $ subscribeAsync nats "bench" Nothing $ asyncReceiver cnt
        replicateM_ rep $ publish nats "bench" Nothing "hello"

        atomically $ waitForValue cnt rep

asyncReceiver :: TVar Int -> Msg -> IO ()
asyncReceiver cnt _ = atomically $ modifyTVar cnt (+ 1)

waitForValue :: TVar Int -> Int -> STM ()
waitForValue tvar value = do
    value' <- readTVar tvar
    if value' /= value
        then retry
        else return ()

million :: Int
million = 1000000

a100000 :: Int
a100000 = 100000

small :: Int
small = 1

medium :: Int
medium = 10

large :: Int
large = 100

smallPubMessages :: IO [Message]
smallPubMessages = million `pubMessages` small

mediumPubMessages :: IO [Message]
mediumPubMessages = million `pubMessages` medium

largePubMessages :: IO [Message]
largePubMessages = million `pubMessages` large

smallMsgMessages :: IO [BS.ByteString]
smallMsgMessages = million `msgMessages` small

mediumMsgMessages :: IO [BS.ByteString]
mediumMsgMessages = million `msgMessages` medium

largeMsgMessages :: IO [BS.ByteString]
largeMsgMessages = million `msgMessages` large

pubMessages :: Int -> Int -> IO [Message]
pubMessages rep size = return $ replicate rep (pubMessage size)

msgMessages :: Int -> Int -> IO [BS.ByteString]
msgMessages rep size = do
    let xs = replicate rep (msgMessage size)
    return $ map (LBS.toStrict . writeMessage) xs

pubMessage :: Int -> Message
pubMessage = PUB "TOPIC.INBOX" (Just "REPLY.INBOX") . replicatePayload

msgMessage :: Int -> Message
msgMessage = 
    MSG "TOPIC.INBOX" 123456 (Just "REPLY.INBOX") . replicatePayload

replicatePayload :: Int -> LBS.ByteString
replicatePayload n =
    let p = map lazyByteString $ replicate n payloadChunk
    in toLazyByteString $ mconcat p

-- | A basic "random" payload chunk with 48 characters.
payloadChunk :: LBS.ByteString
payloadChunk = "pq01ow92ie83ue74ur74yt65jf82nc8emr8dj48v.dksme2z"

defaultURI :: String
defaultURI = "nats://localhost:4222"
