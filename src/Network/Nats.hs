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

    -- * Basic usage of this library
    -- $basic_usage

    -- * Usage of JSON encoding
    -- $json_usage

    -- * Wildcard subscriptions
    -- $wildcards

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
import Network.Nats.JsonApi ( publishJson, requestJson
                            , subscribeAsyncJson, nextJsonMsg
                            )
import Network.Nats.Subscriber (SubQueue)
import Network.Nats.Types ( Msg (..), JsonMsg (..), Sid, Payload
                          , Topic, QueueGroup, NatsException (..)
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
            -- 'defaultManagerSettings'.
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
-- The current version of this library does not yet support TLS.

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

-- $json_usage
--
-- There are built-in support for JSON encoded message payloads. The
-- JSON support is using "Data.Aeson".
--
-- This example show both a requester and a subscriber use JSON as
-- message payload. The toy example implements a service which
-- randomly generates a person, given the gender specification of
-- female or male.
--
-- The examples require the libraries "Data.Aeson", "Data.Text" and
-- "System.Random" to be installed.
--
-- > {-# LANGUAGE DeriveGeneric     #-}
-- > {-# LANGUAGE OverloadedStrings #-}
-- > module Main where
-- >
-- > import Control.Monad
-- > import Data.Aeson
-- > import Data.Text (Text)
-- > import GHC.Generics
-- > import Network.Nats
-- > import System.Random
-- > import Text.Printf
-- >
-- > data Gender = Female | Male
-- >    deriving (Eq, Generic, Show)
-- >
-- > data GenderSpec = GenderSpec
-- >    { gender :: !Gender }
-- >    deriving (Generic, Show)
-- >
-- > data Person = Person
-- >     { firstName :: !Text
-- >     , surname   :: !Text
-- >     , age       :: !Int
-- >     } deriving (Generic, Show)
-- >
-- > instance FromJSON Gender
-- > instance ToJSON Gender
-- > instance FromJSON GenderSpec
-- > instance ToJSON GenderSpec
-- > instance FromJSON Person
-- > instance ToJSON Person
-- >
-- > main :: IO ()
-- > main =
-- >     withNats defaultManagerSettings ["nats://localhost"] $ \nats -> do
-- >
-- >         -- Simple service that generates a random person from
-- >         -- a gender spec.
-- >         void $ subscribeAsyncJson nats "person" Nothing $
-- >             \(JsonMsg _ (Just reply) _ (Just spec)) ->
-- >                 publishJson nats reply Nothing =<< randomPerson spec
-- >
-- >         -- Request a female.
-- >         JsonMsg _ _ _ (Just resp)
-- >             <- requestJson nats "person" $ GenderSpec Female
-- >
-- >         printf "Received: %s\n" (showPerson resp)
-- >
-- >         -- And a male.
-- >         JsonMsg _ _ _ (Just resp')
-- >             <- requestJson nats "person" $ GenderSpec Male
-- >
-- >         printf "Received: %s\n" (showPerson resp')
-- >
-- > showPerson :: Person -> String
-- > showPerson = show
-- >
-- > randomPerson :: GenderSpec -> IO Person
-- > randomPerson spec
-- >     | gender spec == Female = Person <$> randomFrom females
-- >                                      <*> randomFrom surnames
-- >                                      <*> randomFrom [1..99]
-- >     | otherwise             = Person <$> randomFrom males
-- >                                      <*> randomFrom surnames
-- >                                      <*> randomFrom [1..99]
-- >
-- > males :: [Text]
-- > males = ["Curt", "David", "James", "Edward", "Karl"]
-- >
-- > females :: [Text]
-- > females = ["Claire", "Eva", "Sara", "Monica", "Lisa"]
-- >
-- > surnames :: [Text]
-- > surnames = ["Andersson", "Smith", "von Helsing", "Burns", "Baker"]
-- >
-- > randomFrom :: [a] -> IO a
-- > randomFrom xs = (!!) xs <$> randomRIO (0, length xs - 1)

-- $wildcards
--
-- When subscribing one can use wildcards to match variable parts of
-- a topic.
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
-- >     withNats defaultManagerSettings ["nats://localhost"] $ \nats -> do
-- >
-- >         -- "*" matches any token, at any level of the subject.
-- >         (_, queue1) <- subscribe nats "foo.*.baz" Nothing
-- >         (_, queue2) <- subscribe nats "foo.bar.*" Nothing
-- >
-- >         -- ">" matches any length of the tail of the subject, and can
-- >         -- only be the last token.
-- >         (_, queue3) <- subscribe nats "foo.>" Nothing
-- >
-- >         -- This publishing matches all the above.
-- >         publish nats "foo.bar.baz" Nothing "Hello world"
-- >
-- >         forM_ [queue1, queue2, queue3] $ \queue -> do
-- >             Msg _ _ _ payload <- nextMsg queue
-- >             printf "Received: %s\n" (show payload)
