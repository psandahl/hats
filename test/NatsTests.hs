{-# LANGUAGE OverloadedStrings #-}
module NatsTests
    ( recSingleMessage
    , recSingleMessageAsync
    , recMessagesWithTmo
    , unsubscribeToTopic
    ) where

import Control.Concurrent.MVar
import Control.Monad
import System.Timeout (timeout)
import Test.HUnit

import Network.Nats

-- Subscriber on a topic and receive one message through a queue. Expect
-- the received 'Msg' to have the expected data.
recSingleMessage :: Assertion
recSingleMessage =
    void $ withNats defaultManagerConfiguration [defaultURI] $ \nats -> do
        let topic   = "test"
            replyTo = Nothing
            payload = "test message"

        (sid, queue) <- subscribe nats topic Nothing
        publish nats topic replyTo payload

        -- Wait for the message ...
        Msg topic' replyTo' sid' payload' <- nextMsg queue
        sid     @=? sid'
        topic   @=? topic'
        replyTo @=? replyTo'
        payload @=? payload'

-- Subscribe on a topic and receive one message asynchronously. Expect
-- the message receiver to receive the expected 'Msg' data.
recSingleMessageAsync :: Assertion
recSingleMessageAsync =
    void $ withNats defaultManagerConfiguration [defaultURI] $ \nats -> do
        let topic   = "test"
            replyTo = Nothing
            payload = "test message"
        recData <- newEmptyMVar
        sid     <- subscribeAsync nats topic Nothing $ receiver recData
        publish nats topic replyTo payload

        -- Wait for the MVar ...
        (sid', topic', replyTo', payload') <- takeMVar recData
        sid     @=? sid'
        topic   @=? topic'
        replyTo @=? replyTo'
        payload @=? payload'
    where
      receiver :: MVar (Sid, Topic, Maybe Topic, Payload) -> Msg -> IO ()
      receiver recData (Msg topic replyTo sid payload) =
          putMVar recData (sid, topic, replyTo, payload)

-- | Subscribe to a topic, and send two messages to the topic. When
-- reading trying to read a third message from the queue, it shall
-- block. To handle the blocking 'timeout' is used.
recMessagesWithTmo :: Assertion
recMessagesWithTmo =
    void $ withNats defaultManagerConfiguration [defaultURI] $ \nats -> do
        let topic    = "test"
            payload1 = "test message"
            payload2 = "test message 2"

        (sid, queue) <- subscribe nats topic Nothing
        publish nats topic Nothing payload1
        publish nats topic Nothing payload2

        -- Wait for the messages ...
        Just (Msg topic' _ sid' payload1') <-
            timeout oneSec $ nextMsg queue
        sid      @=? sid'
        topic    @=? topic'
        payload1 @=? payload1'

        Just (Msg topic'' _ sid'' payload2') <-
            timeout oneSec $ nextMsg queue
        sid      @=? sid''
        topic    @=? topic''
        payload2 @=? payload2'

        -- This time there shall be a timeout.
        reply <- timeout oneSec $ nextMsg queue
        Nothing @=? reply

-- | Subscribe to a topic, then unsubscribe to it before publishing
-- a message. No message shall show up in the queue.
unsubscribeToTopic :: Assertion
unsubscribeToTopic =
    void $ withNats defaultManagerConfiguration [defaultURI] $ \nats -> do
        let topic = "test"

        (sid, queue) <- subscribe nats topic Nothing
        unsubscribe nats sid Nothing
        publish nats topic Nothing "shall never arrive"

        -- As the test case is unsubscribed, nothing shall show up.
        reply <- timeout oneSec $ nextMsg queue
        Nothing @=? reply
        
defaultURI :: String
defaultURI = "nats://localhost:4222"

oneSec :: Int
oneSec = 1000000
