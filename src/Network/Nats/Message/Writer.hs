{-# LANGUAGE ExistentialQuantification #-}
{-# LANGUAGE OverloadedStrings         #-}
{-# LANGUAGE RecordWildCards           #-}
-- |
-- Module:      Network.Nats.Message.Writer
-- Copyright:   (c) 2016 Patrik Sandahl
-- License:     MIT
-- Maintainer:  Patrik Sandahl <patrik.sandahl@gmail.com>
-- Stability:   experimental
-- Portability: portable
--
-- Serialize NATS 'Message's to 'LBS.ByteString's.
module Network.Nats.Message.Writer
    ( writeMessage
    ) where

import Data.ByteString (ByteString)
import Data.ByteString.Builder
import Data.Monoid ((<>))
import Data.List (foldl', intersperse)

import qualified Data.ByteString.Lazy as LBS

import Network.Nats.Message.Message (Message (..), ProtocolError (..))
import Network.Nats.Types (Sid)

-- | Existentially quantified Field type, to allow for a polymorph
-- list of Fields. All fields with the contraint of beeing Writeable.
data Field = forall w. Writeable w => Field !w

-- | Helper class used for the writing of "handshake message" fields.
class Writeable w where
    write :: w -> Builder

-- | Instance for 'Bool'.
instance Writeable Bool where
    write False = byteString "false"
    write True  = byteString "true"

-- | Instance for 'Int'.
instance Writeable Int where
    write = intDec

-- | Instance for 'ByteString'.
instance Writeable ByteString where
    write value = charUtf8 '\"' <> byteString value <> charUtf8 '\"'

-- | Translate a 'Message' value to a 'LBS.ByteString'.
writeMessage :: Message -> LBS.ByteString
writeMessage = toLazyByteString . writeMessage'

-- | Translate a Message value to a Builder.
writeMessage' :: Message -> Builder

-- The first of the handshake messages; INFO.
writeMessage' INFO {..} =
    let fields = foldl' writeField [] 
                   [ ("\"server_id\"", Field <$> serverId)
                   , ("\"version\"", Field <$> serverVersion)
                   , ("\"go\"", Field <$> goVersion)
                   , ("\"host\"", Field <$> serverHost)
                   , ("\"port\"", Field <$> serverPort)
                   , ("\"auth_required\"", Field <$> serverAuthRequired)
                   , ("\"ssl_required\"", Field <$> serverSslRequired)
                   , ("\"tls_required\"", Field <$> serverTlsRequired)
                   , ("\"tls_verify\"", Field <$> serverTlsVerify)
                   , ("\"max_payload\"", Field <$> maxPayload)
                   ]
        fields' = intersperse (charUtf8 ',') $ reverse fields
    in mconcat $ byteString "INFO {":(fields' ++ [charUtf8 '}'])

-- The second of the handshake messages; CONNECT.
writeMessage' CONNECT {..} =
    let fields = foldl' writeField []
                   [ ("\"verbose\"", Field <$> clientVerbose)
                   , ("\"pedantic\"", Field <$> clientPedantic)
                   , ("\"ssl_required\"", Field <$> clientSslRequired)
                   , ("\"auth_token\"", Field <$> clientAuthToken)
                   , ("\"user\"", Field <$> clientUser)
                   , ("\"pass\"", Field <$> clientPass)
                   , ("\"name\"", Field <$> clientName)
                   , ("\"lang\"", Field <$> clientLang)
                   , ("\"version\"", Field <$> clientVersion)
                   ]
        fields' = intersperse (charUtf8 ',') $ reverse fields
    in mconcat $ byteString "CONNECT {":(fields' ++ [byteString "}\r\n"])

-- MSG message without a reply subject.
writeMessage' (MSG subject sid Nothing payload) =
    byteString "MSG " <> byteString subject <> charUtf8 ' '
                      <> writeSid sid <> charUtf8 ' '
                      <> int64Dec (LBS.length payload) <> byteString "\r\n"
                      <> lazyByteString payload <> byteString "\r\n"

-- MSG message with a reply subject.
writeMessage' (MSG subject sid (Just reply) payload) =
    byteString "MSG " <> byteString subject <> charUtf8 ' '
                      <> writeSid sid <> charUtf8 ' '
                      <> byteString reply <> charUtf8 ' '
                      <> int64Dec (LBS.length payload) <> byteString "\r\n"
                      <> lazyByteString payload <> byteString "\r\n"

-- PUB message without a reply subject.
writeMessage' (PUB subject Nothing payload) =
    byteString "PUB " <> byteString subject <> charUtf8 ' '
                      <> int64Dec (LBS.length payload) <> byteString "\r\n"
                      <> lazyByteString payload <> byteString "\r\n"

-- PUB message with a reply subject.
writeMessage' (PUB subject (Just reply) payload) =
    byteString "PUB " <> byteString subject <> charUtf8 ' '
                      <> byteString reply <> charUtf8 ' '
                      <> int64Dec (LBS.length payload) <> byteString "\r\n"
                      <> lazyByteString payload <> byteString "\r\n"

-- SUB message without a queue group.
writeMessage' (SUB subject Nothing sid) =
    byteString "SUB " <> byteString subject <> charUtf8 ' ' 
                      <> writeSid sid <> byteString "\r\n"

-- SUB message with a queue group.
writeMessage' (SUB subject (Just queue) sid) =
    byteString "SUB " <> byteString subject <> charUtf8 ' '
                      <> byteString queue <> charUtf8 ' '
                      <> writeSid sid <> byteString "\r\n"

-- UNSUB message without auto-unsubscribe limit.
writeMessage' (UNSUB sid Nothing) =
    byteString "UNSUB " <> writeSid sid <> byteString "\r\n"

-- UNSUB message with auto-unsubscribe limit.
writeMessage' (UNSUB sid (Just maxMsgs)) =
    byteString "UNSUB " <> writeSid sid <> charUtf8 ' '
                        <> intDec maxMsgs <> byteString "\r\n"

-- PING message.
writeMessage' PING = byteString "PING" <> byteString "\r\n"

-- PONG message.
writeMessage' PONG = byteString "PONG" <> byteString "\r\n"

-- Server acknowledge of a well-formed message.
writeMessage' OK = byteString "+OK\r\n"

-- | Server indication of a protocol, authorization, or other
-- runtime connection error.
writeMessage' (ERR pe) = byteString "-ERR " <> writePE pe <> "\r\n"

-- | The translate a Field to a Builder and prepend it to the list of
-- Builders.
writeField :: [Builder] -> (ByteString, Maybe Field) -> [Builder]
writeField xs (name, Just (Field value)) = 
    let x = byteString name <> charUtf8 ':' <> write value
    in x:xs

-- There's a Nothing Field. Just return the unmodified Builder list.
writeField xs (_, Nothing) = xs

-- | Translate a ProtocolError to a Builder.
writePE :: ProtocolError -> Builder
writePE UnknownProtocolOperation = byteString "\'Unknown Protocol Operation\'"
writePE AuthorizationViolation   = byteString "\'Authorization Violation\'"
writePE AuthorizationTimeout     = byteString "\'Authorization Timeout\'"
writePE ParserError              = byteString "\'Parser Error\'"
writePE StaleConnection          = byteString "\'Stale Connection\'"
writePE SlowConsumer             = byteString "\'Slow Consumer\'"
writePE MaximumPayloadExceeded   = byteString "\'Maximum Payload Exceeded\'"
writePE InvalidSubject           = byteString "\'Invalid Subject\'"

-- | Translate a Sid to a Builder.
writeSid :: Sid -> Builder
writeSid = int64Dec
