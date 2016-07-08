{-# LANGUAGE RecordWildCards #-}
module Network.Nats.Dispatcher
    ( dispatcher
    ) where

import Control.Concurrent (forkIO)
import Control.Concurrent.STM (atomically, writeTQueue)
import Control.Exception (SomeException, handle)
import Control.Monad (void)
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
import Network.Nats.Subscriber ( Msg (..)
                               , Subscriber (..)
                               , SubscriberMap
                               , lookupSubscriber
                               )
import Network.Nats.Message.Parser (parseMessage)

import qualified Network.Nats.Message.Message as M

dispatcher :: Downstream -> Upstream -> SubscriberMap -> IO ()
dispatcher downstream upstream subscriberMap =
    streamSource downstream              =$= 
        conduitParserEither parseMessage $$ 
        messageSink upstream subscriberMap

messageSink :: Upstream -> SubscriberMap 
            -> Sink (Either ParseError (PositionRange, M.Message)) IO ()
messageSink upstream subscriberMap =
    awaitForever $
        \eMsg -> case eMsg of
            Right (_, msg) -> liftIO $ dispatchMessage upstream
                                                       subscriberMap msg
            Left err       -> liftIO $ putStrLn (show err)
{-# INLINE messageSink #-}

dispatchMessage :: Upstream -> SubscriberMap -> M.Message -> IO ()

dispatchMessage _ subscriberMap (M.Msg topic sid replyTo payload) = do
    let msg = Msg topic replyTo sid payload
    maybe (return ()) (feedSubscriber msg) =<< 
        lookupSubscriber subscriberMap sid

-- Handle 'M.Ping' messages. Just reply with 'M.Pong'.
dispatchMessage upstream _ M.Ping = upstreamMessage upstream M.Pong

-- Other are messages this dispatcher doesn't care about. The 'M.Info'
-- message is handled by 'Connection' at connection handshake.
dispatchMessage _ _ _ = return ()
{-# INLINE dispatchMessage #-}

feedSubscriber :: Msg -> Subscriber -> IO ()
feedSubscriber msg (Subscriber queue _) =
    atomically $ writeTQueue queue msg
feedSubscriber msg (AsyncSubscriber action _) =
    void $ forkIO $ asyncTrampoline (action msg)
{-# INLINE feedSubscriber #-}

asyncTrampoline :: IO () -> IO ()
asyncTrampoline action = allExceptions `handle` action
    where
      allExceptions :: SomeException -> IO ()
      allExceptions _ = return ()
