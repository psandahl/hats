module Network.Nats
    ( Nats
    , Msg (..)
    , Sid
    , Payload
    , Topic
    , QueueGroup
    , SubQueue
    , ManagerConfiguration (..)
    , NatsException (URIError)
    , withNats
    , publish
    , subscribe
    , subscribeAsync
    , nextMsg
    , defaultManagerConfiguration
    ) where

import Control.Exception (bracket, throwIO)
import Data.Either (isLeft)
import Data.Maybe (catMaybes)
import Control.Monad (when)
import Network.URI (URI (..), parseAbsoluteURI)

import Network.Nats.Api ( Nats
                        , publish
                        , subscribe
                        , subscribeAsync
                        , nextMsg
                        , initNats
                        , termNats
                        )
import Network.Nats.ConnectionManager ( ManagerConfiguration (..)
                                      , defaultManagerConfiguration
                                      )
import Network.Nats.Subscriber (Msg (..), SubQueue)
import Network.Nats.Types ( Sid
                          , Payload
                          , Topic
                          , QueueGroup
                          , NatsException (..)
                          )

withNats :: ManagerConfiguration -> [String] -> (Nats -> IO a) -> IO a
withNats config ss action = do
    let uris = convertURIs ss
    when (isLeft uris) $ do
        let (Left err) = uris
        throwIO $ URIError err
    
    let (Right uris') = uris
    bracket (initNats config uris') termNats action

convertURIs :: [String] -> Either String [URI]
convertURIs [] = Left "Must be at least one URI"
convertURIs ss =
    let uris  = toURIs ss
        eqLen = length ss == length uris
    in if eqLen then Right uris
                else Left "Malformed URI(s)"
    where
      toURIs = filter expectedScheme . catMaybes . map parseAbsoluteURI

expectedScheme :: URI -> Bool
expectedScheme uri = uriScheme uri == "nats:" || uriScheme uri == "tls:"

