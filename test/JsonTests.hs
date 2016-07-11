{-# LANGUAGE DeriveGeneric     #-}
{-# LANGUAGE OverloadedStrings #-}
module JsonTests
    ( recSingleJsonMessage
    ) where

import Data.Aeson
import Data.Text (Text)
import GHC.Generics (Generic)
import Test.HUnit

import Network.Nats
 
data TestRec = TestRec
    { textVal :: !Text
    , intVal  :: !Int
    } deriving (Eq, Generic, Show)

instance FromJSON TestRec
instance ToJSON TestRec

-- | Subscribe on a topic and receive one Json message through a queue.
-- Expect the received 'JsonMsg' to echo the published payload.
recSingleJsonMessage :: Assertion
recSingleJsonMessage =
    withNats defaultManagerSettings [defaultURI] $ \nats -> do
        let topic   = "test"
            payload = TestRec { textVal = "Some Text"
                              , intVal  = 42
                              }

        (sid, queue) <- subscribe nats topic Nothing
        publishJson nats topic Nothing payload

        -- Wait for the response ...
        JsonMsg topic' replyTo sid' (Just payload') <- nextJsonMsg queue
        topic   @=? topic'
        Nothing @=? replyTo
        sid     @=? sid'
        payload @=? payload'

defaultURI :: String
defaultURI = "nats://localhost:4222"
