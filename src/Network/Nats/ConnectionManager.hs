{-# LANGUAGE RecordWildCards #-}
-- |
-- Module:      Network.Nats.ConnectionManager
-- Copyright:   (c) 2016 Patrik Sandahl
-- License:     MIT
-- Maintainer:  Patrik Sandahl <patrik.sandahl@gmail.com>
-- Stability:   experimental
-- Portability: portable
--
-- Configuration and functionality for setting up and maintaining
-- connections towards a NATS messaging server.
module Network.Nats.ConnectionManager
    ( ConnectionManager
    , ManagerSettings (..)
    , SockAddr
    , startConnectionManager
    , stopConnectionManager
    , defaultManagerSettings
    , randomSelect
    , roundRobinSelect
    ) where

import Control.Concurrent (ThreadId, forkIO, killThread, myThreadId)
import Control.Concurrent.STM ( TVar, atomically, newTVarIO
                              , readTVarIO, writeTVar
                              )
import Control.Exception (handle, throwIO, throwTo)
import Network.URI (URI)
import Network.Socket (SockAddr)
import System.Random (randomRIO)

import Network.Nats.Connection ( Connection, Downstream
                               , Upstream, makeConnection
                               , clientShutdown, waitForShutdown, sockAddr
                               )
import Network.Nats.Subscriber (SubscriberMap)
import Network.Nats.Types (NatsException (..))

-- | Resourced aquired by the connection manager. The record is
-- opaque to the user.
data ConnectionManager = ConnectionManager
    { connection    :: TVar (Maybe Connection)
    , managerThread :: ThreadId
    }

-- | Internal runtime context for the connection manager.
data ManagerContext = ManagerContext
    { upstream      :: !Upstream
    , downstream    :: !Downstream
    , subscriberMap :: !SubscriberMap
    , uris          :: ![URI]
    , currUriIdx    :: !Int
    , currConn      :: TVar (Maybe Connection)
    , callerThread  :: !ThreadId
    }

-- | A set of parameters to guide the behavior of the connection manager.
-- A default set of parameters can be obtained by calling
-- 'defaultManagerSettings'.
data ManagerSettings = ManagerSettings
    { reconnectionAttempts :: !Int
      -- ^ The number of times the connection manager shall try to
      -- connect a server before giving up.
    
    , maxWaitTimeMS    :: !Int
      -- ^ Maximum waiting between a connection is made and a CONNECT
      -- message is received from the NATS server. If exceeded the
      -- connection is terminated and a new server selection is made.
      -- The unit for the time is in milliseconds.
    
    , serverSelect     :: ([URI], Int) -> IO (URI, Int)
      -- ^ A function to select one of the servers from the
      -- server pool. The arguments to the selector is the list of server
      -- uris and the current index. The reply is the chosen server and
      -- its index.

    , connectedTo      :: SockAddr -> IO ()
      -- ^ Callback to inform that a connection is made to the NATS
      -- server, with the 'SockAddr' for the server. This callback is
      -- made in the connection manager's thread, and the callback's
      -- execution time must be minimized. 'Control.Concurrent.forkIO'
      -- if longer execution times are needed.

    , disconnectedFrom :: SockAddr -> IO ()
      -- ^ Callback to inform that a disconnection to the NATS server
      -- has happen. Give the 'SockAddr' for the server. This callback is
      -- made in the connection manager's thread, and the callback's
      -- execution time must be minimized. 'Control.Concurrent.forkIO'
      -- if longer execution times are needed.

    }

-- | Start the connection manager.
startConnectionManager :: ManagerSettings
                       -> Upstream
                       -> Downstream
                       -> SubscriberMap
                       -> [URI]
                       -> IO ConnectionManager
startConnectionManager settings upstream' downstream' 
                       subscriberMap' uris' = do
    -- The transactional 'Connection' is shared between the 'ManagerContext'
    -- and the 'ConnectionManager'.
    conn   <- newTVarIO Nothing
    caller <- myThreadId
    let context = ManagerContext { upstream      = upstream'
                                 , downstream    = downstream'
                                 , subscriberMap = subscriberMap'
                                 , uris          = uris'
                                 , currUriIdx    = -1
                                 , currConn      = conn
                                 , callerThread  = caller
                                 }
    ConnectionManager <$> pure conn
                      <*> forkIO (managerLoop settings context)

-- | Stop the connection manager, clean up stuff.
stopConnectionManager :: ConnectionManager -> IO ()
stopConnectionManager mgr = do
    -- The order when shutting down things is important. First the
    -- managerThread must be stopped (so it not tries to create new
    -- connections). Then the 'Connection' can be stopped.
    killThread $ managerThread mgr

    -- The 'Connection' is folded in 'Maybe'.
    mapM_ clientShutdown =<< readTVarIO (connection mgr)

-- | Create a default 'ManagerSettings'.
defaultManagerSettings :: ManagerSettings
defaultManagerSettings =
    ManagerSettings
        { reconnectionAttempts = 5
        , maxWaitTimeMS        = 2000
        , serverSelect         = roundRobinSelect
        , connectedTo          = const (return ())
        , disconnectedFrom     = const (return ())
        }

-- | Make a random selection of a server.
randomSelect :: ([URI], Int) -> IO (URI, Int)
randomSelect (xs, _) = do
    idx <- randomRIO (0, length xs - 1)
    return (xs !! idx, idx)

-- | Use round robin to select a server.
roundRobinSelect :: ([URI], Int) -> IO (URI, Int)
roundRobinSelect (xs, currIdx)
    | currIdx == length xs - 1 = return (head xs, 0)
    | otherwise                = return (xs !! (currIdx + 1), currIdx + 1)

-- | Connect to a server and maintain the connection.
managerLoop :: ManagerSettings -> ManagerContext -> IO ()
managerLoop mgr@ManagerSettings {..} ctx@ManagerContext {..} = 
    exceptionForward callerThread `handle` do
        (newIdx, conn) <- tryConnect mgr ctx reconnectionAttempts
        atomically $ writeTVar currConn (Just conn)
        connectedTo $ sockAddr conn
        waitForShutdown conn
        atomically $ writeTVar currConn Nothing
        disconnectedFrom $ sockAddr conn
        managerLoop mgr $ ctx { currUriIdx = newIdx }

-- | Select a server and connect.
tryConnect :: ManagerSettings -> ManagerContext -> Int
            -> IO (Int, Connection)
tryConnect _ _ 0 = throwIO ConnectionGiveUpException
tryConnect mgr@ManagerSettings {..} ctx@ManagerContext {..} attempts = do
    (uri, uriIdx) <- serverSelect (uris, currUriIdx)
    maybe (tryConnect mgr ctx (attempts - 1))
          (\conn -> return (uriIdx, conn)) 
              =<< makeConnection (toUS maxWaitTimeMS) uri 
                                 upstream downstream subscriberMap

-- | Throw 'NatsException's to the provided thread.
exceptionForward :: ThreadId -> NatsException -> IO ()
exceptionForward = throwTo

toUS :: Int -> Int
toUS n = n * 1000
