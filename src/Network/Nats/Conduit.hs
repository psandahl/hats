-- |
-- Module:      Network.Nats.Conduit
-- Copyright:   (c) 2016 Patrik Sandahl
-- License:     MIT
-- Maintainer:  Patrik Sandahl <patrik.sandahl@gmail.com>
-- Stability:   experimental
-- Portability: portable
--
-- 'Conduit' style helper functions.
module Network.Nats.Conduit
    ( Downstream
    , Upstream 
    , connectionSource
    , connectionSink
    , streamSource
    , streamSink
    , messageChunker
    , upstreamMessage
    ) where

import Control.Concurrent.STM (TQueue, atomically, readTQueue, writeTQueue)
import Control.DeepSeq (deepseq)
import Control.Monad (forever)
import Control.Monad.IO.Class (liftIO)
import Data.ByteString (ByteString)
import Data.Conduit (Conduit, Source, Sink, awaitForever, yield)

import Network.Nats.Message.Message (Message)
import Network.Nats.Message.Writer (writeMessage)

import qualified Data.ByteString.Lazy as LBS
import qualified Network.Connection as NC

-- | Downstream data from the client to the NATS server.
type Downstream = TQueue ByteString

-- | Upstream data from the NATS server to the client.
type Upstream = TQueue ByteString

-- | Source from a 'NC.Connection' to a 'ByteString'.
connectionSource :: NC.Connection -> Source IO ByteString
connectionSource c =
    forever $ yield =<< liftIO (NC.connectionGetChunk c)

-- | Sink a 'ByteString' to a 'NC.Connection'.
connectionSink :: NC.Connection -> Sink ByteString IO ()
connectionSink c = awaitForever $ 
    \chunk -> liftIO $ NC.connectionPut c chunk

-- | Source from an 'Upstream' to a 'ByteString'.
streamSource :: Upstream -> Source IO ByteString
streamSource stream =
    forever $ yield =<< liftIO (atomically $ readTQueue stream)

-- | Sink a 'ByteString' to a 'Downstream'.
streamSink :: Downstream -> Sink ByteString IO ()
streamSink stream = awaitForever $
    \chunk -> liftIO $ atomically $ writeTQueue stream chunk

-- | Take one 'Message', encode it and create chunks of it.
messageChunker :: Conduit Message IO ByteString
messageChunker = awaitForever $
    \msg -> mapM_ yield (LBS.toChunks $ writeMessage msg)

-- | Not really a conduit, but a pusher of 'Message' chunks to the
-- 'Upstream'.
upstreamMessage :: Upstream -> Message -> IO ()
upstreamMessage upstream msg = do
    -- Most likely there are different threads pushing messages upstream
    -- using this function. Force as much work as possible outside of
    -- the 'atomically' operations, to prevent contention on the TQueue.
    let chunks = LBS.toChunks $ writeMessage msg
    chunks `deepseq` upstreamMessage' chunks
    where
      upstreamMessage' :: [ByteString] -> IO ()
      upstreamMessage' chunks = 
          atomically $ mapM_ (writeTQueue upstream) chunks
{-# INLINE upstreamMessage #-}
