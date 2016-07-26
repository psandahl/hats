{-# LANGUAGE OverloadedStrings #-}
module ReconnectionTests
    ( subscribeAndReconnect
    , connectionGiveUp
    ) where

import Control.Concurrent
import Control.Exception
import Control.Monad (when)
import Data.Maybe (isNothing)
import System.Timeout (timeout)
import Test.HUnit

import Gnatsd
import Network.Nats

-- | Subscribe to three topics. Take down the current NATS connection,
-- force a reconnection, publish to the topics and test that the
-- messages are received.
subscribeAndReconnect :: Assertion
subscribeAndReconnect = do
    connect <- newEmptyMVar
    let settings = defaultManagerSettings
                       { connectedTo = connected connect
                       }
    g1 <- startGnatsd
    withNats settings [defaultURI] $ \nats -> do

        -- Ok, just wait for the first connect.
        c1 <- timeout oneSec $ takeMVar connect
        when (isNothing c1) $ do
            stopGnatsd g1
            assertFailure "Shall have connected :-("

        -- Subscribe to three topics.
        (_, queue1) <- subscribe nats "topic1" Nothing
        (_, queue2) <- subscribe nats "topic2" Nothing
        (_, queue3) <- subscribe nats "topic3" Nothing

        -- Let things have the time to go on network.
        threadDelay 100000

        -- Take down gnatsd.
        stopGnatsd g1

        -- Start a new instance.
        g2 <- startGnatsd

        -- Publish to the topics.
        publish nats "topic1" Nothing "payload1"
        publish nats "topic2" Nothing "payload2"
        publish nats "topic3" Nothing "payload3"

        m1 <- timeout oneSec $ nextMsg queue1
        when (isNothing m1) $ do
            stopGnatsd g2
            assertFailure "Shall have received a message (m1)"

        m2 <- timeout oneSec $ nextMsg queue2
        when (isNothing m2) $ do
            stopGnatsd g2
            assertFailure "Shall have received a message (m2)"

        m3 <- timeout oneSec $ nextMsg queue3
        when (isNothing m3) $ do
            stopGnatsd g2
            assertFailure "Shall have received a message (m3)"

        -- Survived this far? Success, but terminate gnatsd before quitting.
        stopGnatsd g2

connected :: MVar () -> SockAddr -> IO ()
connected sync _ = putMVar sync ()

-- | Test that when the reconnection logic gives up, a
-- ConnectionGiveUpException is thrown out of the withNats function.
connectionGiveUp :: Assertion
connectionGiveUp =
    (\ConnectionGiveUpException -> return ()) `handle` do
        withNats defaultManagerSettings [defaultURI] $ \_ ->
            threadDelay oneSec

        assertFailure "Shall never come here!"

oneSec :: Int
oneSec = 1000000

