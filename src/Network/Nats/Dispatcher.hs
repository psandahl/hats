-- |
-- Module:      Network.Nats.Dispatcher
-- Copyright:   (c) 2016 Patrik Sandahl
-- License:     MIT
-- Maintainer:  Patrik Sandahl <patrik.sandahl@gmail.com>
-- Stability:   experimental
-- Portability: portable
--
-- The dispatcher is receiving 'Downstream' messages from the NATS
-- server and dispatches them to their receivers.
module Network.Nats.Dispatcher
    ( Dispatcher
    , startDispatcher
    , stopDispatcher
    ) where

import Control.Concurrent (ThreadId, forkIO, killThread, myThreadId)
import Control.Concurrent.STM (atomically, writeTQueue)
import Control.Exception (SomeException, handle, throwTo)
import Control.Monad (void)
import Control.Monad.IO.Class (liftIO)
import Data.Conduit (Sink, ($$), (=$=), awaitForever)
import Data.Conduit.Attoparsec ( ParseError, PositionRange
                               , conduitParserEither
                               )

import Network.Nats.Conduit ( Downstream, Upstream
                            , streamSource, upstreamMessage
                            )
import Network.Nats.Subscriber ( Subscriber (..), SubscriberMap
                               , lookupSubscriber
                               )
import Network.Nats.Types (Msg (..), NatsException (..))
import Network.Nats.Message.Message (Message (..), ProtocolError (..))
import Network.Nats.Message.Parser (parseMessage)

-- | A data type to hold the 'ThreadId' for the dispatcher thread.
newtype Dispatcher = Dispatcher ThreadId

-- | Start the dispatcher thread. Give the dispatcher thread the callers
-- 'ThreadId', and in this case it is assumed that the caller is the
-- same thread as the caller of withNats. The caller thread is used in
-- case an 'AuthorizationException' need to be thrown.
startDispatcher :: Downstream -> Upstream -> SubscriberMap
                -> IO Dispatcher
startDispatcher downstream upstream subscriberMap = do
    caller <- myThreadId
    Dispatcher <$>
        forkIO (dispatcher caller downstream upstream subscriberMap)

-- | Kill the dispatcher thread.
stopDispatcher :: Dispatcher -> IO ()
stopDispatcher (Dispatcher t) = killThread t

-- | The dispatcher pipeline from the 'Downstream', through the message
-- parser and to the core dispatcher.
dispatcher :: ThreadId -> Downstream -> Upstream -> SubscriberMap -> IO ()
dispatcher caller downstream upstream subscriberMap =
    streamSource downstream              =$=
        conduitParserEither parseMessage $$
        messageSink caller upstream subscriberMap

-- | The message 'Sink'. Forever receive messages, if there are
-- parser error print those, otherwise just dispatch the message.
messageSink :: ThreadId -> Upstream -> SubscriberMap
            -> Sink (Either ParseError (PositionRange, Message)) IO ()
messageSink caller upstream subscriberMap =
    awaitForever $
        \eMsg -> case eMsg of
            Right (_, msg) -> liftIO $ dispatchMessage caller upstream
                                                       subscriberMap msg
            Left err       -> liftIO $ print err
{-# INLINE messageSink #-}

-- | Dispatch on 'M.Message. Handles 'MSG' and 'PING'.
dispatchMessage :: ThreadId -> Upstream -> SubscriberMap -> Message -> IO ()

-- Receive one 'MSG'. Lookup its 'Subscriber' and feed it with the
-- message. If no 'Subscriber' is found, the message is silently
-- discarded.
dispatchMessage _ _ subscriberMap (MSG topic sid replyTo payload) = do
    let msg = Msg topic replyTo sid payload
    maybe (return ()) (feedSubscriber msg) =<<
        lookupSubscriber subscriberMap sid

-- Handle 'PING' messages. Just reply with 'PONG'.
dispatchMessage _ upstream _ PING = upstreamMessage upstream PONG

-- Handle 'ERR' messages. If there are authorization violation, the
-- dispatcher will throw. Other errors are just logged for now.
dispatchMessage caller _ _ (ERR err)
    | err == AuthorizationViolation = throwTo caller AuthorizationException
    | otherwise                     = print err

-- Other are messages this dispatcher doesn't care about. The 'INFO'
-- message is handled by 'Connection' at connection handshake.
dispatchMessage _ _ _ _ = return ()
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
