module BullyNode where

import Control.Distributed.Process
import Control.Distributed.Process.Node (LocalNode, runProcess)
import Control.Distributed.Process.Serializable

import Control.Monad (forM_)
import Data.Time.Clock

import TimeoutManager
import Messages

timeoutDuration = 5 :: NominalDiffTime

data NodeState = NodeState {
    selfProcId :: ProcessId,
    timeoutManager :: ProcessId,
    neighbors :: [ProcessId],
    coordinatorId :: ProcessId
} deriving (Show)

checkIfLeader :: NodeState -> Bool
checkIfLeader (NodeState selfProcId _ neighbors _) =
    selfProcId > maxNeighborId
    where
        maxNeighborId = foldr1 (\x y -> if x >= y then x else y) neighbors

broadcast :: Serializable a => a -> [ProcessId] -> Process ()
broadcast message processes =
    forM_ processes (\neighborID -> send neighborID message)

startElection :: ProcessId -> ProcessId -> [ProcessId] -> Process ()
startElection selfProcId timeoutManager neighbors = do
    broadcast (ElectionMessage selfProcId) higherNeighbors
    currentTime <- liftIO $ getCurrentTime
    send timeoutManager $ MonitorTimeoutMessage selfProcId Answer currentTime timeoutDuration
    where
        higherNeighbors = filter ((<) selfProcId) neighbors

electionHandler :: NodeState -> ElectionMessage -> Process NodeState
electionHandler 
    (NodeState selfProcId timeoutManager neighbors cordId) 
    (ElectionMessage fromProcessId) = do
    case selfProcId > fromProcessId of
        True -> do
            -- Action 4
            send fromProcessId $ AnswerMessage selfProcId
            startElection selfProcId timeoutManager neighbors
            return $ NodeState selfProcId timeoutManager neighbors cordId
        False -> do
            return $ NodeState selfProcId timeoutManager neighbors cordId

answerHandler :: NodeState -> AnswerMessage -> Process NodeState
answerHandler 
    (NodeState selfProcId timeoutManager neighbors cordId) 
    (AnswerMessage fromProcessId) = do
    case selfProcId > fromProcessId of
        True -> do
            return $ NodeState selfProcId timeoutManager neighbors cordId
        False -> do
            -- Action 3 - Begin
            currentTime <- liftIO $ getCurrentTime

            let receivedMsg = MessageReceivedNotification selfProcId Answer currentTime
                monitorMsg = MonitorTimeoutMessage selfProcId Coordinator currentTime timeoutDuration
            
            send timeoutManager receivedMsg
            send timeoutManager monitorMsg

            return $ NodeState selfProcId timeoutManager neighbors cordId

coordinatorHandler :: NodeState -> CoordinatorMessage -> Process NodeState
coordinatorHandler 
    (NodeState selfProcId timeoutManager neighbors coordinatorId) 
    (CoordinatorMessage fromProcessId) = do
    -- Action 5
    let coordinatorId' = fromProcessId

    return $ NodeState selfProcId timeoutManager neighbors coordinatorId'

expirationHandler :: NodeState -> ExpirationNotification -> Process NodeState
expirationHandler 
    (NodeState selfProcId timeoutManager neighbors coordinatorId) 
    (ExpirationNotification expiredType) = do
    case expiredType of
        Answer -> do
            -- Action 2
            let coordinatorId' = selfProcId
            broadcast (CoordinatorMessage selfProcId) neighbors
            
            return $ NodeState selfProcId timeoutManager neighbors coordinatorId'
        Coordinator -> do
            -- Action 3 - End
            let state' = NodeState selfProcId timeoutManager neighbors coordinatorId
            state'' <- beginBully state'

            return state''


beginBully :: NodeState -> Process NodeState
beginBully (NodeState selfProcId timeoutManager neighbors coordinatorId) = do
    -- Action 1
    let isLeader = checkIfLeader $ NodeState selfProcId timeoutManager neighbors coordinatorId
    case isLeader of
        True -> do
            let coordinatorId' = selfProcId
            broadcast (CoordinatorMessage selfProcId) neighbors

            return $ NodeState selfProcId timeoutManager neighbors coordinatorId'
        False -> do
            startElection selfProcId timeoutManager neighbors

            return $ NodeState selfProcId timeoutManager neighbors coordinatorId

coordinatorFailureHandler :: NodeState -> ProcessMonitorNotification -> Process NodeState
coordinatorFailureHandler
    (NodeState selfProcId timeoutManager neighbors coordinatorId)
    (ProcessMonitorNotification _ failedId _ ) = do
        case failedId == coordinatorId of
            True -> do
                let state' = NodeState selfProcId timeoutManager neighbors coordinatorId
                
                state'' <- beginBully state'

                return state''
            False -> do
                return $ NodeState selfProcId timeoutManager neighbors coordinatorId

monitorNeighbors :: [ProcessId] -> Process ()
monitorNeighbors neighbors =
    forM_ neighbors (\neighborID -> monitor neighborID)

-- To-Do:
-- figure how how to make an individual bully node aware of other nodes based on 
-- processIds
runBullyNode :: NodeState -> Process ()
runBullyNode state = do
    state' <- receiveWait [
          match $ electionHandler state
        , match $ answerHandler state
        , match $ coordinatorHandler state
        , match $ expirationHandler state
        , match $ coordinatorFailureHandler state
        ]
    runBullyNode state'


-- Need to read neighbors from file and pass it to this function
launchBullyNode :: LocalNode -> IO ()
launchBullyNode n = do
    runProcess n $ do
        timeoutPid <- spawnLocal $ do
            self <- getSelfPid
            selfNodeId <- getSelfNode
            say $ "Starting local timeout manager: " ++ show selfNodeId
    
            runTimeoutManager $ ManagerState self []
        
        self <- getSelfPid
        selfNodeId <- getSelfNode
        say $ "Starting bully node: " ++ show selfNodeId

        runBullyNode $ NodeState self timeoutPid [] self
