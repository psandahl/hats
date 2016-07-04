{-# LANGUAGE TupleSections #-}
-- | Abstraction for a connection towards a NATS server. It owns the
-- networking stuff and performs NATS handshaking necessary.
module Network.Nats.Connection
    ( Connection
    , makeConnection
    , waitForShutdown
    ) where

import Control.Concurrent.Async (Async, async, waitAnyCatchCancel)
import Control.Exception
import Control.Monad (void)
import Control.Monad.IO.Class (liftIO)
import Data.ByteString (ByteString)
import Data.Conduit
import Data.Maybe (fromJust)
import Network.Socket
import Network.URI

import qualified Network.Connection as NC

data Connection = Connection
    { connection :: !NC.Connection
    , fromNet    :: !(Async ())
    , toNet      :: !(Async ())
    }

makeConnection :: URI
               -> Source IO ByteString
               -> Sink ByteString IO ()
               -> IO (Maybe Connection)
makeConnection uri fromApp toApp =
    socketError `handle` (Just <$> makeConnection' uri fromApp toApp)
    where
      socketError :: SomeException -> IO (Maybe Connection)
      socketError e
        | isConnectionRefused e = return Nothing
        | otherwise             = throwIO e

isConnectionRefused :: SomeException -> Bool
isConnectionRefused e =
    show e == "connect: does not exist (Connection refused)"

makeConnection' :: URI
               -> Source IO ByteString
               -> Sink ByteString IO () 
               -> IO Connection
makeConnection' uri fromApp toApp = do
    -- Make the connection.
    ctx  <- NC.initConnectionContext
    conn <- NC.connectTo ctx $
        NC.ConnectionParams
            { NC.connectionHostname  = hostFromUri uri
            , NC.connectionPort      = portFromUri uri
            , NC.connectionUseSocks  = Nothing
            , NC.connectionUseSecure = Nothing
            }

    -- Now start the pipeline threads and return the Connection
    -- record.
    Connection conn <$> (async $ connectionSource conn $$ toApp)
                    <*> (async $ fromApp $$ connectionSink conn)

connectionSource :: NC.Connection -> Source IO ByteString
connectionSource c = go
    where
      go = do
        yield =<< (liftIO $ NC.connectionGetChunk c)
        go

connectionSink :: NC.Connection -> Sink ByteString IO ()
connectionSink c = awaitForever $ 
    \chunk -> liftIO $ NC.connectionPut c chunk

hostFromUri :: URI -> HostName
hostFromUri = uriRegName . fromJust . uriAuthority

portFromUri :: URI -> PortNumber
portFromUri = fromIntegral . extractPort . uriPort . fromJust . uriAuthority
                                
extractPort :: String -> Int
extractPort []      = 4222
extractPort ":"     = 4222
extractPort (_:str) = read str

waitForShutdown :: Connection -> IO ()
waitForShutdown conn = 
    void $ waitAnyCatchCancel [ fromNet conn, toNet conn]
