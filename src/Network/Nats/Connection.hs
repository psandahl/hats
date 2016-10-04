{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards   #-}
-- |
-- Module:      Network.Nats.ConnectionManager
-- Copyright:   (c) 2016 Patrik Sandahl
-- License:     MIT
-- Maintainer:  Patrik Sandahl <patrik.sandahl@gmail.com>
-- Stability:   experimental
-- Portability: portable
--
-- | Abstraction for a connection towards a NATS server. It owns the
-- networking stuff and performs NATS handshaking necessary.
module Network.Nats.Connection
    ( Connection (sockAddr)
    , Upstream
    , Downstream
    , makeConnection
    , clientShutdown
    , waitForShutdown
    ) where

import Control.Concurrent.Async (Async, async, waitAnyCatchCancel)
import Control.Exception (SomeException, fromException, throwIO, handle)
import Control.Monad (void, when)
import Data.Conduit (($$), (=$=))
import Data.Conduit.Attoparsec (sinkParser)
import Data.Conduit.List (sourceList)
import Data.List
import Data.Maybe (fromJust, isNothing)
import Network.Socket ( AddrInfo (..), HostName, PortNumber
                      , SockAddr, defaultHints, getAddrInfo
                      )
import Network.URI (URI, uriAuthority, uriRegName, uriPort, uriUserInfo)
import System.Timeout (timeout)

import Network.Nats.Types (NatsException (..))
import Network.Nats.Conduit ( Upstream, Downstream, connectionSource
                            , connectionSink, streamSource
                            , streamSink, messageChunker
                            )
import Network.Nats.Subscriber (SubscriberMap, subscribeMessages)
import Network.Nats.Message.Message (Message (..))
import Network.Nats.Message.Parser (parseMessage)
import Network.Nats.Message.Writer (writeMessage)

import qualified Data.ByteString.Char8 as BS
import qualified Data.ByteString.Lazy as LBS
import qualified Network.Connection as NC

-- | Type alias for a microsecond timeout.
type Tmo = Int

-- | Record representing an active connection towards the NATS server.
data Connection = Connection
    { connection :: !NC.Connection
    , sockAddr   :: !SockAddr
    , fromNet    :: !(Async ())
    , toNet      :: !(Async ())
    }

-- | Make a new 'Connection' as specified by the URI. Provide one
-- 'Upstream' queue with data from the application to the server, and
-- one 'Downstream' queue with data from the server to the application.
makeConnection :: Tmo -> URI -> Upstream -> Downstream -> SubscriberMap
               -> IO (Maybe Connection)
makeConnection tmo uri fromApp toApp subscriberMap =
    connectionError `handle` (Just <$> makeConnection' tmo uri fromApp
                                                       toApp subscriberMap)
    where
      connectionError :: SomeException -> IO (Maybe Connection)
      connectionError e
        | isConnectionRefused e = return Nothing
        | isResolvError       e = return Nothing
        | otherwise             =
            case fromException e of
                (Just HandshakeException) -> return Nothing
                _                         -> throwIO e

makeConnection' :: Tmo -> URI -> Upstream -> Downstream -> SubscriberMap
                -> IO Connection
makeConnection' tmo uri fromApp toApp subscriberMap = do
    let host = hostFromUri uri
        port = portFromUri uri

    -- Make the connection.
    ctx  <- NC.initConnectionContext
    conn <- NC.connectTo ctx
        NC.ConnectionParams
            { NC.connectionHostname  = host
            , NC.connectionPort      = port
            , NC.connectionUseSocks  = Nothing
            , NC.connectionUseSecure = Nothing
            }

    -- Perform the handshaking of 'Info' and 'Connect' messages between
    -- the client and the server. If the time to receive the 'Info'
    -- message exceeds the timeout, there's a HandshakeException.
    msg <- timeout tmo $ getSingleMessage conn
    when (isNothing msg) $ do
        NC.connectionClose conn
        throwIO HandshakeException

    -- Continue with the handshake.
    handshake uri conn $ fromJust msg

    -- Fetch already made subscriptions for replay.
    msgs <- subscribeMessages subscriberMap

    -- Now start the pipeline threads and let the fun begin.
    Connection conn <$> toSockAddr host port
                    <*> async (recvPipe conn toApp)
                    <*> async (do
                            replaySubscriptions conn msgs
                            sendPipe fromApp conn)

-- | Pipeline to run the 'Downstream' conduit.
recvPipe :: NC.Connection -> Downstream -> IO ()
recvPipe conn toApp = connectionSource conn $$ streamSink toApp

-- | Pipeline to run the 'Upstream' conduit.
sendPipe :: Upstream -> NC.Connection -> IO ()
sendPipe fromApp conn = streamSource fromApp $$ connectionSink conn

-- | Replay all stored subscriptions to the 'NC.Connection'.
replaySubscriptions :: NC.Connection -> [Message] -> IO ()
replaySubscriptions conn msgs =
    sourceList msgs =$= messageChunker $$ connectionSink conn

-- | Shut down a 'Connection' by cancel the threads.
clientShutdown :: Connection -> IO ()
clientShutdown conn = do
    -- The close of the connection will make the threads terminate.
    NC.connectionClose $ connection conn
    void $ waitAnyCatchCancel [ fromNet conn, toNet conn ]

-- | Blocking wait for the connection to shutdown (perhaps it
-- never does).
waitForShutdown :: Connection -> IO ()
waitForShutdown conn = do
    void $ waitAnyCatchCancel [ fromNet conn, toNet conn ]
    NC.connectionClose $ connection conn

-- | Perform the handshake.
-- TODO: More handshaking, tls, tokens etc.
handshake :: URI -> NC.Connection -> Message -> IO ()
handshake uri conn INFO {..} = do
    let (user, pass) = credentialsFromUri uri
        connect = CONNECT { clientVerbose     = Just False
                          , clientPedantic    = Just False
                          , clientSslRequired = Just False
                          , clientAuthToken   = Nothing
                          , clientUser        = user
                          , clientPass        = pass
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

-- | Extract credentials (if any) from the 'URI'.
credentialsFromUri :: URI -> (Maybe BS.ByteString, Maybe BS.ByteString)
credentialsFromUri =
    toBS . extractCredentials . uriUserInfo. fromJust . uriAuthority
    where
      toBS (user, pass) = (BS.pack <$> user, BS.pack <$> pass)

-- | Resolve a 'HostName' and a 'PortNumber' to a 'SockAddr'.
toSockAddr :: HostName -> PortNumber -> IO SockAddr
toSockAddr host port =
    addrAddress . head <$> getAddrInfo (Just defaultHints)
                                       (Just host)
                                       (Just $ show port)

-- | When selected the port is a string of format ":4222". Skip the colon,
-- or if the port is missing, give the default port of 4222.
extractPort :: String -> Int
extractPort []        = 4222
extractPort ":"       = 4222
extractPort (':':str) = read str
extractPort _         = error "This is no valid port, ehh?"

-- | Extract the credentials from a String.
extractCredentials :: String -> (Maybe String, Maybe String)
extractCredentials "" = (Nothing, Nothing)
extractCredentials str =
    let str'  = takeWhile (/= '@') str
        colon = elemIndex ':' str'
    in
        if isNothing colon
            then (Just str', Nothing)
            else
                let (user, _:pass) = splitAt (fromJust colon) str'
                in (Just user, Just pass)

-- | Awkward, but this is how to check for connection refuse.
isConnectionRefused :: SomeException -> Bool
isConnectionRefused e =
    "connect: does not exist (Connection refused)" `isInfixOf` show e

-- | Equally awkward, but this is how to check for resolv errors.
isResolvError :: SomeException -> Bool
isResolvError e =
    show e == "getAddrInfo: does not exist (Name or service not known)"

-- | Get one single message from the 'NC.Connection'. It should be the
-- initial 'Info' message from the NATS server.
getSingleMessage :: NC.Connection -> IO Message
getSingleMessage c = connectionSource c $$ sinkParser parseMessage
