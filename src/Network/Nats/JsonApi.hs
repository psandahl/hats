-- |
-- Module:      Network.Nats.JsonApi
-- Copyright:   (c) 2016 Patrik Sandahl
-- License:     MIT
-- Maintainer:  Patrik Sandahl <patrik.sandahl@gmail.com>
-- Stability:   experimental
-- Portability: portable
--
-- NATS base library extended with with JSON coding of payload. JSON
-- handling is provided by "Data.Aeson".
module Network.Nats.JsonApi
    ( publishJson
    , subscribeAsyncJson
    , requestJson
    , nextJsonMsg
    ) where

import Data.Aeson

import Network.Nats.Api (Nats, publish, subscribeAsync, request, nextMsg)
import Network.Nats.Subscriber (SubQueue)
import Network.Nats.Types (Msg (..), JsonMsg (..), Topic, Sid, QueueGroup)

-- | As 'publish', but with JSON payload.
publishJson :: ToJSON a => Nats -> Topic -> Maybe Topic -> a -> IO ()
publishJson nats topic replyTo = publish nats topic replyTo . encode

-- | As 'subscribeAsync', but with 'JsonMsg' instead of 'Msg'
-- to the handler.
subscribeAsyncJson :: FromJSON a => Nats -> Topic -> Maybe QueueGroup
                   -> (JsonMsg a -> IO ()) -> IO Sid
subscribeAsyncJson nats topic queueGroup action =
    subscribeAsync nats topic queueGroup $
        \(Msg topic' replyTo sid payload) -> do
            let jsonMsg = JsonMsg topic' replyTo sid $ decode payload
            action jsonMsg

-- | As 'request', but with JSON payload and 'JsonMsg' reply.
requestJson :: (ToJSON a, FromJSON b) => Nats -> Topic -> a
            -> IO (JsonMsg b)
requestJson nats topic payload = do
    Msg topic' replyTo sid payload' <- request nats topic $ encode payload
    return $ JsonMsg topic' replyTo sid (decode payload')

-- | As 'nextMsg', but with 'JsonMsg' replies.
nextJsonMsg :: FromJSON a => SubQueue -> IO (JsonMsg a)
nextJsonMsg queue = do
    Msg topic replyTo sid payload <- nextMsg queue
    return $ JsonMsg topic replyTo sid (decode payload)

