{-# LANGUAGE OverloadedStrings #-}
module NatsTests
    ( subSingleMessage
    , subSingleMessageAsync
    ) where

import Control.Concurrent.MVar
import Control.Monad
import Test.HUnit

import Network.Nats

-- Subscriber on a topic and receive one message through a queue. Expect
-- the received 'Msg' to have the expected data.
subSingleMessage :: Assertion
subSingleMessage =
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
subSingleMessageAsync :: Assertion
subSingleMessageAsync =
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
        
defaultURI :: String
defaultURI = "nats://localhost:4222"
