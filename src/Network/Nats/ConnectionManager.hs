-- | Configuration and functionality for setting up and maintaining
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
import Control.Concurrent.STM ( TVar
                              , atomically
                              , newTVarIO
                              , readTVarIO
                              , writeTVar
                              )
import Control.Monad (forever, void, when)
import Data.Maybe (isJust, fromJust)
import Network.URI (URI)
import Network.Socket (SockAddr)
import System.Random (randomRIO)

import Network.Nats.Connection
import Network.Nats.Subscriber (SubscriberMap)

data ConnectionManager = ConnectionManager
    { settings      :: !ManagerSettings
    , upstream      :: !Upstream
    , downstream    :: !Downstream
    , subscriberMap :: !SubscriberMap
    , uris          :: ![URI]
    , connection    :: !(TVar (Maybe Connection))
    , currUri       :: !(TVar Int)
    , managerThread :: !(TVar (Maybe (Async ())))
    }

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

startConnectionManager :: ManagerSettings
                       -> Upstream
                       -> Downstream
                       -> SubscriberMap
                       -> [URI]
                       -> IO ConnectionManager
startConnectionManager settings' upstream' downstream' 
                       subscriberMap' uris' = do
    connection'    <- newTVarIO Nothing
    currUri'       <- newTVarIO (-1)
    managerThread' <- newTVarIO Nothing
    let mgr = ConnectionManager { settings      = settings'
                                , upstream      = upstream'
                                , downstream    = downstream'
                                , subscriberMap = subscriberMap'
                                , uris          = uris'
                                , connection    = connection'
                                , currUri       = currUri'
                                , managerThread = managerThread'
                                }
    thread <- async $ connectionManager mgr
    atomically $ writeTVar managerThread' (Just thread)
    return mgr

stopConnectionManager :: ConnectionManager -> IO ()
stopConnectionManager mgr = do
    -- The order when shutting down things is important. First the
    -- managerThread must be stopped (so it not tries to create new
    -- connections). Then the 'Connection' can be stopped.
    managerThread' <- readTVarIO $ managerThread mgr
    when (isJust managerThread') $ do
        let thread = fromJust managerThread'
        cancel thread
        void $ waitCatch thread

    connection' <- readTVarIO $ connection mgr
    when (isJust connection') $ do
        let connection'' = fromJust connection'
        clientShutdown connection''

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

connectionManager :: ConnectionManager -> IO ()
connectionManager mgr = do
    let connectedTo'      = connectedTo $ settings mgr
        disconnectedFrom' = disconnectedFrom $ settings mgr
    forever $ do
        c <- tryConnect mgr (reconnectionAttempts $ settings mgr)
        atomically $ writeTVar (connection mgr) (Just c)
        connectedTo' $ sockAddr c
        waitForShutdown c
        disconnectedFrom' $ sockAddr c

tryConnect :: ConnectionManager -> Int -> IO Connection
tryConnect _ 0 = error "No more attempts!"
tryConnect mgr n = do
    putStrLn $ "Attempt: " ++ show n
    let selector = serverSelect $ settings mgr
    currUri'      <- readTVarIO $ currUri mgr
    (uri, newUri) <- selector (uris mgr,  currUri')
    atomically $ writeTVar (currUri mgr) newUri
    mConnection <- makeConnection uri (upstream mgr)
                                  (downstream mgr) (subscriberMap mgr)
    case mConnection of
        Just c  -> return c
        Nothing -> do
            threadDelay 1000000
            tryConnect mgr (n - 1)
