module Main where

import Control.Distributed.Process
import Control.Distributed.Process.Node ( initRemoteTable
                                        , runProcess
                                        )
import Control.Distributed.Process.Backend.SimpleLocalnet ( Backend
                                                          , initializeBackend
                                                          , newLocalNode)

import Control.Concurrent (threadDelay)
import Control.Monad (forever, forM_, void)

import System.Environment (getArgs)

import BullyNode

main :: IO ()
main = do
    [host, port] <- getArgs

    backend <- initializeBackend host port initRemoteTable
    
    launchBullyNode backend