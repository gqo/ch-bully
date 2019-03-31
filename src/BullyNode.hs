module BullyNode where

import Control.Distributed.Process
import Control.Distributed.Process.Node (runProcess)
import Control.Distributed.Process.Backend.SimpleLocalnet ( Backend
                                                          , findPeers
                                                          , newLocalNode)
import Control.Distributed.Process.Serializable

import Control.Concurrent (threadDelay)
import Control.Monad (forM_, void, forever)
import Data.Time.Clock

import TimeoutManager
import Messages

coordinatorTimeout = 15 :: NominalDiffTime
answerTimeout = 3 :: NominalDiffTime
findPeersTimeout = 500000 :: Int

data NodeState = NodeState {
    selfProcId :: ProcessId,
    timeoutManager :: ProcessId,
    neighbors :: [NodeId],
    coordinatorId :: NodeId,
    backend :: Backend
}

instance Show NodeState where
    show (NodeState selfProcId timeoutPid neighbors coordinatorId _)
        = "\nProcessId: " ++ show selfProcId ++
          "\nTimeoutManager: " ++ show timeoutPid ++
          "\nNeighbors: " ++ show neighbors ++
          "\nCoordinatorId: " ++ show coordinatorId ++
          "\n------------------------"

checkIfLeader :: NodeId -> [NodeId] -> Bool
checkIfLeader _ [] = True
checkIfLeader selfNodeId neighbors =
    selfNodeId > maxNeighborId
    where
        maxNeighborId = foldr1 (\x y -> if x >= y then x else y) neighbors

bullySend :: (Serializable a, Show a) => a -> NodeId -> Process ()
bullySend message nodeId = do
    say $ "Sending " ++ show message ++ " to " ++ show nodeId
    state' <- nsendRemote nodeId (show nodeId) message
    return state'
    

broadcast :: (Serializable a, Show a) => a -> [NodeId] -> Process ()
broadcast message processes =
    forM_ processes (\neighborID -> bullySend message neighborID)

startElection :: ProcessId -> ProcessId -> [NodeId] -> Process ()
startElection selfProcId timeoutManager neighbors = do
    broadcast (ElectionMessage selfNodeId) higherNeighbors
    currentTime <- liftIO $ getCurrentTime
    send timeoutManager $ MonitorTimeoutMessage selfProcId Answer currentTime answerTimeout
    where
        selfNodeId = processNodeId selfProcId
        higherNeighbors = filter ((<) selfNodeId) neighbors

electionHandler :: NodeState -> ElectionMessage -> Process NodeState
electionHandler 
    (NodeState selfProcId timeoutManager neighbors cordId backend) 
    (ElectionMessage fromNodeId) = do
        say $ "Received election message from: " ++ show fromNodeId
        let selfNodeId = processNodeId selfProcId
        case selfNodeId > fromNodeId of
            True -> do
                say $ "They have a lower nodeId. Answering and starting election."
                -- Action 4
                nsendRemote fromNodeId (show fromNodeId) $ AnswerMessage selfNodeId
                startElection selfProcId timeoutManager neighbors
                return $ NodeState selfProcId timeoutManager neighbors cordId backend
            False -> do
                say $ "They have a higher nodeID. Disregarding."
                return $ NodeState selfProcId timeoutManager neighbors cordId backend

answerHandler :: NodeState -> AnswerMessage -> Process NodeState
answerHandler 
    (NodeState selfProcId timeoutManager neighbors cordId backend) 
    (AnswerMessage fromNodeId) = do
        say $ "Received answer message from: " ++ show fromNodeId
        let selfNodeId = processNodeId selfProcId
        case selfNodeId > fromNodeId of
            True -> do
                say $ "They have a lower nodeID. Disregarding."
                return $ NodeState selfProcId timeoutManager neighbors cordId backend
            False -> do
                say $ "They have a higher nodeId. Waiting for a coordinator message."
                -- Action 3 - Begin
                currentTime <- liftIO $ getCurrentTime

                let receivedMsg = MessageReceivedNotification selfProcId Answer currentTime
                    monitorMsg = MonitorTimeoutMessage selfProcId Coordinator currentTime coordinatorTimeout
                
                send timeoutManager receivedMsg
                send timeoutManager monitorMsg

                return $ NodeState selfProcId timeoutManager neighbors cordId backend

coordinatorHandler :: NodeState -> CoordinatorMessage -> Process NodeState
coordinatorHandler 
    (NodeState selfProcId timeoutManager neighbors coordinatorId backend) 
    (CoordinatorMessage fromNodeId) = do
        say $ "Received a coordinator message from: " ++ show fromNodeId
        -- Action 5
        currentTime <- liftIO $ getCurrentTime
        let coordinatorId' = fromNodeId
            receivedMsg = MessageReceivedNotification selfProcId Coordinator currentTime

        send timeoutManager receivedMsg

        return $ NodeState selfProcId timeoutManager neighbors coordinatorId' backend

expirationHandler :: NodeState -> ExpirationNotification -> Process NodeState
expirationHandler 
    (NodeState selfProcId timeoutManager neighbors coordinatorId backend) 
    (ExpirationNotification expiredType) = do
        let selfNodeId = processNodeId selfProcId
        case expiredType of
            Answer -> do
                say $ "Did not receive answer. Declaring self coordinator."
                -- Action 2
                let coordinatorId' = selfNodeId
                broadcast (CoordinatorMessage selfNodeId) neighbors
                
                return $ NodeState selfProcId timeoutManager neighbors coordinatorId' backend
            Coordinator -> do
                say $ "Did not receive coordinator message. Starting election."
                -- Action 3 - End
                let state' = NodeState selfProcId timeoutManager neighbors coordinatorId backend
                state'' <- startBullyRound state'

                return state''

monitorNeighbors :: [NodeId] -> Process ()
monitorNeighbors neighbors =
    forM_ neighbors (\neighborID -> monitorNode neighborID)

startBullyRound :: NodeState -> Process NodeState
startBullyRound (NodeState selfProcId timeoutManager neighbors coordinatorId backend) = do
    say $ "Locating current neighbors..."

    peers <- liftIO $ findPeers backend findPeersTimeout

    let selfNodeId = processNodeId selfProcId
        neighbors = filter ((/=) selfNodeId) peers

    say $ "Located current neighbors: " ++ show neighbors

    monitorNeighbors neighbors

    say $ "Starting bully round..."
    -- Action 1
    let isLeader = checkIfLeader selfNodeId neighbors
        coordinatorId' = selfNodeId
    case isLeader of
        True -> do
            say $ "This node is the leader. Broadcasting coordinator message."
            broadcast (CoordinatorMessage selfNodeId) neighbors

            return $ NodeState selfProcId timeoutManager neighbors coordinatorId' backend
        False -> do
            say $ "This node is not the leader. Starting election."
            startElection selfProcId timeoutManager neighbors

            return $ NodeState selfProcId timeoutManager neighbors coordinatorId' backend

launchBully :: NodeState -> Process NodeState
launchBully (NodeState selfProcId timeoutManager _ coordinatorId backend) = do
    say $ "Locating starting neighbors..."
    
    peers <- liftIO $ findPeers backend findPeersTimeout

    let selfNodeId = processNodeId selfProcId
        neighbors = filter ((/=) selfNodeId) peers

    say $ "Located starting neighbors: " ++ show neighbors
    say $ "Sending starting neighbors new node message..."

    broadcast NewNodeMessage neighbors

    state' <- startBullyRound $ NodeState selfProcId timeoutManager neighbors coordinatorId backend

    return state'

coordinatorFailureHandler :: NodeState -> NodeMonitorNotification -> Process NodeState
coordinatorFailureHandler
    (NodeState selfProcId timeoutManager neighbors coordinatorId backend)
    (NodeMonitorNotification _ failedId _ ) = do
        case failedId == coordinatorId of
            True -> do
                say $ "Detected failure on coordinator node: " ++ show failedId
                let state' = NodeState selfProcId timeoutManager neighbors coordinatorId backend
                
                state'' <- startBullyRound state'

                return state''
            False -> do
                say $ "Detected failure on non-coordinator node: " ++ show failedId
                return $ NodeState selfProcId timeoutManager neighbors coordinatorId backend

newNodeHandler :: NodeState -> NewNodeMessage -> Process NodeState
newNodeHandler (NodeState selfProcId timeoutManager _ coordinatorId backend) _ = do
    say $ "Node joined the network. Updating neighbors..."

    peers <- liftIO $ findPeers backend findPeersTimeout

    let selfNodeId = processNodeId selfProcId
        neighbors' = filter ((/=) selfNodeId) peers

    say $ "Located new neighbors: " ++ show neighbors'

    monitorNeighbors neighbors'

    return $ NodeState selfProcId timeoutManager neighbors' coordinatorId backend

logStateHandler :: NodeState -> LogStateMessage -> Process NodeState
logStateHandler state _ = do
    say $ "\nCurrent state: " ++ show state
    return state

runBullyNode :: NodeState -> Process ()
runBullyNode state = do
    state' <- receiveWait [
          match $ electionHandler state
        , match $ answerHandler state
        , match $ coordinatorHandler state
        , match $ expirationHandler state
        , match $ coordinatorFailureHandler state
        , match $ newNodeHandler state
        , match $ logStateHandler state]
    runBullyNode state'


-- Need to read neighbors from file and pass it to this function
launchBullyNode :: Backend -> IO ()
launchBullyNode backend = do
    node <- newLocalNode backend

    runProcess node $ do
        timeoutPid <- spawnLocal $ do
            self <- getSelfPid
            selfNodeId <- getSelfNode
            say $ "Starting local timeout manager: " ++ show selfNodeId
    
            runTimeoutManager $ ManagerState self []
        
        self <- getSelfPid
        selfNodeId <- getSelfNode
        say $ "Starting bully node: " ++ show selfNodeId

        registerRemoteAsync selfNodeId (show selfNodeId) self
        
        void $ spawnLocal $ forever $ do
            liftIO $ threadDelay 10000000
            send self LogStateMessage

        initialState <- launchBully $ NodeState self timeoutPid [] selfNodeId backend
        
        runBullyNode initialState
