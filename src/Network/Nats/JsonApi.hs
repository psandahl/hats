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
    , requestJson
    ) where

import Data.Aeson (ToJSON, encode)

import Network.Nats.Api (Nats, publish, request)
import Network.Nats.Types (Msg, Topic)

-- | As 'publish', but with JSON payload.
publishJson :: ToJSON a => Nats -> Topic -> Maybe Topic -> a -> IO ()
publishJson nats topic replyTo = publish nats topic replyTo . encode
{-# INLINE publishJson #-}

-- | As 'request', but with JSON payload.
requestJson :: ToJSON a => Nats -> Topic -> a -> IO Msg
requestJson nats topic = request nats topic . encode
{-# INLINE requestJson #-}
