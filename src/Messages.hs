{-# LANGUAGE DeriveGeneric #-}

module Messages where

import Control.Distributed.Process (ProcessId)
import GHC.Generics (Generic)
import Data.Binary (Binary)
import Data.Binary.Orphans
import Data.Typeable (Typeable)
import Data.Time.Clock (UTCTime, NominalDiffTime)

data MessageType = Election | Answer | Coordinator
    deriving (Typeable, Generic, Show, Eq)

instance Binary MessageType

data ElectionMessage = ElectionMessage { 
    electionFrom :: ProcessId 
    -- electionTerm :: Int
} deriving (Typeable, Generic, Show)

instance Binary ElectionMessage

data AnswerMessage = AnswerMessage {
    answerFrom :: ProcessId 
    -- answerTerm :: Int
} deriving (Typeable, Generic, Show)

instance Binary AnswerMessage

data CoordinatorMessage = CoordinatorMessage { 
    coordinatorFrom :: ProcessId 
    -- coordinatorTerm :: Int
} deriving (Typeable, Generic, Show)

instance Binary CoordinatorMessage

data MonitorTimeoutMessage = MonitorTimeoutMessage {
    monitorFrom :: ProcessId,
    -- expectingFrom :: ProcessId,
    expectedType :: MessageType,
    timeSent :: UTCTime,
    expectedIn :: NominalDiffTime
} deriving (Typeable, Generic, Show)

instance Binary MonitorTimeoutMessage

data MessageReceivedNotification = MessageReceivedNotification {
    monitoringFrom :: ProcessId,
    -- receivedFrom :: ProcessId,
    receivedType :: MessageType,
    timeReceived :: UTCTime
} deriving (Typeable, Generic, Show)

instance Binary MessageReceivedNotification

data ExpirationNotification = ExpirationNotification {
    -- expiredFrom :: ProcessId,
    expiredType :: MessageType
} deriving (Typeable, Generic, Show)

instance Binary ExpirationNotification