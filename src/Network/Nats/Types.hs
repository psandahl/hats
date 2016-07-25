{-# LANGUAGE DeriveAnyClass #-}
-- |
-- Module:      Network.Nats.Types
-- Copyright:   (c) 2016 Patrik Sandahl
-- License:     MIT
-- Maintainer:  Patrik Sandahl <patrik.sandahl@gmail.com>
-- Stability:   experimental
-- Portability: portable
--
-- Base types for the library's API.
module Network.Nats.Types
    ( Msg (..)
    , JsonMsg (..)
    , Topic
    , Payload
    , Sid
    , QueueGroup
    , NatsException (..)
    ) where

import Control.Exception (Exception)
import Data.Typeable (Typeable)
import GHC.Int (Int64)

import qualified Data.ByteString as BS
import qualified Data.ByteString.Lazy as LBS

-- | A NATS message as received by the user.
data Msg = Msg !Topic !(Maybe Topic) {-# UNPACK #-} !Sid !Payload
    deriving (Eq, Show)

-- | A NATS message as received by the user, with payload encoded as
-- JSON. JSON handling is provided by "Data.Aeson".
data JsonMsg a =
    JsonMsg !Topic !(Maybe Topic) {-# UNPACK #-} !Sid !(Maybe a)
    deriving (Eq, Show)

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

