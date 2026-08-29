{-# LANGUAGE DataKinds #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE TypeOperators #-}

module Dsss.Circuit.Core where

import Data.Kind (Type)
import Dsss.Circuit.TypeNat
import Dsss.Circuit.Vec

data CircuitId

data Wire (g :: CircuitId) (w :: Width) = Wire
  { wireNode :: !Int
  , wirePort :: !Int
  }

data Bus (g :: CircuitId) (w :: Width) where
  Bus :: NonZero w => Vec w (Wire g 1) -> Bus g w

data Port (g :: CircuitId) (w :: Width) where
  Port :: KnownNat w => Wire g w -> Port g w

data Signal (g :: CircuitId) (w :: Width) where
  Scalar :: Wire g 1        -> Signal g 1
  Vector :: NonZero w => Wire g w -> Signal g w
