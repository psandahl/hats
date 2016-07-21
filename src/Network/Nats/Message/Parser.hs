{-# LANGUAGE OverloadedStrings #-}
-- |
-- Module:      Network.Nats.Message.Parser
-- Copyright:   (c) 2016 Patrik Sandahl
-- License:     MIT
-- Maintainer:  Patrik Sandahl <patrik.sandahl@gmail.com>
-- Stability:   experimental
-- Portability: portable
--
-- NATS protocol 'Message' parser. To be used with the
-- "Data.Attoparsec.ByteString" library.
module Network.Nats.Message.Parser
    ( parseMessage
    ) where

import Control.Applicative ((<|>))
import Control.Monad (void)
import Data.Attoparsec.ByteString.Char8
import Data.ByteString.Char8 (ByteString)

import qualified Data.Attoparsec.ByteString.Char8 as AP
import qualified Data.ByteString.Char8 as BS
import qualified Data.ByteString.Lazy.Char8 as LBS

import Network.Nats.Message.Message ( Message (..)
                                    , ProtocolError (..)
                                    )
import Network.Nats.Types (Sid)

data HandshakeMessageValue =
    Bool   !Bool
  | String !ByteString
  | Int    !Int
    deriving Show

type HandshakeMessageField = (ByteString, HandshakeMessageValue)

-- | Parse a NATS message.
parseMessage :: Parser Message
parseMessage = skipSpace *> parseMessage'
    where
      parseMessage' = msgMessage
                  <|> infoMessage 
                  <|> connectMessage
                  <|> pubMessage
                  <|> subMessage
                  <|> unsubMessage
                  <|> pingMessage
                  <|> pongMessage
                  <|> okMessage 
                  <|> errMessage

-- | The parsing of the Info message is not performance critical.
infoMessage :: Parser Message
infoMessage = do
    spacedMsgName "INFO"
    void $ char '{'
    fields <- parseInfoMessageFields
    void $ char '}'
    mkInfoMessage fields

parseInfoMessageFields :: Parser [HandshakeMessageField]
parseInfoMessageFields = infoMessageField `sepBy` char ','
    where
      infoMessageField = parseServerId
                     <|> parseVersion
                     <|> parseGoVersion
                     <|> parseServerHost
                     <|> parseServerPort
                     <|> parseServerAuthRequired
                     <|> parseSslRequired
                     <|> parseTlsRequired
                     <|> parseTlsVerify
                     <|> parseMaxPayload

-- | Nor is the parsing the Connect message performace critical.
connectMessage :: Parser Message
connectMessage = do
    spacedMsgName "CONNECT"
    void $ char '{'
    fields <- parseConnectMessageFields
    void $ char '}'
    newLine
    mkConnectMessage fields

parseConnectMessageFields :: Parser [HandshakeMessageField]
parseConnectMessageFields = connectMessageField `sepBy` char ','
    where
      connectMessageField = parseClientVerbose
                        <|> parseClientPedantic
                        <|> parseSslRequired
                        <|> parseClientAuthToken
                        <|> parseClientUser
                        <|> parseClientPass
                        <|> parseClientName
                        <|> parseClientLang
                        <|> parseVersion

-- | Parse a MSG message ...
msgMessage :: Parser Message
msgMessage = msgMessageWithReply <|> msgMessageWithoutReply

-- | ... with a reply-to field.
msgMessageWithReply :: Parser Message
msgMessageWithReply = do
    spacedMsgName "MSG"
    MSG <$> takeTill isSpace <* singleSpace
        <*> parseSid <* singleSpace
        <*> (Just <$> takeTill isSpace <* singleSpace)
        <*> readPayload <* newLine

-- | ... and without a reply-to.
msgMessageWithoutReply :: Parser Message
msgMessageWithoutReply = do
    spacedMsgName "MSG"
    MSG <$> takeTill isSpace <* singleSpace
        <*> parseSid <* singleSpace
        <*> pure Nothing
        <*> readPayload <* newLine

-- | Parse a PUB message ...
pubMessage :: Parser Message
pubMessage = pubMessageWithReply <|> pubMessageWithoutReply

-- | ... with a reply-to field.
pubMessageWithReply :: Parser Message
pubMessageWithReply = do
    spacedMsgName "PUB"
    PUB <$> takeTill isSpace <* singleSpace
        <*> (Just <$> takeTill isSpace <* singleSpace)
        <*> readPayload <* newLine

-- | ... and without a reply-to.
pubMessageWithoutReply :: Parser Message
pubMessageWithoutReply = do
    spacedMsgName "PUB"
    PUB <$> takeTill isSpace <* singleSpace
        <*> pure Nothing
        <*> readPayload <* newLine

-- | Helper parser to read the length/payload pair from a PUB/MSG
-- message.
readPayload :: Parser LBS.ByteString
readPayload = do
    len <- decimal <* newLine
    LBS.fromStrict <$> AP.take len
{-# INLINE readPayload #-}

-- | Parse a SUB message ...
subMessage :: Parser Message
subMessage = subMessageWithQueue <|> subMessageWithoutQueue

-- | ... with a queue group.
subMessageWithQueue :: Parser Message
subMessageWithQueue = do
    spacedMsgName "SUB"
    SUB <$> takeTill isSpace <* singleSpace
        <*> (Just <$> takeTill isSpace <* singleSpace)
        <*> parseSid <* newLine
    
-- | ... and without a queue group.
subMessageWithoutQueue :: Parser Message
subMessageWithoutQueue = do
    spacedMsgName "SUB"
    SUB <$> takeTill isSpace <* singleSpace
        <*> pure Nothing
        <*> parseSid <* newLine

-- | Parse an UNSUB message ...
unsubMessage :: Parser Message
unsubMessage = unsubMessageWithLimit <|> unsubMessageWithoutLimit

-- | ... with an unsubscribe limit.
unsubMessageWithLimit :: Parser Message
unsubMessageWithLimit = do
    spacedMsgName "UNSUB"
    UNSUB <$> parseSid <* singleSpace
          <*> (Just <$> decimal) <* newLine

-- | ... and without an unsubscribe limit.
unsubMessageWithoutLimit :: Parser Message
unsubMessageWithoutLimit = do
    spacedMsgName "UNSUB"
    UNSUB <$> parseSid <* newLine
          <*> pure Nothing

pingMessage :: Parser Message
pingMessage = (msgName "PING" >> newLine) *> pure PING

pongMessage :: Parser Message
pongMessage = (msgName "PONG" >> newLine) *> pure PONG

okMessage :: Parser Message
okMessage = (msgName "+OK" >> newLine) *> pure OK

errMessage :: Parser Message
errMessage = do
    spacedMsgName "-ERR"
    ERR <$> protocolError <* newLine

parseServerId :: Parser HandshakeMessageField
parseServerId = pair "\"server_id\"" quotedString "server_id" String

parseVersion :: Parser HandshakeMessageField
parseVersion = pair "\"version\"" quotedString "version" String

parseGoVersion :: Parser HandshakeMessageField
parseGoVersion = pair "\"go\"" quotedString "go" String

parseServerHost :: Parser HandshakeMessageField
parseServerHost = pair "\"host\"" quotedString "host" String

parseServerPort :: Parser HandshakeMessageField
parseServerPort = pair "\"port\"" decimal "port" Int

parseServerAuthRequired :: Parser HandshakeMessageField
parseServerAuthRequired = 
    pair "\"auth_required\"" boolean "auth_required" Bool

parseSslRequired :: Parser HandshakeMessageField
parseSslRequired = pair "\"ssl_required\"" boolean "ssl_required" Bool

parseTlsRequired :: Parser HandshakeMessageField
parseTlsRequired = pair "\"tls_required\"" boolean "tls_required" Bool

parseTlsVerify :: Parser HandshakeMessageField
parseTlsVerify = pair "\"tls_verify\"" boolean "tls_verify" Bool

parseMaxPayload :: Parser HandshakeMessageField
parseMaxPayload = pair "\"max_payload\"" decimal "max_payload" Int

parseClientVerbose :: Parser HandshakeMessageField
parseClientVerbose = pair "\"verbose\"" boolean "verbose" Bool

parseClientPedantic :: Parser HandshakeMessageField
parseClientPedantic = pair "\"pedantic\"" boolean "pedantic" Bool

parseClientAuthToken :: Parser HandshakeMessageField
parseClientAuthToken =
    pair "\"auth_token\"" quotedString "auth_token" String

parseClientUser :: Parser HandshakeMessageField
parseClientUser = pair "\"user\"" quotedString "user" String

parseClientPass :: Parser HandshakeMessageField
parseClientPass = pair "\"pass\"" quotedString "pass" String

parseClientName :: Parser HandshakeMessageField
parseClientName = pair "\"name\"" quotedString "name" String

parseClientLang :: Parser HandshakeMessageField
parseClientLang = pair "\"lang\"" quotedString "lang" String

pair :: ByteString -> Parser a -> ByteString 
               -> (a -> HandshakeMessageValue) 
               -> Parser HandshakeMessageField
pair fieldName parser keyName ctor = do
    void $ string fieldName
    void $ char ':'
    value <- parser
    return (keyName, ctor value)

quotedString :: Parser ByteString
quotedString = BS.pack <$> (char '\"' *> manyTill anyChar (char '\"'))

boolean :: Parser Bool
boolean = string "false" *> return False <|> string "true" *> return True

protocolError :: Parser ProtocolError
protocolError =
    stringCI "\'Unknown Protocol Operation\'" 
        *> return UnknownProtocolOperation <|>

    stringCI "\'Authorization Violation\'"
        *> return AuthorizationViolation   <|>

    stringCI "\'Authorization Timeout\'"
        *> return AuthorizationTimeout     <|>

    stringCI "\'Parser Error\'"
        *> return ParserError              <|>

    stringCI "\'Stale Connection\'"
        *> return StaleConnection          <|>

    stringCI "\'Slow Consumer\'"
        *> return SlowConsumer             <|>

    stringCI "\'Maximum Payload Exceeded\'"
        *> return MaximumPayloadExceeded   <|>

    stringCI "\'Invalid Subject\'"
        *> return InvalidSubject

parseSid :: Parser Sid
parseSid = decimal

mkInfoMessage :: [HandshakeMessageField] -> Parser Message
mkInfoMessage fields =
    INFO <$> asByteString (lookup "server_id" fields)
         <*> asByteString (lookup "version" fields)
         <*> asByteString (lookup "go" fields)
         <*> asByteString (lookup "host" fields)
         <*> asInt (lookup "port" fields)
         <*> asBool (lookup "auth_required" fields)
         <*> asBool (lookup "ssl_required" fields)
         <*> asBool (lookup "tls_required" fields)
         <*> asBool (lookup "tls_verify" fields)
         <*> asInt (lookup "max_payload" fields)

mkConnectMessage :: [HandshakeMessageField] -> Parser Message
mkConnectMessage fields =
    CONNECT <$> asBool (lookup "verbose" fields)
            <*> asBool (lookup "pedantic" fields)
            <*> asBool (lookup "ssl_required" fields)
            <*> asByteString (lookup "auth_token" fields)
            <*> asByteString (lookup "user" fields)
            <*> asByteString (lookup "pass" fields)
            <*> asByteString (lookup "name" fields)
            <*> asByteString (lookup "lang" fields)
            <*> asByteString (lookup "version" fields)

asByteString :: Maybe HandshakeMessageValue -> Parser (Maybe ByteString)
asByteString Nothing               = return Nothing
asByteString (Just (String value)) = return (Just value)
asByteString _                     = fail "Expected a ByteString"

asBool :: Maybe HandshakeMessageValue -> Parser (Maybe Bool)
asBool Nothing             = return Nothing
asBool (Just (Bool value)) = return (Just value)
asBool _                   = fail "Expected a boolean"

asInt :: Maybe HandshakeMessageValue -> Parser (Maybe Int)
asInt Nothing            = return Nothing
asInt (Just (Int value)) = return (Just value)
asInt _                  = fail "Expected an Int"

spacedMsgName :: ByteString -> Parser ()
spacedMsgName name = do
    msgName name
    singleSpace
{-# INLINE spacedMsgName #-}

singleSpace :: Parser ()
singleSpace = void space
{-# INLINE singleSpace #-}

newLine :: Parser ()
newLine = void $ string "\r\n"
{-# INLINE newLine #-}

msgName :: ByteString -> Parser ()
msgName = void . stringCI
{-# INLINE msgName #-}
