module Main where

import Control.Distributed.Process
import Control.Distributed.Process.Node ( initRemoteTable
                                        , runProcess
                                        , newLocalNode
                                        )
import Network.Transport.TCP (createTransport, defaultTCPParameters)

import Control.Concurrent (threadDelay)

import Control.Monad (forever, forM_)

import BullyNode

main :: IO ()
main = do
    maybeT <- createTransport "127.0.0.1" "10501" defaultTCPParameters
    case maybeT of
        Right t -> do
            n <- newLocalNode t initRemoteTable
            runProcess n $ do
                self <- getSelfPid
                selfNodeID <- getSelfNode
                say $ "Starting bully node: " ++ show selfNodeID

                let neighbors = [] :: [ProcessId]
                runBullyNode $ NodeState self neighbors self
        Left error -> print error