HATS - Haskell NATS client
===

Haskell client for the NATS messaging system (see https://nats.io for
a general introduction to NATS).

Examples:

This section gives a simple messaging example using this library. The
example requires the presence of a NATS server, running on localhost
using the default port 4222. If other host or port, adapt the
example.

```haskell
{-# LANGUAGE OverloadedStrings #-}
module Main
    ( main
    ) where

import Network.Nats
import Text.Printf

main :: IO ()
main =
    withNats defaultManagerSettings ["nats://localhost"] $ \nats -> do

       -- Subscribe to the topic "foo".
       (s, q) <- subscribe nats "foo" Nothing

       -- Publish to topic "foo", do not request a reply.
       publish nats "foo" Nothing "Some payload"

       -- Wait for a message, print the message's payload
       msg <- nextMsg q
       printf "Received %s\n" (show $ payload msg)

       -- Unsubscribe from topic "foo".
       unsubscribe nats s Nothing
```

Beside from the subscription mode where messages, synchronously, are
fetched from a queue there is also an asynchronous mode where each
request is handled immediately in their own thread.

```haskell
{-# LANGUAGE OverloadedStrings #-}
module Main
    ( main
    ) where

import Control.Monad
import Data.Maybe
import Network.Nats
import Text.Printf

main :: IO ()
main =
    withNats defaultManagerSettings ["nats://localhost"] $ \nats -> do
       
        -- A simple - asynchronous - help service that will answer
        -- requesters that give a reply topic with "I can help".
        s1 <- subscribeAsync nats "help" Nothing $ \msg -> do
            printf "Help service received: %s\n" (show $ payload msg)
            when (isJust $ replyTo msg) $
                publish nats (fromJust $ replyTo msg) Nothing "I can help"

        -- Subscribe to help replies.
        (s2, q) <- subscribe nats "help.reply" Nothing

        -- Request help.
        publish nats "help" (Just "help.reply") "Please ..."

        -- Wait for reply.
        msg <- nextMsg q
        printf "Received: %s\n" (show $ payload msg)

        -- Unsubscribe.
        unsubscribe nats s1 Nothing
        unsubscribe nats s2 Nothing
```
