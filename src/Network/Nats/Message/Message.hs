{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric  #-}
-- |
-- Module:      Network.Nats.Message.Message
-- Copyright:   (c) 2016 Patrik Sandahl
-- License:     MIT
-- Maintainer:  Patrik Sandahl <patrik.sandahl@gmail.com>
-- Stability:   experimental
-- Portability: portable
--
-- Message definitions for the NATS protocol.
module Network.Nats.Message.Message
    ( Message (..)
    , ProtocolError (..)
    ) where

import Control.DeepSeq (NFData)
import GHC.Generics (Generic)
import qualified Data.ByteString as BS

import Network.Nats.Types (Topic, Payload, Sid, QueueGroup)

-- | Protocol error enumeration.
data ProtocolError
    = UnknownProtocolOperation
    | AuthorizationViolation
    | AuthorizationTimeout
    | ParserError
    | StaleConnection
    | SlowConsumer
    | MaximumPayloadExceeded
    | InvalidSubject
    deriving (Bounded, Enum, Eq, Generic, NFData, Show)

-- | The kind of messages that can be exchanged between the NATS server
-- and a NATS client.
-- Some of the documentation strings are taken from:
-- <https://nats.io/documentation/internals/nats-protocol/>
data Message =
    -- | As soon as the server accepts a connection from the client, it
    -- will send information about itself and the configuration and
    -- security requirements that are necessary for the client to
    -- successfully authenticate with the server and
    -- exchange messages.
    INFO { serverId           :: !(Maybe BS.ByteString)
           -- ^ The unique identifier of the NATS server.
         , serverVersion      :: !(Maybe BS.ByteString)
           -- ^ The version of the NATS server.
         , goVersion          :: !(Maybe BS.ByteString)
           -- ^ The version of golang the server was built with.
         , serverHost         :: !(Maybe BS.ByteString)
           -- ^ The IP address of the NATS server host.
         , serverPort         :: !(Maybe Int)
           -- ^ The port number the NATS server is configured to listen on.
         , serverAuthRequired :: !(Maybe Bool)
           -- ^ If set, the client should try to authenticate.
         , serverSslRequired  :: !(Maybe Bool)
           -- ^ If set, the client must authenticate using SSL.
         , serverTlsRequired  :: !(Maybe Bool)
         , serverTlsVerify    :: !(Maybe Bool)
         , maxPayload         :: !(Maybe Int)
           -- ^ Maximum payload size that server will accept from client.
         }

    -- | The CONNECT message is the reply to the Info message. Once the
    -- client has established a TCP/IP socket connection with the NATS
    -- server, and an Info message has been received from the server,
    -- the client may sent a Connect message to the NATS server to
    -- provide more information about the current connection as
    -- well as security information.
  | CONNECT { clientVerbose     :: !(Maybe Bool)
              -- ^ Turns on +OK protocol acknowledgements.
            , clientPedantic    :: !(Maybe Bool)
              -- ^ Turns on additional strict format checking.
            , clientSslRequired :: !(Maybe Bool)
              -- ^ Indicates whether the client requires an SSL connection.
            , clientAuthToken   :: !(Maybe BS.ByteString)
              -- ^ Client authorization token.
            , clientUser        :: !(Maybe BS.ByteString)
              -- ^ Connection username (if auth_required is set).
            , clientPass        :: !(Maybe BS.ByteString)
              -- ^ Connection password (if auth_required is set).
            , clientName        :: !(Maybe BS.ByteString)
              -- ^ Optional client name.
            , clientLang        :: !(Maybe BS.ByteString)
              -- The implementation of the client.
            , clientVersion     :: !(Maybe BS.ByteString)
              -- ^ The version of the client.
            }

    -- | The MSG message carries payload from the server to the client.
    -- subject: Subject name this message was received on.
    -- sid: The unique alphanumeric subscription ID of the subject.
    -- reply-to: The inbox subject on which the publisher is listening
    -- for responses.
    -- #bytes: Implicit by the length of the payload.
    -- payload: The message payload data.
  | MSG !Topic {-# UNPACK #-} !Sid !(Maybe Topic) !Payload

    -- | The PUB message publishes the message payload to the given
    -- subject name. If a reply subject is supplied, it will be
    -- delivered to eligible subscribers along with the supplied
    -- payload. Payload can be zero size.
    -- subject: The destination subject to publish to.
    -- reply-to: The reply inbox subject that subscribers can use to
    -- send a response back to the publisher/requestor.
    -- #bytes: Implicit by the length of payload.
    -- payload: The message payload data.
  | PUB !Topic !(Maybe Topic) !Payload

    -- | The SUB message initiates a subscription to a subject,
    -- optionally joining a distributed queue group.
    -- subject: The subject name to subscribe to.
    -- (Optional) queue group: If specified, the subscriper will join 
    -- this queue group.
    -- sid: A unique alphanumeric SubscriptionId.
  | SUB !Topic !(Maybe QueueGroup) {-# UNPACK #-} !Sid

    -- | The UNSUB message unsubscribes the connection from the specified
    -- subject, or auto-unsubscribes after the specified number of 
    -- messages has been received.
  | UNSUB {-# UNPACK #-} !Sid !(Maybe Int)

    -- | The PING and PONG messages are the keep-alive mechanism between
    -- the client and the server. The server will continously send
    -- Ping messages to the client. If the client does not reply
    -- within time the connection is terminated by the server.
  | PING
  | PONG

    -- | When the verbose (clientVerbose) option is set to true, the
    -- server acknowledges each well-formed prototol message from the
    -- client with a +OK message.
  | OK

    -- | The -ERR message is used by the server indicate a protocol,
    -- authorization, or other runtime connection error to the client.
    -- Most of those errors result in the server closing the
    -- connection. InvalidSubject is the exception.
  | ERR !ProtocolError
    deriving (Eq, Generic, NFData, Show)
