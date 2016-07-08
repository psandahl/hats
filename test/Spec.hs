module Main
    ( main
    ) where

import Test.Framework (Test, defaultMain, testGroup)
import Test.Framework.Providers.HUnit (testCase)
import Test.Framework.Providers.QuickCheck2 (testProperty)

import NatsTests (subSingleMessage, subSingleMessageAsync)
import MessageProps (encodeDecodeMessage)

main :: IO ()
main = defaultMain testSuite

testSuite :: [Test]
testSuite =
    [ testGroup "Message property tests"
        [ testProperty "Encoding and decoding of Message"
                       encodeDecodeMessage
        ]
    , testGroup "Plain (non-JSON) NATS API tests"
        [ testCase "Subscription of a single message"
                   subSingleMessage
        , testCase "Async subscription of a single message"
                    subSingleMessageAsync
        ]
    ]
