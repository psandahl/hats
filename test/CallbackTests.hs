module CallbackTests
    ( connectToCallback
    ) where

import Control.Concurrent.MVar
import System.Timeout (timeout)
import Test.HUnit

import Network.Nats

-- | Check that the connectTo callback is called at the first connect
-- when entering withNats.
connectToCallback :: Assertion
connectToCallback = do
    connect <- newEmptyMVar
    let settings = defaultManagerSettings
                       { connectedTo = callback connect
                       }

    withNats settings [defaultURI] $ \_nats -> do
        -- Wait for connection ...
        c <- timeout oneSec $ takeMVar connect
        Just () @=? c

oneSec :: Int
oneSec = 1000000

callback :: MVar () -> SockAddr -> IO ()
callback sync sockAddr = do
    putStrLn $ "Connected to: " ++ show sockAddr
    putMVar sync ()

defaultURI :: String
defaultURI = "nats://localhost:4222"
