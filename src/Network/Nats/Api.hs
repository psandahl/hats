module Network.Nats.Api
    ( Nats
    , initNats
    , termNats
    , publish
    , subscribe
    , subscribeAsync
    , unsubscribe
    , nextMsg
    ) where

import Control.Concurrent.Async (Async, async)
import Control.Concurrent.STM ( atomically
                              , newTQueueIO
                              , readTQueue
                              )

import Network.Nats.Conduit (Downstream, Upstream, upstreamMessage)
import Network.Nats.ConnectionManager ( ConnectionManager
                                      , ManagerConfiguration
                                      , startConnectionManager
                                      , stopConnectionManager
                                      )
import Network.Nats.Dispatcher (dispatcher)
import Network.Nats.Types ( Sid
                          , Topic
                          , Payload
                          , QueueGroup
                          )
import Network.Nats.Subscriber ( SubscriberMap
                               , Msg
                               , SubQueue (..)
                               , newSubscriberMap
                               , addSubscription
                               , addAsyncSubscription
                               )
import Network.Nats.Message.Message (Message (..))

import Network.URI (URI)
import System.Random (randomRIO)

data Nats = Nats
    { subscriberMap     :: SubscriberMap
    , connectionManager :: !ConnectionManager
    , downstream        :: !Downstream
    , upstream          :: !Upstream
    , dispatcherThread  :: !(Async ())
    }

initNats :: ManagerConfiguration -> [URI] -> IO Nats
initNats config uris = do
    subscriberMap'    <- newSubscriberMap
    downstream'       <- newTQueueIO
    upstream'         <- newTQueueIO
    manager           <- startConnectionManager config upstream' 
                                                downstream' uris
    dispatcherThread' <- async $ dispatcher downstream' upstream'
                                            subscriberMap'

    return Nats { subscriberMap     = subscriberMap'
                , connectionManager = manager
                , downstream        = downstream'
                , upstream          = upstream'
                , dispatcherThread  = dispatcherThread'
                }

termNats :: Nats -> IO ()
termNats nats = stopConnectionManager $ connectionManager nats

publish :: Nats -> Topic -> Maybe Topic -> Payload -> IO ()
publish nats topic replyTo payload =
    upstreamMessage (upstream nats) $ Pub topic replyTo payload

subscribe :: Nats -> Topic -> Maybe QueueGroup -> IO (Sid, SubQueue)
subscribe nats topic queueGroup = do
    sid <- newSid
    let msg = Sub topic queueGroup sid
    subQueue <- addSubscription (subscriberMap nats) sid msg
    upstreamMessage (upstream nats) msg
    return (sid, subQueue)

subscribeAsync :: Nats -> Topic -> Maybe QueueGroup
               -> (Msg -> IO ()) -> IO Sid
subscribeAsync nats topic queueGroup action = do
    sid <- newSid
    let msg = Sub topic queueGroup sid
    addAsyncSubscription (subscriberMap nats) sid msg action 
    upstreamMessage (upstream nats) msg
    return sid

unsubscribe :: Nats -> Sid -> IO ()
unsubscribe = undefined

nextMsg :: SubQueue -> IO Msg
{-# INLINE nextMsg #-}
nextMsg (SubQueue queue) = atomically $ readTQueue queue

newSid :: IO Sid
{-# INLINE newSid #-}
newSid = randomRIO (0, maxBound)

