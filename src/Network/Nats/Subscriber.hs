module Network.Nats.Subscriber
    ( SubscriberMap
    , Subscriber (..)
    , Msg (..)
    , SubQueue (..)
    , newSubscriberMap
    , addSubscriber
    , addAsyncSubscriber
    , removeSubscriber
    , lookupSubscriber
    , subscribeMessages
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
                              , readTVarIO
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

addSubscriber :: SubscriberMap -> Sid -> Message -> IO SubQueue
addSubscriber subscriberMap sid msg = do
    queue <- newTQueueIO
    let sub = Subscriber queue msg
    atomically $ modifyTVar subscriberMap $ HM.insert sid sub
    return $ SubQueue queue
{-# INLINE addSubscriber #-}

addAsyncSubscriber :: SubscriberMap -> Sid -> Message
                     -> (Msg -> IO ()) -> IO ()
addAsyncSubscriber subscriberMap sid msg action = do
    let sub = AsyncSubscriber action msg
    atomically $ modifyTVar subscriberMap $ HM.insert sid sub
{-# INLINE addAsyncSubscriber #-}

removeSubscriber :: SubscriberMap -> Sid -> IO ()
removeSubscriber subscriberMap sid =
    atomically $ modifyTVar subscriberMap $ HM.delete sid
{-# INLINE removeSubscriber #-}

lookupSubscriber :: SubscriberMap -> Sid -> IO (Maybe Subscriber)
lookupSubscriber subscriberMap sid =
    HM.lookup sid <$> atomically (readTVar subscriberMap)
{-# INLINE lookupSubscriber #-}

subscribeMessages :: SubscriberMap -> IO [Message]
subscribeMessages subscriberMap =
    map extractMessage . HM.elems <$> readTVarIO subscriberMap

extractMessage :: Subscriber -> Message
extractMessage (Subscriber _ msg)      = msg
extractMessage (AsyncSubscriber _ msg) = msg
{-# INLINE extractMessage #-}
