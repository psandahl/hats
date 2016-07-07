{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards   #-}
-- | Abstraction for a connection towards a NATS server. It owns the
-- networking stuff and performs NATS handshaking necessary.
module Network.Nats.Connection
    ( Connection
    , Upstream
    , Downstream
    , makeConnection
    , waitForServerShutdown
    ) where

import Control.Concurrent.Async ( Async
                                , async
                                , waitAnyCatchCancel
                                )
import Control.Exception ( SomeException
                         , fromException
                         , throwIO
                         , handle
                         )
import Control.Monad (void)
import Data.Conduit (($$))
import Data.Conduit.Attoparsec (sinkParser)
import Data.Maybe (fromJust)
import Network.Socket (HostName, PortNumber)
import Network.URI ( URI
                   , uriAuthority
                   , uriRegName
                   , uriPort
                   )

import Network.Nats.Types (NatsException (..))
import Network.Nats.Conduit ( Upstream
                            , Downstream
                            , connectionSource
                            , connectionSink
                            , streamSource
                            , streamSink
                            )
import Network.Nats.Message.Message (Message (..))
import Network.Nats.Message.Parser (parseMessage)
import Network.Nats.Message.Writer (writeMessage)

import qualified Data.ByteString.Lazy as LBS
import qualified Network.Connection as NC

-- | Record representing an active connection towards the NATS server.
data Connection = Connection
    { connection :: !NC.Connection
    , fromNet    :: !(Async ())
    , toNet      :: !(Async ())
    }

-- | Make a new 'Connection' as specified by the URI. Provide one
-- 'Upstream' queue with data from the application to the server, and
-- one 'Downstream' queue with data from the server to the application.
makeConnection :: URI -> Upstream -> Downstream -> IO (Maybe Connection)
makeConnection uri fromApp toApp =
    socketError `handle` (Just <$> makeConnection' uri fromApp toApp)
    where
      socketError :: SomeException -> IO (Maybe Connection)
      socketError e
        | isConnectionRefused e = return Nothing
        | otherwise             =
            case fromException e of
                (Just HandshakeException) -> return Nothing
                _                         -> throwIO e
            
makeConnection' :: URI -> Upstream -> Downstream -> IO Connection
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

    -- Perform the handshaking of 'Info' and 'Connect' messages between
    -- the client and the server.
    handshake uri conn =<< getSingleMessage conn

    -- Now start the pipeline threads and let the fun begin.
    Connection conn <$> (async $ connectionSource conn $$ streamSink toApp)
                    <*> (async $ streamSource fromApp $$ connectionSink conn)

-- | Blocking wait for the server connection to shutdown (perhaps it
-- never does).
waitForServerShutdown :: Connection -> IO ()
waitForServerShutdown conn = do
    void $ waitAnyCatchCancel [ fromNet conn, toNet conn]
    NC.connectionClose $ connection conn

-- | Perform the handshake.
-- TODO: More handshaking, user, password, tls, tokens etc.
handshake :: URI -> NC.Connection -> Message -> IO ()
handshake _uri conn Info {..} = do
    let connect = Connect { clientVerbose     = Just False
                          , clientPedantic    = Just False
                          , clientSslRequired = Just False
                          , clientAuthToken   = Nothing
                          , clientUser        = Nothing
                          , clientPass        = Nothing
                          , clientName        = Just "hats"
                          , clientLang        = Just "Haskell"
                          , clientVersion     = Just "0.1.0.0"
                          }
    mapM_ (NC.connectionPut conn) $ LBS.toChunks (writeMessage connect)

handshake _ _ _ = throwIO HandshakeException


-- | Select the host part from the 'URI'.
hostFromUri :: URI -> HostName
hostFromUri = uriRegName . fromJust . uriAuthority

-- | Select the port part from the 'URI'.
portFromUri :: URI -> PortNumber
portFromUri = fromIntegral . extractPort . uriPort . fromJust . uriAuthority
                                
-- | When selected the port is a string of format ":4222". Skip the colon,
-- or if the port is missing, give the default port of 4222.
extractPort :: String -> Int
extractPort []        = 4222
extractPort ":"       = 4222
extractPort (':':str) = read str
extractPort _         = error "This is no valid port, ehh?"

-- | Awkward, but this is how to check for connection refuse.
isConnectionRefused :: SomeException -> Bool
isConnectionRefused e =
    show e == "connect: does not exist (Connection refused)"

-- | Get one single message from the 'NC.Connection'. It should be the
-- initial 'Info' message from the NATS server.
getSingleMessage :: NC.Connection -> IO Message
getSingleMessage c = connectionSource c $$ sinkParser parseMessage
