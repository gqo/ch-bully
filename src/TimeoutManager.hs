module TimeoutManager where

import Control.Distributed.Process

import Control.Monad (forM_)

import Data.Time.Clock
import Data.List (partition)

import Messages

data ManagerState = ManagerState {
    selfProcId :: ProcessId,
    expectedMessages :: [MonitorTimeoutMessage]
} deriving (Show)

checkExpired :: UTCTime -> MonitorTimeoutMessage -> Bool
checkExpired currentTime (MonitorTimeoutMessage _ _ timeSent expectedIn) = 
    not (timeSince < expectedIn)
    where
        timeSince = diffUTCTime currentTime timeSent

partionExpiredMessages :: UTCTime -> [MonitorTimeoutMessage] -> ([MonitorTimeoutMessage], [MonitorTimeoutMessage])
partionExpiredMessages currentTime expectedMessages =
    partition (checkExpired currentTime) expectedMessages

notifyExpiration :: MonitorTimeoutMessage -> Process ()
notifyExpiration (MonitorTimeoutMessage callerID expiredType _ _) =
    send callerID message
    where
        message = ExpirationNotification expiredType

notifyExpirations :: [MonitorTimeoutMessage] -> Process ()
notifyExpirations expiredMessages =
    forM_ expiredMessages (\msg -> notifyExpiration msg)

handleExpiredMessages :: ManagerState -> Process ManagerState
handleExpiredMessages (ManagerState selfProcId expectedMessages) = do
    currentTime <- liftIO $ getCurrentTime
    let (expiredMessages, expectedMessages') = partionExpiredMessages currentTime expectedMessages
    
    notifyExpirations expiredMessages

    return $ ManagerState selfProcId expectedMessages'
    

monitorTimeoutHandler :: ManagerState -> MonitorTimeoutMessage -> Process ManagerState
monitorTimeoutHandler (ManagerState selfProcId expectedMessages) msg = do
    let expectedMessages' = msg:expectedMessages

    return $ ManagerState selfProcId expectedMessages'

compareMessages :: MessageReceivedNotification -> MonitorTimeoutMessage -> Bool
compareMessages (MessageReceivedNotification a b _) (MonitorTimeoutMessage x y _ _)
    | a == x && b == y = True
    | otherwise = False

removeMonitor :: MessageReceivedNotification -> [MonitorTimeoutMessage] -> [MonitorTimeoutMessage]
removeMonitor _ [] = []
removeMonitor msg (x:xs) | compareMessages msg x = xs
                         | otherwise = x : removeMonitor msg xs

receiveMessageHandler :: ManagerState -> MessageReceivedNotification -> Process ManagerState
receiveMessageHandler (ManagerState selfProcId expectedMessages) msg = do
    let expectedMessages' = removeMonitor msg expectedMessages

    return $ ManagerState selfProcId expectedMessages'

runTimeoutManager :: ManagerState -> Process ()
runTimeoutManager state = do
    maybeState <- receiveTimeout 0 $ [
          match $ monitorTimeoutHandler state
        , match $ receiveMessageHandler state
        ]
    case maybeState of
        Nothing -> do
            state' <- handleExpiredMessages state
            runTimeoutManager state'
        Just state' -> do
            state'' <- handleExpiredMessages state'
            runTimeoutManager state''