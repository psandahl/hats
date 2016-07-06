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

import Network.Nats.Connection (Downstream, Upstream)
import Network.Nats.ConnectionManager ( ConnectionManager
                                      , ManagerConfiguration
                                      , startConnectionManager
                                      , stopConnectionManager
                                      )
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
import Network.Nats.Message.Writer (writeMessage)

import Control.Concurrent.STM ( atomically
                              , newTQueueIO
                              , writeTQueue
                              , readTQueue
                              )
import Network.URI (URI)
import System.Random (randomRIO)

import qualified Data.ByteString.Lazy as LBS

data Nats = Nats
    { subscriberMap     :: SubscriberMap
    , connectionManager :: !ConnectionManager
    , downstream        :: !Downstream
    , upstream          :: !Upstream
    }

initNats :: ManagerConfiguration -> [URI] -> IO Nats
initNats config uris = do
    subscriberMap' <- newSubscriberMap
    downstream'    <- newTQueueIO
    upstream'      <- newTQueueIO
    manager        <- startConnectionManager config upstream' 
                                             downstream' uris
    return $ Nats { subscriberMap     = subscriberMap'
                  , connectionManager = manager
                  , downstream        = downstream'
                  , upstream          = upstream'
                  }

termNats :: Nats -> IO ()
termNats = stopConnectionManager . connectionManager

publish :: Nats -> Topic -> Maybe Topic -> Payload -> IO ()
publish nats topic replyTo payload =
    pushMessage nats $ Pub topic replyTo payload

subscribe :: Nats -> Topic -> Maybe QueueGroup -> IO (Sid, SubQueue)
subscribe nats topic queueGroup = do
    sid <- newSid
    let msg = Sub topic queueGroup sid
    subQueue <- addSubscription (subscriberMap nats) sid msg
    pushMessage nats msg
    return (sid, subQueue)

subscribeAsync :: Nats -> Topic -> Maybe QueueGroup
               -> (Msg -> IO ()) -> IO Sid
subscribeAsync nats topic queueGroup action = do
    sid <- newSid
    let msg = Sub topic queueGroup sid
    addAsyncSubscription (subscriberMap nats) sid msg action 
    pushMessage nats msg
    return sid

unsubscribe :: Nats -> Sid -> IO ()
unsubscribe = undefined

nextMsg :: SubQueue -> IO Msg
nextMsg (SubQueue queue) = atomically $ readTQueue queue

pushMessage :: Nats -> Message -> IO ()
{-# INLINE pushMessage #-}
pushMessage nats msg = atomically $
    mapM_ (writeTQueue $ upstream nats) $ LBS.toChunks (writeMessage msg)

newSid :: IO Sid
{-# INLINE newSid #-}
newSid = randomRIO (0, maxBound)

