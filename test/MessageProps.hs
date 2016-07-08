{-# LANGUAGE OverloadedStrings    #-}
{-# OPTIONS_GHC -fno-warn-orphans #-}
module MessageProps
    ( encodeDecodeMessage
    ) where

import Data.Attoparsec.ByteString.Char8
import Data.ByteString.Char8 (ByteString)
import Test.QuickCheck

import qualified Data.ByteString.Char8 as BS
import qualified Data.ByteString.Lazy.Char8 as LBS

import Network.Nats.Types (Sid)
import Network.Nats.Message.Message (Message (..), ProtocolError (..))
import Network.Nats.Message.Parser (parseMessage)
import Network.Nats.Message.Writer (writeMessage)

-- | Arbitrary instance for ProtocolError.
instance Arbitrary ProtocolError where
    arbitrary = elements [ minBound .. ]

-- | Arbitrary instance for Message.
instance Arbitrary Message where
    arbitrary = oneof [ arbitraryInfo
                      , arbitraryConnect
                      , arbitraryMsg
                      , arbitraryPub
                      , arbitrarySub
                      , arbitraryUnsub
                      , arbitraryPingPong
                      , arbitraryOk
                      , arbitraryErr
                      ]
       
-- | Arbitrary generation of Info messages.
arbitraryInfo :: Gen Message
arbitraryInfo =
    Info <$> perhaps valueString
         <*> perhaps valueString
         <*> perhaps valueString
         <*> perhaps valueString
         <*> perhaps posInt
         <*> arbitrary
         <*> arbitrary
         <*> arbitrary
         <*> arbitrary
         <*> perhaps posInt

-- | Arbitrary generation of Connect messages.
arbitraryConnect :: Gen Message
arbitraryConnect =
    Connect <$> arbitrary
            <*> arbitrary
            <*> arbitrary
            <*> perhaps valueString
            <*> perhaps valueString
            <*> perhaps valueString
            <*> perhaps valueString
            <*> perhaps valueString
            <*> perhaps valueString

-- | Arbitrary generation of Msg messages.
arbitraryMsg :: Gen Message
arbitraryMsg = Msg <$> alnumString
                   <*> sid
                   <*> perhaps alnumString
                   <*> payloadString

-- | Arbitrary generation of Pub messages.
arbitraryPub :: Gen Message
arbitraryPub = Pub <$> alnumString
                   <*> perhaps alnumString
                   <*> payloadString

-- | Arbitrary generation of Sub messages.
arbitrarySub :: Gen Message
arbitrarySub = Sub <$> alnumString 
                   <*> perhaps alnumString 
                   <*> sid

-- | Arbitrary generation of Sub messages.
arbitraryUnsub :: Gen Message
arbitraryUnsub = Unsub <$> sid
                       <*> perhaps posInt

-- | Arbitrary generation of Ping/Pong messages.
arbitraryPingPong :: Gen Message
arbitraryPingPong = oneof [ pure Ping, pure Pong ]

-- | Arbitrary generation of Ok messages.
arbitraryOk :: Gen Message
arbitraryOk = pure Ok

-- | Arbitrary generation of Err messages.
arbitraryErr :: Gen Message
arbitraryErr = Err <$> arbitrary

-- | Test by write a Message to ByteString, and parse it back again.
encodeDecodeMessage :: Message -> Bool
encodeDecodeMessage msg =
    let asByteString = LBS.toStrict $ writeMessage msg
    in verify (parse parseMessage asByteString)
    where
      verify :: IResult ByteString Message -> Bool
      verify result =
        case result of
            (Done _ msg2) -> msg == msg2
            (Partial g)   -> verify (g "")
            _             -> False

-- | Generate Maybe's for the tailor made generators.
perhaps :: Gen a -> Gen (Maybe a)
perhaps gen = oneof [ return Nothing, Just <$> gen ]

-- | Generate a ByteString which not contains any quote characters.
valueString :: Gen ByteString
valueString =
    BS.pack <$> listOf (elements selection)
    where
      selection :: [Char]
      selection = ['a'..'z'] ++ ['A'..'Z'] ++ ['0'..'9'] ++ "+-_!?*(){} "

payloadString :: Gen LBS.ByteString
payloadString = LBS.pack <$> listOf arbitrary

-- | Generate a non-empty ByteString which is plain alphanumeric.
alnumString :: Gen ByteString
alnumString =
    BS.pack <$> listOf1 (elements selection)
    where
      selection :: [Char]
      selection = ['a'..'z'] ++ ['A'..'Z'] ++ ['0'..'9'] 

-- | Generate a positive integer. Can be max size of Int.
posInt :: Gen Int
posInt = choose (0, maxBound)

-- | Generate a Sid
sid :: Gen Sid
sid = choose (0, maxBound)
