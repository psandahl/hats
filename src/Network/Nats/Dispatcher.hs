module Network.Nats.Dispatcher
    ( dispatcher
    ) where

import Control.Monad.IO.Class (liftIO)
import Data.Conduit (Sink, ($$), (=$=), awaitForever)
import Data.Conduit.Attoparsec ( ParseError
                               , PositionRange
                               , conduitParserEither
                               )

import Network.Nats.Conduit ( Downstream
                            , Upstream
                            , streamSource
                            , upstreamMessage
                            )
import Network.Nats.Subscriber (SubscriberMap)
import Network.Nats.Message.Message (Message (..))
import Network.Nats.Message.Parser (parseMessage)

dispatcher :: Downstream -> Upstream -> SubscriberMap -> IO ()
dispatcher downstream upstream subscriberMap =
    streamSource downstream              =$= 
        conduitParserEither parseMessage $$ 
        messageSink upstream subscriberMap

messageSink :: Upstream -> SubscriberMap 
            -> Sink (Either ParseError (PositionRange, Message)) IO ()
{-# INLINE messageSink #-}
messageSink upstream subscriberMap =
    awaitForever $
        \eMsg -> case eMsg of
            Right (_, msg) -> liftIO $ dispatchMessage upstream
                                                       subscriberMap msg
            Left err       -> liftIO $ putStrLn (show err)

dispatchMessage :: Upstream -> SubscriberMap -> Message -> IO ()
{-# INLINE dispatchMessage #-}
dispatchMessage upstream _ Ping = upstreamMessage upstream Pong
