-- |
-- Module:      Network.Nats.Subscriber
-- Copyright:   (c) 2016 Patrik Sandahl
-- License:     MIT
-- Maintainer:  Patrik Sandahl <patrik.sandahl@gmail.com>
-- Stability:   experimental
-- Portability: portable
--
-- Data structures and API for handling of subscribers.
module Network.Nats.Subscriber
    ( SubscriberMap
    , Subscriber (..)
    , SubQueue (..)
    , newSubscriberMap
    , addSubscriber
    , addAsyncSubscriber
    , removeSubscriber
    , lookupSubscriber
    , subscribeMessages
    ) where

import Network.Nats.Types (Msg, Sid)
import Network.Nats.Message.Message (Message (..))

import Control.Concurrent.STM ( TQueue, TVar, atomically, newTVarIO
                              , newTQueueIO, modifyTVar, readTVar
                              , readTVarIO
                              )
import Data.HashMap.Strict (HashMap)

import qualified Data.HashMap.Strict as HM

-- | Map from 'Sid' to 'Subscriber'. Wrapped in a 'TVar'.
type SubscriberMap = TVar (HashMap Sid Subscriber)

-- | Data structure to describe a subscriber. Each subscriber caches
-- the SUB 'Message' used to define it. Needed when replaying
-- subscriptions at server reconnects.
data Subscriber
    = Subscriber !(TQueue Msg) !Message
    -- ^ A ordinary subscriber, which is just a 'TQueue' of 'Msg's.
    | AsyncSubscriber !(Msg -> IO ()) !Message
    -- ^ An asynchronous subscriber, with an IO action taking a
    -- 'Msg'.

-- | A subscriber queue, a queue of 'Msg' handled by a 'TQueue'.
newtype SubQueue = SubQueue (TQueue Msg)

-- | Create a new empty 'SubscriberMap'.
newSubscriberMap :: IO SubscriberMap
newSubscriberMap = newTVarIO HM.empty

-- | Add a new subscriber to the 'SubscriberMap'.
addSubscriber :: SubscriberMap -> Sid -> Message -> IO SubQueue
addSubscriber subscriberMap sid msg = do
    queue <- newTQueueIO
    let sub = Subscriber queue msg
    atomically $ modifyTVar subscriberMap $ HM.insert sid sub
    return $ SubQueue queue
{-# INLINE addSubscriber #-}

-- | Add a new, asynchronous, subscriber to the 'SubscriberMap'.
addAsyncSubscriber :: SubscriberMap -> Sid -> Message
                     -> (Msg -> IO ()) -> IO ()
addAsyncSubscriber subscriberMap sid msg action = do
    let sub = AsyncSubscriber action msg
    atomically $ modifyTVar subscriberMap $ HM.insert sid sub
{-# INLINE addAsyncSubscriber #-}

-- | Remove a subscriber.
removeSubscriber :: SubscriberMap -> Sid -> IO ()
removeSubscriber subscriberMap sid =
    atomically $ modifyTVar subscriberMap $ HM.delete sid
{-# INLINE removeSubscriber #-}

-- | Try to lookup a subscriber.
lookupSubscriber :: SubscriberMap -> Sid -> IO (Maybe Subscriber)
lookupSubscriber subscriberMap sid =
    HM.lookup sid <$> atomically (readTVar subscriberMap)
{-# INLINE lookupSubscriber #-}

-- | Enumerate all subscriber SUB 'Message's from the 'SubscriberMap'.
subscribeMessages :: SubscriberMap -> IO [Message]
subscribeMessages subscriberMap =
    map extractMessage . HM.elems <$> readTVarIO subscriberMap

extractMessage :: Subscriber -> Message
extractMessage (Subscriber _ msg)      = msg
extractMessage (AsyncSubscriber _ msg) = msg
{-# INLINE extractMessage #-}
