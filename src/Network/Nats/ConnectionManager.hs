-- | Configuration and functionality for setting up and maintaining
-- connections towards a NATS messaging server.
module Network.Nats.ConnectionManager
    ( ConnectionManager (..)
    , ManagerConfiguration (..)
    , newConnectionManager
    , startConnectionManager
    , stopConnectionManager
    , defaultManagerConfiguration
    , randomSelect
    , roundRobinSelect
    ) where

import Data.Conduit (Source, Sink)
import Data.ByteString (ByteString)
import Network.Socket (SockAddr)
import Network.URI (URI)
import System.Random (randomRIO)

data ConnectionManager = ConnectionManager
    { configuration :: !ManagerConfiguration
    }

data ManagerConfiguration = ManagerConfiguration
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

    , connectInfo :: SockAddr -> IO ()
      -- ^ Callback to inform that a connection is made, with the 'SockAddr'
      -- for the server.

    , disconnectInfo :: SockAddr -> IO ()
      -- ^ Callback to inform that a disconnect has happened, with
      -- the 'SockAddr' for the server.
    }

newConnectionManager :: ManagerConfiguration
                     -> Source IO ByteString
                     -> Sink ByteString IO ()
                     -> [URI]
                     -> IO ConnectionManager
newConnectionManager = undefined

startConnectionManager :: ConnectionManager -> IO ()
startConnectionManager = undefined

stopConnectionManager :: ConnectionManager -> IO ()
stopConnectionManager = undefined

-- | Create a default 'ManagerConfiguration'.
defaultManagerConfiguration :: ManagerConfiguration
defaultManagerConfiguration =
    ManagerConfiguration
        { reconnectionAttempts = 5
        , maxWaitTime          = 2
        , serverSelect         = roundRobinSelect
        , connectInfo          = \_ -> return ()
        , disconnectInfo       = \_ -> return ()
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
