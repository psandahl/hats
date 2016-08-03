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
    -- * Limitations in implementation
    -- $limitations

    -- * Simple messaging example.
    -- $simple_messaging

    -- * Ascyncronous message handling.
    -- $async_handling

    -- * Convenience API for the request pattern.
    -- $request_pattern

    -- * Topic structure.
    -- $topic_structure

      Nats
    , Msg
    , Sid
    , Payload
    , Topic
    , QueueGroup
    , MsgQueue
    , ManagerSettings (..)
    , NatsException ( URIError, ConnectionGiveUpException
                    , AuthorizationException
                    )
    , SockAddr
    , withNats
    , publish
    , publishJson
    , subscribe
    , subscribeAsync
    , request
    , requestJson
    , unsubscribe
    , nextMsg
    , topic
    , replyTo
    , sid
    , payload
    , jsonPayload
    , jsonPayload'
    , defaultSettings
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
                                      , defaultSettings
                                      )
import Network.Nats.JsonApi (publishJson, requestJson)
import Network.Nats.Types ( Sid, Payload , Topic, QueueGroup
                          , NatsException (..), MsgQueue
                          , Msg, topic, replyTo
                          , sid, payload, jsonPayload, jsonPayload'
                          )

-- | Run an IO action while connection towards NATS is maintained. If
-- a NATS connection is lost, the connection manager will try to
-- reconnect the same or one of the other NATS servers
-- (as specified by the provided URI strings).
-- Strategies for reconnection is specified
-- in the 'ManagerSettings'. All subscriptions will be automatically
-- replayed once a new connection is made.
withNats :: ManagerSettings
            -- ^ Settings for the connection manager. Default
            -- 'ManagerSettings' can be obtained by
            -- 'defaultSettings'.
         -> [String]
            -- ^ A list of URI strings to specify the NATS servers
            -- available. If any URI string is malformed an 'URIError'
            -- exception is thrown. Parsing of URIs is performed using
            -- the 'parseAbsoluteURI' function.
         -> (Nats -> IO a)
            -- ^ The user provided action. Once the action is terminated
            -- the connection will close.
         -> IO a
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

-- $limitations
--
-- 1) The current version of this library does not yet support TLS.
--
-- 2) The current version of this library does not yet support 
-- authorization tokens (but support user names and passwords
-- in the URI strings).
--
-- $simple_messaging
--
-- This section gives a simple messaging example using this library. The
-- example requires the presence of a NATS server, running on localhost
-- using the default port 4222. If other host or port, adapt the
-- example.
--
-- > {-# LANGUAGE OverloadedStrings #-}
-- > module Main
-- >    ( main
-- >    ) where
-- >
-- > import Network.Nats
-- > import Text.Printf
-- >
-- > main :: IO ()
-- > main =
-- >    withNats defaultSettings ["nats://localhost"] $ \nats -> do
-- >
-- >        -- Subscribe to the topic "foo".
-- >        (s, q) <- subscribe nats "foo" Nothing
-- >
-- >        -- Publish to topic "foo", do not request a reply.
-- >        publish nats "foo" Nothing "Some payload"
-- >
-- >        -- Wait for a message, print the message's payload
-- >        msg <- nextMsg q
-- >        printf "Received %s\n" (show $ payload msg)
-- >
-- >        -- Unsubscribe from topic "foo".
-- >        unsubscribe nats s Nothing
--
-- $async_handling
--
-- Beside from the subscription mode where messages, synchronously, are
-- fetched from a queue there is also an asynchronous mode where each
-- request is handled immediately in their own thread.
--
-- > {-# LANGUAGE OverloadedStrings #-}
-- > module Main
-- >    ( main
-- >    ) where
-- >
-- > import Control.Monad
-- > import Data.Maybe
-- > import Network.Nats
-- > import Text.Printf
-- >
-- > main :: IO ()
-- > main =
-- >    withNats defaultSettings ["nats://localhost"] $ \nats -> do
-- >       
-- >        -- A simple - asynchronous - help service that will answer
-- >        -- requesters that give a reply topic with "I can help".
-- >        s1 <- subscribeAsync nats "help" Nothing $ \msg -> do
-- >            printf "Help service received: %s\n" (show $ payload msg)
-- >            when (isJust $ replyTo msg) $
-- >                publish nats (fromJust $ replyTo msg) Nothing "I can help"
-- >
-- >        -- Subscribe to help replies.
-- >        (s2, q) <- subscribe nats "help.reply" Nothing
-- >
-- >        -- Request help.
-- >        publish nats "help" (Just "help.reply") "Please ..."
-- >
-- >        -- Wait for reply.
-- >        msg <- nextMsg q
-- >        printf "Received: %s\n" (show $ payload msg)
-- >
-- >        -- Unsubscribe.
-- >        unsubscribe nats s1 Nothing
-- >        unsubscribe nats s2 Nothing
--
-- $request_pattern
--
-- In the example above there's a common request pattern. Sending a
-- message to a topic, requesting a reply, subscribing to the reply topic,
-- receiving the reply message and then unsubscribe from the reply topic.
--
-- This pattern can be handled more simply using the 'request' function.
--
-- > {-# LANGUAGE OverloadedStrings #-}
-- > module Main
-- >    ( main
-- >    ) where
-- >
-- > import Control.Monad
-- > import Data.Maybe
-- > import Network.Nats
-- > import Text.Printf
-- >
-- > main :: IO ()
-- > main =
-- >    withNats defaultSettings ["nats://localhost"] $ \nats -> do
-- > 
-- >        -- A simple - asynchronous - help service that will answer
-- >        -- requesters that give a reply topic with "I can help".
-- >        s <- subscribeAsync nats "help" Nothing $ \msg -> do
-- >            printf "Help service received: %s\n" (show $ payload msg)
-- >            when (isJust $ replyTo msg) $
-- >                publish nats (fromJust $ replyTo msg) Nothing "I can help"
-- >
-- >        -- Request help.
-- >        msg <- request nats "help" "Please ..."
-- >        printf "Received: %s\n" (show $ payload msg)
-- >
-- >        -- Unsubscribing the help service only.
-- >        unsubscribe nats s Nothing
--
-- $topic_structure
--
-- Topic structure is tree like similar to file systems, or the Haskell
-- module structure, and components in the tree is separated by dots.
-- A subscriber of a topic can use wildcards to specify patterns.
--
-- > {-# LANGUAGE OverloadedStrings #-}
-- > module Main
-- >    ( main
-- >    ) where
-- >
-- > import Control.Monad
-- > import Data.Maybe
-- > import Network.Nats
-- > import Text.Printf
-- >
-- > main :: IO ()
-- > main =
-- >    withNats defaultSettings ["nats://localhost"] $ \nats -> do
-- > 
-- >        -- "*" matches any token, at any level of the subject.
-- >        (_, queue1) <- subscribe nats "foo.*.baz" Nothing
-- >        (_, queue2) <- subscribe nats "foo.bar.*" Nothing
-- >
-- >        -- ">" matches any length of the tail of the subject, and can
-- >        -- only be the last token.
-- >        (_, queue3) <- subscribe nats "foo.>" Nothing
-- >
-- >        -- This publishing matches all the above.
-- >        publish nats "foo.bar.baz" Nothing "Hello world"
-- >
-- >        -- Show that the message showed up on all queues.
-- >        forM_ [queue1, queue2, queue3] $ \queue -> do
-- >            msg <- nextMsg queue
-- >            printf "Received: %s\n" (show $ payload msg)
