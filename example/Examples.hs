{-# LANGUAGE OverloadedStrings #-}
-- | A set of example programs to demonstrate NATS features and the
-- API of the "Network.Nats" library.
module Main
    ( main
    ) where

import Control.Exception
import Control.Monad
import Data.Maybe
import Network.Nats
import System.Environment
import Text.Printf

main :: IO ()
main =
    natsHandler `handle` do
        demo <- getArgs
        case demo of
            ["sync-sub"]    -> syncSub 
            ["async-sub"]   -> asyncSub
            ["async-req"]   -> asyncReq
            ["topic"]       -> topic'
            ["queue-group"] -> queueGroup
            _               -> mapM_ putStrLn usage
    where
      -- Take care of the exceptions that can be thrown out from within
      -- 'withNats'.
      natsHandler :: NatsException -> IO ()
      natsHandler e =
        case e of
            ConnectionGiveUpException -> putStrLn "No NATS connection!"
            AuthorizationException    -> putStrLn "Can't authorize!"
            URIError err              -> putStrLn err
            _                         -> throwIO e

-- | Simple messaging.
syncSub :: IO ()
syncSub =
    withNats defaultSettings ["nats://localhost"] $ \nats -> do

        -- Subscribe to the topic "foo".
        (s, q) <- subscribe nats "foo" Nothing

        -- Publish to topic "foo", do not request a reply.
        publish nats "foo" Nothing "Some payload"

        -- Wait for a message, print the message's payload
        msg <- nextMsg q
        printf "Received %s\n" (show $ payload msg)

        -- Unsubscribe from topic "foo".
        unsubscribe nats s Nothing

-- | Request help from a simple help service. The help service is
-- asynchronous.
asyncSub :: IO ()
asyncSub =
    withNats defaultSettings ["nats://localhost"] $ \nats -> do
       
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

        -- Unsubscribe from topics.
        unsubscribe nats s1 Nothing
        unsubscribe nats s2 Nothing

-- | As 'asyncSub', but using the 'request' function to simplify.
asyncReq :: IO ()
asyncReq =
    withNats defaultSettings ["nats://localhost"] $ \nats -> do
       
        -- A simple - asynchronous - help service that will answer
        -- requesters that give a reply topic with "I can help".
        s <- subscribeAsync nats "help" Nothing $ \msg -> do
            printf "Help service received: %s\n" (show $ payload msg)
            when (isJust $ replyTo msg) $
                publish nats (fromJust $ replyTo msg) Nothing "I can help"

        -- Request help.
        msg <- request nats "help" "Please ..."
        printf "Received: %s\n" (show $ payload msg)

        -- Unsubscribe.
        unsubscribe nats s Nothing

-- | Demonstration of topic strings and how they are interpreted by
-- NATS.
topic' :: IO ()
topic' =
    withNats defaultSettings ["nats://localhost"] $ \nats -> do

        -- "*" matches any token, at any level of the subject.
        (_, queue1) <- subscribe nats "foo.*.baz" Nothing
        (_, queue2) <- subscribe nats "foo.bar.*" Nothing

        -- ">" matches any length of the tail of the subject, and can
        -- only be the last token.
        (_, queue3) <- subscribe nats "foo.>" Nothing

        -- This publishing matches all the above.
        publish nats "foo.bar.baz" Nothing "Hello world"

        -- Show that the message showed up on all queues.
        forM_ [queue1, queue2, queue3] $ \queue -> do
            msg <- nextMsg queue
            printf "Received: %s\n" (show $ payload msg)

        -- The NATS server will purge the subscriptions once we
        -- have disconnected.

-- | Some fun with queue groups. Subscribers that share the same 
-- queue group will be load shared by NATS, i.e. only one subscriber
-- will answer each request.
queueGroup :: IO ()
queueGroup =
    withNats defaultSettings ["nats://localhost"] $ \nats -> do

        -- Install a couple of message echo workers. All sharing the
        -- same queue group.
        void $ subscribeAsync nats "echo" (Just "workers") $ worker nats "one"
        void $ subscribeAsync nats "echo" (Just "workers") $ worker nats "two"
        void $ subscribeAsync nats "echo" (Just "workers") $ worker nats "three"
        void $ subscribeAsync nats "echo" (Just "workers") $ worker nats "four"

        -- Request some echos. There will only be one of the echo
        -- workers answering each request.
        msg1 <- request nats "echo" "E1 E1 E1"
        printf "Received: %s\n" (show $ payload msg1)
        msg2 <- request nats "echo" "E2 E2 E2"
        printf "Received: %s\n" (show $ payload msg2)
    where
      worker :: Nats -> String -> Msg -> IO ()
      worker nats name msg = do
          printf "Request handled by %s\n" name
          when (isJust $ replyTo msg) $
              publish nats (fromJust $ replyTo msg) Nothing (payload msg)

usage :: [String]
usage =
    [ "Usage: hats-examples <example>"
    , ""
    , "Examples:"
    , ""
    , "sync-sub    : Demo of synchronous handling of messages."
    , "async-sub   : Demo of asynchronous handling of messages."
    , "async-req   : Demo of the request API."
    , "topic       : Demo of topic structure."
    , "queue-group : Demo of queue group handling."
    ]
