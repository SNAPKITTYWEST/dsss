{-# LANGUAGE DataKinds #-}
{-# LANGUAGE GADTs #-}

module Dsss.Circuit.Builder where

import Control.Monad.State.Strict
import Dsss.Circuit.Core
import Dsss.Circuit.Gate

data Node = Node
  { nodeId     :: !Int
  , nodeOpcode :: !String
  , nodeInputs :: ![Int]
  , nodeWidth  :: !Int
  }

data CircuitState = CircuitState
  { nextNode :: !Int
  , nodes    :: ![Node]
  }

newtype Build (g :: CircuitId) a =
  Build { unBuild :: State CircuitState a }
  deriving newtype (Functor, Applicative, Monad)

emit :: Gate g w -> Build g (Wire g w)
emit gate = Build $ do
  st <- get
  let n = nextNode st
  put st
    { nextNode = n + 1
    , nodes    = Node n (tag gate) (inputs gate) (gateWidth gate) : nodes st
    }
  pure (Wire n 0)
  where
    tag     _ = "gate"
    inputs  _ = []
    gateWidth _ = 0
