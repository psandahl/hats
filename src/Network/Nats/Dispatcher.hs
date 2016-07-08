{-# LANGUAGE RecordWildCards #-}
-- | The dispatcher is receiving 'Downstream' messages from the NATS
-- server and dispatches them to their receivers.
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

-- | The dispatcher pipeline from the 'Downstream', through the message
-- parser and to the core dispatcher.
dispatcher :: Downstream -> Upstream -> SubscriberMap -> IO ()
dispatcher downstream upstream subscriberMap =
    streamSource downstream              =$= 
        conduitParserEither parseMessage $$ 
        messageSink upstream subscriberMap

-- | The message 'Sink'. Forever receive messages, if there are
-- parser error print those, otherwise just dispatch the message.
messageSink :: Upstream -> SubscriberMap 
            -> Sink (Either ParseError (PositionRange, M.Message)) IO ()
messageSink upstream subscriberMap =
    awaitForever $
        \eMsg -> case eMsg of
            Right (_, msg) -> liftIO $ dispatchMessage upstream
                                                       subscriberMap msg
            Left err       -> liftIO $ putStrLn (show err)
{-# INLINE messageSink #-}

-- | Dispatch on 'M.Message. Handles 'M.Msg' and 'M.Ping'.
dispatchMessage :: Upstream -> SubscriberMap -> M.Message -> IO ()

-- Receive one 'M.Msg'. Lookup its 'Subscriber' and feed it with the 
-- message. If no 'Subscriber' is found, the message is silently
-- discarded.
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

-- | Feed a 'Subscriber' with a 'Msg'.
feedSubscriber :: Msg -> Subscriber -> IO ()

-- Queue subscriber. Write the queue.
feedSubscriber msg (Subscriber queue _) =
    atomically $ writeTQueue queue msg

-- Async subscriber. Fork a handler.
feedSubscriber msg (AsyncSubscriber action _) =
    void $ forkIO $ asyncTrampoline (action msg)
{-# INLINE feedSubscriber #-}

-- | Trampoline to handle exceptions from an async handler.
asyncTrampoline :: IO () -> IO ()
asyncTrampoline action = allExceptions `handle` action
    where
      allExceptions :: SomeException -> IO ()
      allExceptions e = putStrLn $ "Async handler crash: " ++ show e
