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
-- This section gives examples on basic usage of this library. The
-- example requires the presence of a NATS server, running on localhost
-- using the default port 4222. If other host or port, adapt the
-- example.
--
-- > {-# LANGUAGE OverloadedStrings #-}
-- > module Main where
-- >
-- > import Control.Monad
-- > import Network.Nats
-- > import Text.Printf
-- >
-- > main :: IO ()
-- > main =
-- >   -- The connection will close when the action has finished.
-- >   withNats defaultManagerSettings ["nats://localhost"] $ \nats -> do
-- >
-- >       -- Simple publisher.
-- >       publish nats "foo" Nothing "Hello world"
-- >
-- >       -- Simple async subscriber.
-- >       void $ subscribeAsync nats "foo" Nothing $
-- >           \(Msg _ _ _ payload) ->
-- >               printf "(Async) Received a message: %s\n" (show payload)
-- >
-- >       -- | Simple sync subscriber.
-- >       (sid, queue) <- subscribe nats "foo" Nothing
-- >       Msg _ _ _ payload <- nextMsg queue
-- >
-- >       -- Wait for the async handler's printout. Then press a key.
-- >       void $ getChar
-- >
-- >       printf "(Sync) Received a message: %s\n" (show payload)
-- >
-- >       -- Unsubscribe.
-- >       unsubscribe nats sid Nothing
-- >
-- >       -- Replies (to the below request).
-- >       void $ subscribeAsync nats "help" Nothing $
-- >           \(Msg _ (Just reply) _ _) ->
-- >               publish nats reply Nothing "I can help"
-- >
-- >       -- Request.
-- >       (Msg _ _ _ response) <- request nats "help" "Help me"
-- >       printf "(Req) Received a message: %s\n" (show response)
-- >
-- >       -- Press a key to terminate program.
-- >       void $ getChar
