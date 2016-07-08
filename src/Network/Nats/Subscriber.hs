module Network.Nats.Subscriber
    ( SubscriberMap
    , Subscriber (..)
    , Msg (..)
    , SubQueue (..)
    , newSubscriberMap
    , addSubscription
    , addAsyncSubscription
    , lookupSubscriber
    ) where

import Network.Nats.Types ( Payload
                          , Sid
                          , Topic
                          )
import Network.Nats.Message.Message (Message (..))

import Control.Concurrent.STM ( TQueue
                              , TVar
                              , atomically
                              , newTVarIO
                              , newTQueueIO
                              , modifyTVar
                              , readTVar
                              )
import Data.HashMap.Strict (HashMap)

import qualified Data.HashMap.Strict as HM

type SubscriberMap = TVar (HashMap Sid Subscriber)

data Subscriber 
    = Subscriber !(TQueue Msg) !Message
    | AsyncSubscriber !(Msg -> IO ()) !Message

data Msg = Msg !Topic !(Maybe Topic) {-# UNPACK #-} !Sid !Payload
    deriving (Eq, Show)

newtype SubQueue = SubQueue (TQueue Msg)

newSubscriberMap :: IO SubscriberMap
newSubscriberMap = newTVarIO HM.empty

addSubscription :: SubscriberMap -> Sid -> Message -> IO SubQueue
addSubscription subscriberMap sid msg = do
    queue <- newTQueueIO
    let sub = Subscriber queue msg
    atomically $ modifyTVar subscriberMap $ HM.insert sid sub
    return $ SubQueue queue
{-# INLINE addSubscription #-}

addAsyncSubscription :: SubscriberMap -> Sid -> Message 
                     -> (Msg -> IO ()) -> IO ()
addAsyncSubscription subscriberMap sid msg action = do
    let sub = AsyncSubscriber action msg
    atomically $ modifyTVar subscriberMap $ HM.insert sid sub
{-# INLINE addAsyncSubscription #-}

lookupSubscriber :: SubscriberMap -> Sid -> IO (Maybe Subscriber)
lookupSubscriber subscriberMap sid =
    HM.lookup sid <$> atomically (readTVar subscriberMap)
{-# INLINE lookupSubscriber #-}
