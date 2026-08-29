{-# LANGUAGE DataKinds #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE UndecidableInstances #-}
{-# LANGUAGE StandaloneKindSignatures #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE NoStarIsType #-}

module Dsss.Circuit.TypeNat where

import Data.Kind (Constraint, Type)
import Data.Proxy (Proxy(..))
import GHC.TypeLits
  ( Nat, KnownNat, natVal, TypeError, ErrorMessage(..)
  , type (+), type (-), type (*), type (<=?), CmpNat
  )

type Width = Nat
type Depth = Nat
type Arity = Nat
type PortIx = Nat

type One  = 1
type Two  = 2
type Byte = 8
type Word = 32
type Lane = 64

type family Assert (p :: Bool) (msg :: ErrorMessage) :: Constraint where
  Assert 'True  _   = ()
  Assert 'False msg = TypeError msg

type family NonZero (n :: Nat) :: Constraint where
  NonZero 0 = TypeError ('Text "Circuit width must be non-zero")
  NonZero _ = ()

type family Fits (i :: Nat) (n :: Nat) :: Constraint where
  Fits i n =
    Assert (i <=? (n - 1))
      ( 'Text "Port index " ':<>: 'ShowType i
      ':<>: 'Text " is outside width " ':<>: 'ShowType n
      )

type family SameWidth (a :: Nat) (b :: Nat) :: Constraint where
  SameWidth n n = ()
  SameWidth a b =
    TypeError
      ( 'Text "Wire-width mismatch: "
      ':<>: 'ShowType a
      ':<>: 'Text " versus "
      ':<>: 'ShowType b
      )

widthVal :: forall n. KnownNat n => Int
widthVal = fromInteger (natVal (Proxy @n))
