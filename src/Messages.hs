{-# LANGUAGE DeriveGeneric #-}

module Messages where

import Control.Distributed.Process (ProcessId)
import GHC.Generics (Generic)
import Data.Binary (Binary)
import Data.Typeable (Typeable)

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