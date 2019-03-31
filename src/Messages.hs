{-# LANGUAGE DeriveGeneric #-}

module Messages where

import Control.Distributed.Process (ProcessId, NodeId)
import GHC.Generics (Generic)
import Data.Binary (Binary)
import Data.Binary.Orphans
import Data.Typeable (Typeable)
import Data.Time.Clock (UTCTime, NominalDiffTime)

data MessageType = Election | Answer | Coordinator
    deriving (Typeable, Generic, Show, Eq)

instance Binary MessageType

data ElectionMessage = ElectionMessage { 
    electionFrom :: NodeId 
    -- electionTerm :: Int
} deriving (Typeable, Generic, Show)

instance Binary ElectionMessage

data AnswerMessage = AnswerMessage {
    answerFrom :: NodeId 
    -- answerTerm :: Int
} deriving (Typeable, Generic, Show)

instance Binary AnswerMessage

data CoordinatorMessage = CoordinatorMessage { 
    coordinatorFrom :: NodeId 
    -- coordinatorTerm :: Int
} deriving (Typeable, Generic, Show)

instance Binary CoordinatorMessage

data NewNodeMessage = NewNodeMessage {

} deriving (Typeable, Generic, Show)

instance Binary NewNodeMessage

data LogStateMessage = LogStateMessage {

} deriving (Typeable, Generic, Show)

instance Binary LogStateMessage

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