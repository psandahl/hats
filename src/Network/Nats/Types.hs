{-# LANGUAGE DeriveAnyClass #-}
-- | Base types for the messages and the API.
module Network.Nats.Types
    ( Topic
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

type Topic      = BS.ByteString
type Payload    = LBS.ByteString
type Sid        = Int64
type QueueGroup = BS.ByteString

data NatsException
    = HandshakeException
    deriving (Typeable, Show)

instance Exception NatsException

