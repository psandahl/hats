-- | Implement a proxy towards the NATS server daemon - gnatsd. Provide
-- functions to start and stop NATS. Will require the program gnatsd
-- to be found in the PATH environment variable.
module Gnatsd
    ( ProcessHandle
    , startGnatsd
    , stopGnatsd
    , withGnatsd
    ) where

import Control.Concurrent (threadDelay)
import Control.Exception (bracket)
import Control.Monad (void)
import System.Process ( ProcessHandle
                      , spawnProcess
                      , terminateProcess
                      , waitForProcess
                      )

-- | Start gnatsd using its default settings (i.e. open port 4222
-- for traffic). Give the server a little while to start.
startGnatsd :: IO ProcessHandle
startGnatsd = spawnProcess "gnatsd" [] <* waitAWhile

-- | Stop the the gnatsd server. Wait for it to stop.
stopGnatsd :: ProcessHandle -> IO ()
stopGnatsd proc = do
    terminateProcess proc
    void $ waitForProcess proc

-- | Convenience function to wrap things in a bracket.
withGnatsd :: IO () -> IO ()
withGnatsd action = bracket startGnatsd stopGnatsd (const action)

waitAWhile :: IO ()
waitAWhile = threadDelay 500000
