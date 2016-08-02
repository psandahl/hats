{-# LANGUAGE DeriveAnyClass #-}
-- |
-- Module:      Network.Nats.Types
-- Copyright:   (c) 2016 Patrik Sandahl
-- License:     MIT
-- Maintainer:  Patrik Sandahl <patrik.sandahl@gmail.com>
-- Stability:   experimental
-- Portability: portable
--
-- Base types for the library's API. JSON support is implemented
-- with "Data.Aeson".
module Network.Nats.Types
    ( Topic
    , Payload
    , Sid
    , QueueGroup
    , NatsException (..)
    , MsgQueue (..)
    , Msg (..)
    , topic
    , replyTo
    , sid
    , payload
    , jsonPayload
    , jsonPayload'
    ) where

import Control.Concurrent.STM (TQueue)
import Control.Exception (Exception)
import Data.Aeson (FromJSON, decode, decode')
import Data.Typeable (Typeable)
import GHC.Int (Int64)

import qualified Data.ByteString as BS
import qualified Data.ByteString.Lazy as LBS

-- | The type of a topic where to publish, or to subscribe on. Type
-- alias for 'BS.ByteString'.
type Topic = BS.ByteString

-- | The type of a message payload. Type alias for 'LBS.ByteString'.
type Payload = LBS.ByteString

-- | The numeric id for a subscription. An id shall be unique within
-- a NATS client. The value of the id will be generated automatically
-- by the API. Type alias for 'Int64'.
type Sid = Int64

-- | A 'Topic' subscriber can be part of a queue group, an entity
-- for load balancing in NATS. Type alias for 'BS.ByteString'.
type QueueGroup = BS.ByteString

-- | Exceptions generated from within this library.
data NatsException
    = HandshakeException
    -- ^ An exception caused by errors during the NATS connection
    -- handshake.

    | ConnectionGiveUpException
    -- ^ An exception thrown when all the configured connection
    -- attempts are consumed.

    | URIError !String
    -- ^ An exception caused by invalid URI strings given to the
    -- 'Network.Nats.withNats' function.
    deriving (Typeable, Show)

instance Exception NatsException

-- | A message queue, a queue of 'Msg's handled by a 'TQueue'.
newtype MsgQueue = MsgQueue (TQueue Msg)

-- | A NATS message as received by the user. The message itself is
-- opaque to the user, but the fields can be read by the API functions
-- 'topic', 'replyTo', 'sid', 'payload', 'jsonPayload' and
-- 'jsonPayload''
data Msg = Msg !Topic !(Maybe Topic) {-# UNPACK #-} !Sid !Payload
    deriving (Eq, Show)

-- | Read the complete topic on which a message was received.
topic :: Msg -> Topic
topic (Msg t _ _ _) = t
{-# INLINE topic #-}

-- | Read the reply-to topic from a received message.
replyTo :: Msg -> Maybe Topic
replyTo (Msg _ r _ _) = r
{-# INLINE replyTo #-}

-- | Read the subscription id for the subscription on which this message
-- was received.
sid :: Msg -> Sid
sid (Msg _ _ s _) = s
{-# INLINE sid #-}

-- | Read the raw payload from a received message.
payload :: Msg -> Payload
payload (Msg _ _ _ p) = p
{-# INLINE payload #-}

-- | Decode a message's payload as JSON. Is using 'decode' for
-- the decoding.
jsonPayload :: FromJSON a => Msg -> Maybe a
jsonPayload = decode . payload
{-# INLINE jsonPayload #-}

-- | Decode a message's payload as JSON. Is using 'decode'' for
-- the decoding.
jsonPayload' :: FromJSON a => Msg -> Maybe a
jsonPayload' = decode' . payload
{-# INLINE jsonPayload' #-}
