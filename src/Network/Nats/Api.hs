{-# LANGUAGE OverloadedStrings #-}
-- |
-- Module:      Network.Nats.Api
-- Copyright:   (c) 2016 Patrik Sandahl
-- License:     MIT
-- Maintainer:  Patrik Sandahl <patrik.sandahl@gmail.com>
-- Stability:   experimental
-- Portability: portable
--
-- NATS base API as provided by this library. A thin JSON layer is
-- added in "Network.Nats.JsonApi".
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
import Control.Concurrent.STM (atomically , newTQueueIO, readTQueue)
import Control.Exception (bracket)

import Network.Nats.Conduit (Downstream, Upstream, upstreamMessage)
import Network.Nats.ConnectionManager ( ConnectionManager
                                      , ManagerSettings
                                      , startConnectionManager
                                      , stopConnectionManager
                                      )
import Network.Nats.Dispatcher (dispatcher)
import Network.Nats.Types (Sid, Topic, Payload, QueueGroup)
import Network.Nats.Subscriber ( SubscriberMap, Msg, SubQueue (..)
                               , newSubscriberMap, addSubscriber
                               , addAsyncSubscriber, removeSubscriber
                               )
import Network.Nats.Message.Message (Message (..))

import Network.URI (URI)
import System.Random (randomRIO)

import qualified Data.ByteString.Char8 as BS

-- | The type of the handle used by the API. To the user this
-- type is opaque. The Nats handle is only valid within the scope of
-- 'Network.Nats.withNats' function.
data Nats = Nats
    { subscriberMap     :: SubscriberMap
    -- ^ A map to hold 'Topic' subscribers.

    , connectionManager :: !ConnectionManager
    -- ^ The 'ConnectionManager'.

    , downstream        :: !Downstream
    -- ^ The stream of messages from the NATS server to the client.

    , upstream          :: !Upstream
    -- ^ The stream of messages from the client to the NATS server.

    , dispatcherThread  :: !(Async ())
    -- ^ The message dispatcher thread.
    }

-- | Setting up of all the necessary resources needed by 'Nats'.
-- Suited for use with the style of resource management given by
-- 'Control.Exception.bracket'.
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

-- | Clean up 'Nats' resource. Used to clean up after 'initNats'.
termNats :: Nats -> IO ()
termNats nats = stopConnectionManager $ connectionManager nats

-- | Publish some 'Payload' message to a 'Topic'. The NATS server will
-- distribute the message to subscribers of the 'Topic'.
--
-- > publish nats "GREETINGS" Nothing "Hello, there!"
--
-- Will publish the string Hello, there! to subscribers of GREETINGS. No
-- reply-to 'Topic' is provided. To request a reply, provide a 'Topic'
-- where the subscriber can publish a reply.
--
-- > publish nats "GREETINGS" (Just "THANKS") "Hello, there!"
publish :: Nats -> Topic -> Maybe Topic -> Payload -> IO ()
publish nats topic replyTo payload =
    upstreamMessage (upstream nats) $ PUB topic replyTo payload
{-# INLINE publish #-}

-- | Subscribe to a 'Topic'. Optionally a subscription can be part of
-- a 'QueueGroup'. The function will immediately return with a tuple of
-- a 'Sid' for the subscription, and a 'SubQueue' from where messages can
-- be fetched using 'nextMsg'.
--
-- > (sid, queue) <- subscribe nats "do.stuff" Nothing
--
-- Or
--
-- > (sid, queue) <- subscribe nats "do.stuff" (Just "stuffworkers")
subscribe :: Nats -> Topic -> Maybe QueueGroup -> IO (Sid, SubQueue)
subscribe nats topic queueGroup = do
    sid <- newSid
    let msg = SUB topic queueGroup sid
    subQueue <- addSubscriber (subscriberMap nats) sid msg
    upstreamMessage (upstream nats) msg
    return (sid, subQueue)

-- | Subscribe to a 'Topic'. Optionally a subscription can be part of
-- a 'QueueGroup'.
--
-- Subscriptions using this function will be asynchronous, and each
-- message will be handled in its own thread. A message handler is
-- an IO action taking a 'Msg' as its argument. The function return
-- the 'Sid' for the subscription.
--
-- > sid <- subscribeAsync nats "do.stuff" Nothing $ \msg -> do
-- >     -- Do stuff with the msg
--
-- Or
--
-- > sid <- subscribeAsync nats "do.stuff" Nothing messageHandler
-- >
-- > messageHandler :: Msg -> IO ()
-- > messageHandler msg = do
-- >    -- Do stuff with the msg
subscribeAsync :: Nats -> Topic -> Maybe QueueGroup
               -> (Msg -> IO ()) -> IO Sid
subscribeAsync nats topic queueGroup action = do
    sid <- newSid
    let msg = SUB topic queueGroup sid
    addAsyncSubscriber (subscriberMap nats) sid msg action 
    upstreamMessage (upstream nats) msg
    return sid

-- | Request is publishing a 'Payload' to a 'Topic' and waiting for a
-- 'Msg'. Request is a blocking operation, but can be interrupted
-- by 'System.Timeout.timeout'.
--
-- > msg <- request nats "do.stuff" "A little payload"
--
-- Or
--
-- > maybeMsg <- timeout tmo $ request nats "do.stuff" "A little payload"
request :: Nats -> Topic -> Payload -> IO Msg
request nats topic payload = do
    replyTo <- randomReplyTo
    bracket (subscribe nats replyTo Nothing)
            (\(sid, _) -> unsubscribe nats sid Nothing)
            (\(_, queue) -> do
                publish nats topic (Just replyTo) payload
                nextMsg queue
            )

-- | Unsubscribe from a subscription using its 'Sid'. Optionally a limit
-- for automatic unsubscription can be given. Unsubscription will happen
-- once the number of messages - the limit - has been reached.
--
-- > unsubscribe nats sid Nothing
--
-- Or
--
-- > unsubscribe nats sid (Just 100)
unsubscribe :: Nats -> Sid -> Maybe Int -> IO ()
unsubscribe nats sid limit = do
    let msg = UNSUB sid limit
    removeSubscriber (subscriberMap nats) sid
    upstreamMessage (upstream nats) msg

-- | Fetch a new 'Msg' from the 'SubQueue'. Fetching a message is a
-- blocking operation, but can be interrupted by 'System.Timeout.timeout'.
--
-- > msg <- nextMsg queue
--
-- Or
--
-- > maybeMsg <- timeout tmo $ nextMsg queue
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
