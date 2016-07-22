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

import Control.Concurrent (threadDelay)
import Control.Concurrent.Async (Async, async, cancel, waitCatch)
import Control.Concurrent.STM ( TVar, atomically, newTVarIO
                              , readTVarIO, writeTVar
                              )
import Control.Monad (void)
import Network.URI (URI)
import Network.Socket (SockAddr)
import System.Random (randomRIO)

import Network.Nats.Connection ( Connection, Downstream
                               , Upstream, makeConnection
                               , clientShutdown, waitForShutdown, sockAddr
                               )
import Network.Nats.Subscriber (SubscriberMap)

-- | Resourced aquired by the connection manager. The record is
-- opaque to the user.
data ConnectionManager = ConnectionManager
    { connection    :: TVar (Maybe Connection)
    , managerThread :: Async ()
    }

-- | Internal runtime context for the connection manager.
data ManagerContext = ManagerContext
    { upstream      :: !Upstream
    , downstream    :: !Downstream
    , subscriberMap :: !SubscriberMap
    , uris          :: ![URI]
    , currUriIdx    :: !Int
    , currConn      :: TVar (Maybe Connection)
    }

-- | A set of parameters to guide the behavior of the connection manager.
-- A default set of parameters can be obtained by calling
-- 'defaultManagerSettings'.
data ManagerSettings = ManagerSettings
    { reconnectionAttempts :: !Int
      -- ^ The number of times the connection manager shall try to
      -- connect a server before giving up.
    
    , maxWaitTime :: !Int
      -- ^ Maximum waiting between a connection is made and a CONNECT
      -- message is received from the NATS server. If exceeded the
      -- connection is terminated and a new server selection is made.
    
    , serverSelect :: ([URI], Int) -> IO (URI, Int)
      -- ^ A function to select one of the servers from the
      -- server pool. The arguments to the selector is the list of server
      -- uris and the current index. The reply is the chosen server and
      -- its index.

    , connectedTo :: SockAddr -> IO ()
      -- ^ Callback to inform that a connection is made to the NATS
      -- server, with the 'SockAddr' for the server.

    , disconnectedFrom :: SockAddr -> IO ()
      -- ^ Callback to inform that a disconnection to the NATS server
      -- has happen. Give the 'SockAddr' for the server.
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
    conn <- newTVarIO Nothing
    let context = ManagerContext { upstream      = upstream'
                                 , downstream    = downstream'
                                 , subscriberMap = subscriberMap'
                                 , uris          = uris'
                                 , currUriIdx    = -1
                                 , currConn      = conn
                                 }
    ConnectionManager <$> pure conn
                      <*> async (managerLoop settings context)

-- | Stop the connection manager, clean up stuff.
stopConnectionManager :: ConnectionManager -> IO ()
stopConnectionManager mgr = do
    -- The order when shutting down things is important. First the
    -- managerThread must be stopped (so it not tries to create new
    -- connections). Then the 'Connection' can be stopped.
    cancel $ managerThread mgr
    void $ waitCatch (managerThread mgr)

    -- The 'Connection' is folded in 'Maybe'.
    mapM_ clientShutdown =<< readTVarIO (connection mgr)

-- | Create a default 'ManagerSettings'.
defaultManagerSettings :: ManagerSettings
defaultManagerSettings =
    ManagerSettings
        { reconnectionAttempts = 5
        , maxWaitTime          = 2
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
managerLoop mgr@ManagerSettings {..} ctx@ManagerContext {..} = do
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
tryConnect _ _ 0 = error "No more attempts. Giving up."
tryConnect mgr@ManagerSettings {..} ctx@ManagerContext {..} attempts = do
    (uri, uriIdx) <- serverSelect (uris, currUriIdx)
    maybe (threadDelay 500000 >> tryConnect mgr ctx (attempts - 1))
          (\conn -> return (uriIdx, conn)) 
              =<< makeConnection uri upstream downstream subscriberMap
