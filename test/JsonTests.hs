{-# LANGUAGE DeriveGeneric     #-}
{-# LANGUAGE OverloadedStrings #-}
module JsonTests
    ( recSingleJsonMessage
    , requestJsonMessage
    ) where

import Control.Monad (void)
import Data.Aeson
import Data.Maybe (fromJust)
import Data.Text (Text)
import GHC.Generics (Generic)
import Test.HUnit

import Gnatsd
import Network.Nats
 
data TestRec = TestRec
    { textVal :: !Text
    , intVal  :: !Int
    } deriving (Eq, Generic, Show)

instance FromJSON TestRec
instance ToJSON TestRec

-- | Subscribe on a topic and receive one Json message through a queue.
-- Expect the received 'JsonMsg' to echo the published payload.
recSingleJsonMessage, recSingleJsonMessage' :: Assertion
recSingleJsonMessage = withGnatsd recSingleJsonMessage'

recSingleJsonMessage' =
    withNats defaultManagerSettings [defaultURI] $ \nats -> do
        let topic'   = "test"
            payload' = TestRec { textVal = "Some Text"
                               , intVal  = 42
                               }

        (sid', queue) <- subscribe nats topic' Nothing
        publishJson nats topic' Nothing payload'

        -- Wait for the response ...
        msg <- nextMsg queue
        topic'   @=? topic msg
        Nothing  @=? replyTo msg
        sid'     @=? sid msg
        payload' @=? (fromJust $ jsonPayload msg)

-- | Request a topic. Excersize both the requestJson api and the
-- subscribeAsyncJson api, as the handler will modify the given Json
-- record.
requestJsonMessage, requestJsonMessage' :: Assertion
requestJsonMessage = withGnatsd requestJsonMessage'

requestJsonMessage' =
    withNats defaultManagerSettings [defaultURI] $ \nats -> do
        let topic'   = "test"
            payload1 = TestRec { textVal = "Some Text"
                               , intVal  = 42
                               }
            payload2 = TestRec { textVal = "Some Text"
                               , intVal  = 43
                               }
       
        -- Async handler that receive a TestRec and increments its
        -- intVal field before sending it back.
        void $ subscribeAsync nats topic' Nothing $
            \msg-> do
                let p     = fromJust $ jsonPayload msg
                    reply = p { intVal = intVal p + 1 }
                publishJson nats (fromJust $ replyTo msg) Nothing reply

        msg <- requestJson nats topic' payload1

        payload2 @=? (fromJust $ jsonPayload msg)
