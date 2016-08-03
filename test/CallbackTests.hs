module CallbackTests
    ( callingCallbacks
    ) where

import Control.Concurrent.MVar
import Control.Monad (when)
import Data.Maybe (isNothing, isJust)
import System.Timeout (timeout)
import Test.HUnit

import Gnatsd
import Network.Nats

-- | Check that callbacks are called when needed at connection and
-- disconnection.
callingCallbacks :: Assertion
callingCallbacks = do
    connect    <- newEmptyMVar
    disconnect <- newEmptyMVar
    let settings = defaultSettings
                       { connectedTo      = connected connect
                       , disconnectedFrom = disconnected disconnect
                       }
    g1 <- startGnatsd
    withNats settings [defaultURI] $ \_nats -> do
        
        -- Wait for connection.
        c1 <- timeout oneSec $ takeMVar connect
        when (isNothing c1) $ do
            stopGnatsd g1
            assertFailure "Shall have connectedTo callback"

        -- Check that no disconnect has happen.
        d1 <- tryTakeMVar disconnect
        when (isJust d1) $ do
            stopGnatsd g1
            assertFailure "Shall have no disconnectedFrom callback"

        -- Shoot down gnatsd ...
        stopGnatsd g1

        -- Now a disconnect shall have happen.
        d2 <- timeout oneSec $ takeMVar disconnect
        when (isNothing d2) $
            assertFailure "Shall have disconnectedFrom callback"

        -- Start gnatsd again ...
        g2 <- startGnatsd

        -- Check that we have a new connect callback.
        c2 <- timeout oneSec $ takeMVar connect
        when (isNothing c2) $ do
            stopGnatsd g2
            assertFailure "Shall have connectedTo callback"

        -- Done. Close.
        stopGnatsd g2

oneSec :: Int
oneSec = 1000000

connected :: MVar () -> SockAddr -> IO ()
connected sync sockAddr = do
    putStrLn $ "Connected to: " ++ show sockAddr
    putMVar sync ()

disconnected :: MVar () -> SockAddr -> IO ()
disconnected sync sockAddr = do
    putStrLn $ "Disconnected from: " ++ show sockAddr
    putMVar sync ()

