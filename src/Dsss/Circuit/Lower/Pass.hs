{-# LANGUAGE DataKinds #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE RecordWildCards #-}

-- | DSSS Lowering Pass
-- Converts a well-typed width-indexed Circuit GADT into a canonical
-- word-level constraint graph plus proof obligations.
-- Width indices are preserved from source to target — never erased.
module Dsss.Circuit.Lower.Pass where

import GHC.TypeNats (KnownNat, natVal, Nat)
import Data.Proxy (Proxy(..))
import Data.HashMap.Strict (HashMap)
import qualified Data.HashMap.Strict as HM
import Data.Natural (Natural)
import Control.Monad.State.Strict
import Control.Monad.Except

import Dsss.Circuit.Core
import Dsss.Circuit.Gate
import Dsss.Circuit.TypeNat

-- ---------------------------------------------------------------------------
-- Width witness
-- ---------------------------------------------------------------------------

data WidthWitness (w :: Nat) where
  WidthWitness :: KnownNat w => Proxy w -> WidthWitness w

-- ---------------------------------------------------------------------------
-- Lowered word
-- ---------------------------------------------------------------------------

data LoweredWord (g :: CircuitId) (w :: Width) where
  LWord
    :: { lwId     :: !WordId
       , lwWidth  :: !(WidthWitness w)
       , lwOrigin :: !NodeId
       , lwClass  :: !WordClass
       }
    -> LoweredWord g w

data WordClass = Comb | StateRead | StateWrite
  deriving (Show, Eq, Ord)

-- ---------------------------------------------------------------------------
-- Word operators (SSA-like graph)
-- ---------------------------------------------------------------------------

data WordOp
  = WConst  !BitPattern
  | WInput  !Name
  | WNot    !WordId
  | WAnd    !WordId !WordId
  | WXor    !WordId !WordId
  | WMux    !WordId !WordId !WordId
  | WConcat !WordId !WordId
  | WExtract !Int !Int !WordId
  | WAdd    !WordId !WordId
  | WSub    !WordId !WordId
  | WEq     !WordId !WordId
  | WUlt    !WordId !WordId
  | WState  !RegId
  | WNext   !RegId !WordId
  deriving (Eq, Ord, Show)

data Phase = PComb | PStateRead | PStateWrite
  deriving (Eq, Ord, Show)

data WordNode = WordNode
  { wordId     :: !WordId
  , wordWidth  :: !Natural
  , wordOp     :: !WordOp
  , wordOrigin :: !NodeId
  , wordPhase  :: !Phase
  , wordPolicy :: !PolicyRef
  }

-- ---------------------------------------------------------------------------
-- Proof obligations
-- ---------------------------------------------------------------------------

data Obligation
  = WidthPreserved  !NodeId !Natural
  | OpWellSorted    !WordId !WordOp
  | ExtractInRange  !WordId !Int !Int !Natural
  | CombinationalAcyclic ![WordId]
  | RegisterDefined !RegId !WordId
  | LoweringEquivalent !WordId !LoweringWitness
  | PropertyWellFormed !PropertyId !WordId

-- ---------------------------------------------------------------------------
-- Certificate
-- ---------------------------------------------------------------------------

data LowerCert = LowerCert
  { certNode        :: !WordId
  , certSource      :: !NodeId
  , certSourceType  :: !TypeFingerprint
  , certRule        :: !LowerRule
  , certInputs      :: ![WordId]
  , certWidth       :: !Natural
  , certPolicyHash  :: !Hash
  , certObligations :: ![ObligationId]
  }

-- ---------------------------------------------------------------------------
-- Hash-cons memo table
-- ---------------------------------------------------------------------------

data CircuitKey = CircuitKey
  { keyCtor     :: !CtorTag
  , keyWidth    :: !Natural
  , keyChildren :: ![WordId]
  , keyPayload  :: !Payload
  } deriving (Eq)

data SomeLoweredWord where
  SomeLoweredWord :: LoweredWord g w -> SomeLoweredWord

type Memo = HashMap CircuitKey SomeLoweredWord

-- ---------------------------------------------------------------------------
-- Lowering monad
-- ---------------------------------------------------------------------------

data LowerState = LowerState
  { lsMemo    :: !Memo
  , lsNodes   :: ![WordNode]
  , lsCerts   :: ![LowerCert]
  , lsObligs  :: ![Obligation]
  , lsNextId  :: !Int
  }

type LowerM a = ExceptT LowerError (State LowerState) a

data LowerError
  = ZeroWidthCircuit
  | WidthMismatch Natural Natural NodeId
  | CombinationalCycle [WordId]
  | UndefinedRegister RegId
  deriving (Show)

-- ---------------------------------------------------------------------------
-- Width reification
-- ---------------------------------------------------------------------------

reifyWidth :: forall w. KnownNat w => WidthWitness w -> LowerM Natural
reifyWidth WidthWitness{} = do
  let n = natVal (Proxy @w)
  if n == 0
    then throwError ZeroWidthCircuit
    else pure n

-- ---------------------------------------------------------------------------
-- Core lowering function
-- ---------------------------------------------------------------------------

lower :: Circuit g w -> LowerM (LoweredWord g w)
lower = \case
  CConst bits  -> lowerConst bits
  CInput name  -> lowerInput name
  CNot x       -> unary WNot x
  CAnd x y     -> binary WAnd x y
  CXor x y     -> binary WXor x y
  CAdd x y     -> binary WAdd x y
  CSub x y     -> binary WSub x y
  CMux s t f   -> do { ls <- lower s; lt <- lower t; lf <- lower f; emitMux ls lt lf }
  CConcat x y  -> do { lx <- lower x; ly <- lower y; emitConcat lx ly }
  CSlice x hi lo -> do { lx <- lower x; emitExtract hi lo lx }
  CEq x y      -> compareLower WEq x y
  CUlt x y     -> compareLower WUlt x y
  CReg r x     -> lowerReg r x

-- ---------------------------------------------------------------------------
-- Helpers (stubs — implementations attach obligations and certificates)
-- ---------------------------------------------------------------------------

lowerConst  :: Vec w Bit -> LowerM (LoweredWord g w)
lowerConst _ = error "stub: lowerConst"

lowerInput  :: Name -> LowerM (LoweredWord g w)
lowerInput _ = error "stub: lowerInput"

unary :: (WordId -> WordOp) -> Circuit g w -> LowerM (LoweredWord g w)
unary _ _ = error "stub: unary"

binary :: (WordId -> WordId -> WordOp)
       -> Circuit g w -> Circuit g w -> LowerM (LoweredWord g w)
binary _ _ _ = error "stub: binary"

compareLower :: (WordId -> WordId -> WordOp)
             -> Circuit g w -> Circuit g w -> LowerM (LoweredWord g 1)
compareLower _ _ _ = error "stub: compareLower"

emitMux :: LoweredWord g 1 -> LoweredWord g w -> LoweredWord g w
        -> LowerM (LoweredWord g w)
emitMux _ _ _ = error "stub: emitMux"

emitConcat :: LoweredWord g a -> LoweredWord g b -> LowerM (LoweredWord g (a + b))
emitConcat _ _ = error "stub: emitConcat"

emitExtract :: proxy hi -> proxy lo -> LoweredWord g w
            -> LowerM (LoweredWord g (hi - lo + 1))
emitExtract _ _ _ = error "stub: emitExtract"

lowerReg :: RegId -> Circuit g w -> LowerM (LoweredWord g w)
lowerReg _ _ = error "stub: lowerReg"

-- ---------------------------------------------------------------------------
-- Placeholder types (to be filled by theory modules)
-- ---------------------------------------------------------------------------
type WordId        = Int
type NodeId        = Int
type RegId         = Int
type PolicyRef     = Int
type ObligationId  = Int
type BitPattern    = [Bool]
type Name          = String
type CtorTag       = String
type Payload       = String
type TypeFingerprint = String
type LowerRule     = String
type LoweringWitness = String
type Hash          = String
type PropertyId    = Int
