{-# LANGUAGE TupleSections #-}
-- | Abstraction for a connection towards a NATS server. It owns the
-- networking stuff and performs NATS handshaking necessary.
module Network.Nats.Connection
    ( Connection
    , makeConnection
    , waitForShutdown
    ) where

import Control.Concurrent.Async (Async)
import Control.Exception
import Data.ByteString (ByteString)
import Data.Conduit (ResumableSource, Sink)
import Data.Maybe (fromJust)
import Network.Socket
import Network.URI

import qualified Network.Connection as NC

data Connection = Connection
    { connection :: !NC.Connection
    }

makeConnection :: URI -> IO (Maybe Connection)
makeConnection uri =
    socketError `handle` (Just <$> makeConnection' uri)
    where
      socketError :: SomeException -> IO (Maybe Connection)
      socketError e
        | isConnectionRefused e = return Nothing
        | otherwise             = throwIO e

isConnectionRefused :: SomeException -> Bool
isConnectionRefused e =
    show e == "connect: does not exist (Connection refused)"

makeConnection' :: URI
--               -> ResumableSource IO ByteString
--               -> Sink ByteString IO () 
               -> IO Connection
makeConnection' uri = do
    ctx <- NC.initConnectionContext
    conn <- NC.connectTo ctx $
        NC.ConnectionParams
            { NC.connectionHostname  = hostFromUri uri
            , NC.connectionPort      = portFromUri uri
            , NC.connectionUseSocks  = Nothing
            , NC.connectionUseSecure = Nothing
            }
    return $ Connection
                { connection = conn
                }

hostFromUri :: URI -> HostName
hostFromUri = uriRegName . fromJust . uriAuthority

portFromUri :: URI -> PortNumber
portFromUri = fromIntegral . extractPort . uriPort . fromJust . uriAuthority
                                
extractPort :: String -> Int
extractPort []      = 4222
extractPort ":"     = 4222
extractPort (_:str) = read str

waitForShutdown :: Connection -> IO ()
waitForShutdown = undefined
