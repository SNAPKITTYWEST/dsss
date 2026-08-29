{-# LANGUAGE DataKinds #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE UndecidableInstances #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}

module Dsss.Circuit.DSL where

import GHC.TypeNats
import GHC.TypeLits (TypeError, ErrorMessage(..))
import Data.Proxy

-- | Core Circuit GADT mapping input width 'i' to output width 'o'
data Circuit (i :: Nat) (o :: Nat) where
  Id    :: Circuit n n
  Split :: Circuit n (n + n)
  Join  :: Circuit (n + n) n
  And   :: Circuit (2 * n) n
  Or    :: Circuit (2 * n) n
  Xor   :: Circuit (2 * n) n
  Not   :: Circuit n n
  Reg   :: KnownNat n => Circuit n n
  (:***:) :: Circuit i1 o1 -> Circuit i2 o2 -> Circuit (i1 + i2) (o1 + o2)
  (:>>>:) :: (CheckWire m1 m2 ~ m) => Circuit i m1 -> Circuit m2 o -> Circuit i o

infixr 5 :>>>:
infixr 6 :***:

-- | Enforce exact wiring with custom diagnostics
type family CheckWire (m1 :: Nat) (m2 :: Nat) :: Nat where
  CheckWire m m   = m
  CheckWire m1 m2 = TypeError
    ( 'Text "Circuit Topology Error: Wiring Invariant Violation"
    ':$$: 'Text "================================================="
    ':$$: 'Text "Upstream output bus width:   " ':<>: 'ShowType m1
    ':$$: 'Text "Downstream input bus width:  " ':<>: 'ShowType m2
    ':$$: 'Text "Cannot safely bridge "
          ':<>: 'ShowType m1 ':<>: 'Text " wires to "
          ':<>: 'ShowType m2 ':<>: 'Text " terminals."
    )

-- | Reflect circuit bounds for runtime allocation
allocateState :: forall n. KnownNat n => Circuit n n -> Int
allocateState Reg = fromIntegral (natVal (Proxy @n))
allocateState Id  = 0
allocateState Not = 0
allocateState _   = 0

-- | Example: 64-bit bounded ALU state pipeline
aluPipeline :: Circuit 128 64
aluPipeline = Xor :>>>: Reg :>>>: Not
