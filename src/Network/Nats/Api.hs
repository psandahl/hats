{-# LANGUAGE OverloadedStrings #-}
 module Network.Nats.Api
    ( Nats
    , initNats
    , termNats
    , publish
    , subscribe
    , subscribeAsync
    , request
    , unsubscribe
    , nextMsg
    ) where

import Control.Concurrent.Async (Async, async)
import Control.Concurrent.STM ( atomically
                              , newTQueueIO
                              , readTQueue
                              )
import Control.Exception (bracket)

import Network.Nats.Conduit (Downstream, Upstream, upstreamMessage)
import Network.Nats.ConnectionManager ( ConnectionManager
                                      , ManagerSettings
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
                               , addSubscriber
                               , addAsyncSubscriber
                               , removeSubscriber
                               )
import Network.Nats.Message.Message (Message (..))

import Network.URI (URI)
import System.Random (randomRIO)

import qualified Data.ByteString.Char8 as BS

data Nats = Nats
    { subscriberMap     :: SubscriberMap
    , connectionManager :: !ConnectionManager
    , downstream        :: !Downstream
    , upstream          :: !Upstream
    , dispatcherThread  :: !(Async ())
    }

initNats :: ManagerSettings -> [URI] -> IO Nats
initNats config uris = do
    subscriberMap'    <- newSubscriberMap
    downstream'       <- newTQueueIO
    upstream'         <- newTQueueIO
    manager           <- startConnectionManager config upstream' 
                                                downstream' subscriberMap'
                                                uris
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
    upstreamMessage (upstream nats) $ PUB topic replyTo payload
{-# INLINE publish #-}

subscribe :: Nats -> Topic -> Maybe QueueGroup -> IO (Sid, SubQueue)
subscribe nats topic queueGroup = do
    sid <- newSid
    let msg = SUB topic queueGroup sid
    subQueue <- addSubscriber (subscriberMap nats) sid msg
    upstreamMessage (upstream nats) msg
    return (sid, subQueue)

subscribeAsync :: Nats -> Topic -> Maybe QueueGroup
               -> (Msg -> IO ()) -> IO Sid
subscribeAsync nats topic queueGroup action = do
    sid <- newSid
    let msg = SUB topic queueGroup sid
    addAsyncSubscriber (subscriberMap nats) sid msg action 
    upstreamMessage (upstream nats) msg
    return sid

request :: Nats -> Topic -> Payload -> IO Msg
request nats topic payload = do
    replyTo <- randomReplyTo
    bracket (subscribe nats replyTo Nothing)
            (\(sid, _) -> unsubscribe nats sid Nothing)
            (\(_, queue) -> do
                publish nats topic (Just replyTo) payload
                nextMsg queue
            )

unsubscribe :: Nats -> Sid -> Maybe Int -> IO ()
unsubscribe nats sid limit = do
    let msg = UNSUB sid limit
    removeSubscriber (subscriberMap nats) sid
    upstreamMessage (upstream nats) msg

nextMsg :: SubQueue -> IO Msg
nextMsg (SubQueue queue) = atomically $ readTQueue queue
{-# INLINE nextMsg #-}

newSid :: IO Sid
newSid = randomRIO (0, maxBound)
{-# INLINE newSid #-}

randomReplyTo :: IO Topic
randomReplyTo = do
    value <- BS.pack . show <$> randomRIO (0, maxBound :: Int)
    return $ "INBOX." `BS.append` value
{-# INLINE randomReplyTo #-}
