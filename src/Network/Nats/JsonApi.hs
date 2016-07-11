module Network.Nats.JsonApi
    ( JsonMsg (..)
    , publishJson
    , subscribeAsyncJson
    , requestJson
    , nextJsonMsg
    ) where

import Data.Aeson

import Network.Nats.Api
import Network.Nats.Subscriber (Msg (..), SubQueue)
import Network.Nats.Types (Topic, Sid, QueueGroup)

data JsonMsg a =
    JsonMsg !Topic !(Maybe Topic) {-# UNPACK #-} !Sid !(Maybe a)
    deriving (Eq, Show)

publishJson :: ToJSON a => Nats -> Topic -> Maybe Topic -> a -> IO ()
publishJson nats topic replyTo = publish nats topic replyTo . encode

subscribeAsyncJson :: FromJSON a => Nats -> Topic -> Maybe QueueGroup
                   -> (JsonMsg a -> IO ()) -> IO Sid
subscribeAsyncJson nats topic queueGroup action =
    subscribeAsync nats topic queueGroup $
        \(Msg topic' replyTo sid payload) -> do
            let jsonMsg = JsonMsg topic' replyTo sid $ decode payload
            action jsonMsg

requestJson :: (ToJSON a, FromJSON b) => Nats -> Topic -> a
            -> IO (JsonMsg b)
requestJson nats topic payload = do
    Msg topic' replyTo sid payload' <- request nats topic $ encode payload
    return $ JsonMsg topic' replyTo sid (decode payload')

nextJsonMsg :: FromJSON a => SubQueue -> IO (JsonMsg a)
nextJsonMsg queue = do
    Msg topic replyTo sid payload <- nextMsg queue
    return $ JsonMsg topic replyTo sid (decode payload)

