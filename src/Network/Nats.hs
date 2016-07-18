-- |
-- Module:      Network.Nats
-- Copyright:   (c) 2016 Patrik Sandahl
-- License:     MIT
-- Maintainer:  Patrik Sandahl <patrik.sandahl@gmail.com>
-- Stability:   experimental
-- Portability: portable
--
-- A Haskell client for the NATS messaging system.
-- See <https://nats.io> for general information and documentation.
module Network.Nats
    (
    -- * Basic usage of this library
    -- $basic_usage

    -- ** Obtaining a Nats handle
    -- $obtaining_nats
      Nats
    , Msg (..)
    , JsonMsg (..)
    , Sid
    , Payload
    , Topic
    , QueueGroup
    , SubQueue
    , ManagerSettings (..)
    , NatsException (URIError)
    , SockAddr
    , withNats
    , publish
    , publishJson
    , subscribe
    , subscribeAsync
    , subscribeAsyncJson
    , request
    , requestJson
    , unsubscribe
    , nextMsg
    , nextJsonMsg
    , defaultManagerSettings
    ) where

import Control.Exception (bracket, throwIO)
import Data.Maybe (mapMaybe)
import Network.URI (URI (..), parseAbsoluteURI)

import Network.Nats.Api ( Nats, publish, subscribe, subscribeAsync
                        , request, unsubscribe, nextMsg
                        , initNats, termNats
                        )
import Network.Nats.ConnectionManager ( ManagerSettings (..)
                                      , SockAddr
                                      , defaultManagerSettings
                                      )
import Network.Nats.JsonApi ( JsonMsg (..), publishJson, requestJson
                            , subscribeAsyncJson, nextJsonMsg
                            )
import Network.Nats.Subscriber (Msg (..), SubQueue)
import Network.Nats.Types ( Sid, Payload, Topic, QueueGroup
                          , NatsException (..)
                          )

-- | Run an IO action while connected to a NATS server. Default
-- 'ManagerSettings' can be given by the 'defaultManagerSettings'
-- function.
--
-- There must be at least one URI string for specifying connection(s) to
-- NATS. The only URI schemes accepted are nats and tls.
--
-- The connection towards NATS will be termated once the action has
-- finished.
withNats :: ManagerSettings -> [String] -> (Nats -> IO a) -> IO a
withNats settings uriStrings action =
    either (throwIO . URIError)
           (\uris -> bracket (initNats settings uris) termNats action)
           (convertURIs uriStrings)

-- | Convert a list of strings to a list of 'URI'. If there are
-- errors during the conversion an error description is returned.
convertURIs :: [String] -> Either String [URI]
convertURIs [] = Left "Must be at least one URI"
convertURIs ss =
    let uris   = toURIs ss
        eqLen  = length ss == length uris
        toURIs = filter expectedScheme . mapMaybe parseAbsoluteURI
    in if eqLen then Right uris
                else Left "Malformed URI(s)"

-- | Only expect the schemes of nats or tls.
expectedScheme :: URI -> Bool
expectedScheme uri = uriScheme uri == "nats:" || uriScheme uri == "tls:"

-- $basic_usage
--
-- This section gives examples on basic usage of this library. All
-- examples requires the presence of a NATS server.
--
-- The API provided by this library requires that the user get hold
-- of a 'Nats' handle, a data structure opaque to the user.

-- $obtaining_nats
--
-- To obtain a 'Nats' handle, use 'withNats' and provide an IO action
-- that will take the 'Nats' handle as input value. The action can
-- either be a lambda or a named function.
--
-- The other argument given to 'withNats' are settings for the library's
-- connection manager and a list of URI strings describing available
-- NATS servers.
--
-- To get hold of the default 'ManagerSettings' just call
-- 'defaultManagerSettings'.
--
-- If you have a NATS server running on localhost, binding to port 4222,
-- a valid URI string is nats://localhost:4222.
--
-- > withNats defaultManagerSettings ["nats://localhost"] $ \nats -> do
-- >   -- Do stuff with the handle. Can only be used inside withNats
--
-- Or
--
-- > withNats defaultManagerSettings ["nats://localhost"] natsApp
-- >
-- > natsApp :: Nats -> IO ()
-- > natsApp nats = -- Do stuff ...
