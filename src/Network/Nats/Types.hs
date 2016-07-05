-- | Base types for the messages and the API.
module Network.Nats.Types
    ( Topic
    , Payload
    , Sid
    , QueueGroup
    ) where

import GHC.Int (Int64)

import qualified Data.ByteString as BS
import qualified Data.ByteString.Lazy as LBS

type Topic      = BS.ByteString
type Payload    = LBS.ByteString
type Sid        = Int64
type QueueGroup = BS.ByteString

