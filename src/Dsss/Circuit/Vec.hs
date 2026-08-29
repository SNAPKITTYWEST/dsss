{-# LANGUAGE EmptyCase #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE TypeOperators #-}

module Dsss.Circuit.Vec where

import Data.Kind (Type)
import Dsss.Circuit.TypeNat

data Fin (n :: Nat) where
  FZ :: Fin (n + 1)
  FS :: Fin n -> Fin (n + 1)

data Vec (n :: Nat) (a :: Type) where
  VNil :: Vec 0 a
  (:#) :: a -> Vec n a -> Vec (n + 1) a

infixr 5 :#

data Bit = O | I
  deriving (Eq, Ord, Show)

finToInt :: Fin n -> Int
finToInt FZ     = 0
finToInt (FS ix) = 1 + finToInt ix

index :: Vec n a -> Fin n -> a
index (x :# _)  FZ     = x
index (_ :# xs) (FS ix) = index xs ix
index VNil      ix      = case ix of {}
