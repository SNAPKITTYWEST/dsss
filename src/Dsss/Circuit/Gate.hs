{-# LANGUAGE DataKinds #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE UndecidableInstances #-}

module Dsss.Circuit.Gate where

import GHC.TypeLits (Nat, type (+))
import Dsss.Circuit.TypeNat
import Dsss.Circuit.Core
import Dsss.Circuit.Vec

data Gate (g :: CircuitId) (out :: Width) where
  Const  :: KnownNat w => Vec w Bit -> Gate g w
  Input  :: KnownNat w => String    -> Gate g w
  Not    :: Wire g w -> Gate g w
  And    :: Wire g w -> Wire g w -> Gate g w
  Or     :: Wire g w -> Wire g w -> Gate g w
  Xor    :: Wire g w -> Wire g w -> Gate g w
  Mux    :: Wire g 1 -> Wire g w -> Wire g w -> Gate g w
  Concat :: Wire g a -> Wire g b -> Gate g (a + b)
  Slice  :: (Fits lo w, Fits hi w)
         => Wire g w -> Fin (hi - lo + 1) -> Gate g (hi - lo + 1)
  EqW    :: Wire g w -> Wire g w -> Gate g 1
  Ult    :: Wire g w -> Wire g w -> Gate g 1
  Add    :: Wire g w -> Wire g w -> Gate g w
  Sub    :: Wire g w -> Wire g w -> Gate g w
  Mul    :: Wire g w -> Wire g w -> Gate g w
  Reg    :: Wire g w -> Gate g w

type family SliceWidth (hi :: Nat) (lo :: Nat) :: Nat where
  SliceWidth hi lo = hi - lo + 1

type family ValidSlice (w :: Nat) (hi :: Nat) (lo :: Nat) :: Constraint where
  ValidSlice w hi lo =
    ( Assert (lo <=? hi)
        ( 'Text "Slice lower bound exceeds upper bound: "
        ':<>: 'ShowType lo ':<>: 'Text " > " ':<>: 'ShowType hi
        )
    , Assert (hi <=? (w - 1))
        ( 'Text "Slice upper bound outside source width: "
        ':<>: 'ShowType hi ':<>: 'Text " for width " ':<>: 'ShowType w
        )
    )
