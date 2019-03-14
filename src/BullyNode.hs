module BullyNode where

import Control.Distributed.Process

import Control.Distributed.Process.Serializable

import Control.Monad (forM_)

import Messages

data NodeState = NodeState {
    selfProcId :: ProcessId,
    neighbors :: [ProcessId],
    coordinatorId :: ProcessId
} deriving (Show)

checkIfLeader :: NodeState -> Bool
checkIfLeader (NodeState selfProcId neighbors _) =
    selfProcId > maxNeighborId
    where
        maxNeighborId = foldr1 (\x y -> if x >= y then x else y) neighbors

broadcast :: Serializable a => a -> [ProcessId] -> Process ()
broadcast message processes =
    forM_ processes (\neighborID -> send neighborID message)

startElection :: ProcessId -> [ProcessId] -> Process ()
startElection selfProcId neighbors =
    broadcast (ElectionMessage selfProcId) higherNeighbors
    where
        higherNeighbors = filter ((<) selfProcId) neighbors

electionHandler :: NodeState -> ElectionMessage -> Process NodeState
electionHandler (NodeState selfProcId neighbors cordId) (ElectionMessage fromProcessId) = do
    case selfProcId > fromProcessId of
        True -> do
            send fromProcessId $ AnswerMessage selfProcId
            startElection selfProcId neighbors
            return $ NodeState selfProcId neighbors cordId
        False -> do
            return $ NodeState selfProcId neighbors cordId

answerHandler :: NodeState -> AnswerMessage -> Process NodeState
answerHandler (NodeState selfProcId neighbors cordId) (AnswerMessage fromProcessId) = do
    case selfProcId > fromProcessId of
        True -> do
            -- timeout here somehow
            -- another receiveWait?
            return $ NodeState selfProcId neighbors cordId
        False -> do
            return $ NodeState selfProcId neighbors cordId

coordinatorHandler :: NodeState -> CoordinatorMessage -> Process NodeState
coordinatorHandler (NodeState selfProcId neighbors _) (CoordinatorMessage fromProcessId) = do
    let coordinatorId' = fromProcessId

    return $ NodeState selfProcId neighbors coordinatorId'


-- To-Do:
-- match node failures
-- match node joins - abstracted from actual nodes?
-- spawnLocal option for timeouts
-- receive option with global state of expected messages option for timeouts
-- figure out timeout when received higherID election
-- figure out timeout when received higherID answer
runBullyNode :: NodeState -> Process ()
runBullyNode state = do
    state' <- receiveWait [
          match $ electionHandler state
        , match $ answerHandler state
        , match $ coordinatorHandler state
        ]
    runBullyNode state'