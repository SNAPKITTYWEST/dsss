# Typed Circuit DSL

The DSSS circuit DSL is a GADT in `src/Dsss/Circuit/DSL.hs` indexed by **input
bus width** and **output bus width** as `GHC.TypeNats`.  Width mismatches are
rejected by GHC at compile time — not by a runtime assertion, not by an
exception, by the type checker.

---

## Core Type

```haskell
data Circuit (i :: Nat) (o :: Nat) where
  Id      :: Circuit n n
  Split   :: Circuit n (n + n)
  Join    :: Circuit (n + n) n
  And     :: Circuit (2 * n) n
  Or      :: Circuit (2 * n) n
  Xor     :: Circuit (2 * n) n
  Not     :: Circuit n n
  Reg     :: KnownNat n => Circuit n n
  (:***:) :: Circuit i1 o1 -> Circuit i2 o2 -> Circuit (i1 + i2) (o1 + o2)
  (:>>>:) :: (CheckWire m1 m2 ~ m) => Circuit i m1 -> Circuit m2 o -> Circuit i o
```

The two composition operators:

- `(:***:)` — **parallel** composition.  Two independent circuits side by side;
  the combined width is the sum of the individual widths.
- `(:>>>:)` — **sequential** composition (pipe).  The output of the left circuit
  feeds the input of the right.  Wire widths must match exactly; if they don't,
  GHC emits a structured type error.

---

## Wire Composition and the `CheckWire` Type Family

`(:>>>:)` uses the `CheckWire` type family to enforce the width contract:

```haskell
type family CheckWire (m1 :: Nat) (m2 :: Nat) :: Nat where
  CheckWire m m   = m                 -- widths match: pass through
  CheckWire m1 m2 = TypeError         -- widths differ: compile error
    ( 'Text "Circuit Topology Error: Wiring Invariant Violation"
    ':$$: 'Text "================================================="
    ':$$: 'Text "Upstream output bus width:   " ':<>: 'ShowType m1
    ':$$: 'Text "Downstream input bus width:  " ':<>: 'ShowType m2
    ':$$: 'Text "Cannot safely bridge "
          ':<>: 'ShowType m1 ':<>: 'Text " wires to "
          ':<>: 'ShowType m2 ':<>: 'Text " terminals."
    )
```

If you try to connect a 64-bit output to a 32-bit input, GHC prints:

```
Circuit Topology Error: Wiring Invariant Violation
=================================================
Upstream output bus width:   64
Downstream input bus width:  32
Cannot safely bridge 64 wires to 32 terminals.
```

This is the complete error message — no runtime behaviour is needed to detect it.

---

## Writing Your First Circuit

### Identity and negation

```haskell
-- A 16-bit wire that passes through unchanged
id16 :: Circuit 16 16
id16 = Id

-- Invert all 16 bits
inv16 :: Circuit 16 16
inv16 = Not
```

### Parallel buses

```haskell
-- Process two 8-bit buses side by side, yielding 16 bits
twoByte :: Circuit 16 16
twoByte = Not :***:  Not   -- invert both halves independently
```

The type `Circuit (8 + 8) (8 + 8)` is inferred as `Circuit 16 16` by GHC's
type-nat normalisation.

### Sequential pipeline

```haskell
-- XOR a 128-bit bus, register the 64-bit result, invert
pipeline :: Circuit 128 64
pipeline = Xor :>>>: Reg :>>>: Not
```

`Xor` has type `Circuit (2*64) 64` = `Circuit 128 64`.  
`Reg` has type `Circuit 64 64`.  
`Not` has type `Circuit 64 64`.  
Sequential composition type-checks because all intermediate widths agree.

---

## Gate-Level Primitives (`Gate.hs`)

Below `Circuit`, the `Gate` type models individual word-level operations in the
lowered SSA graph:

```haskell
data Gate (g :: CircuitId) (out :: Width) where
  Const  :: KnownNat w => Vec w Bit -> Gate g w
  Input  :: KnownNat w => String    -> Gate g w
  Not    :: Wire g w -> Gate g w
  And    :: Wire g w -> Wire g w -> Gate g w
  Or     :: Wire g w -> Wire g w -> Gate g w
  Xor    :: Wire g w -> Wire g w -> Gate g w
  Mux    :: Wire g 1 -> Wire g w -> Wire g w -> Gate g w    -- 1-bit select
  Concat :: Wire g a -> Wire g b -> Gate g (a + b)
  Slice  :: (Fits lo w, Fits hi w)
         => Wire g w -> Fin (hi - lo + 1) -> Gate g (hi - lo + 1)
  EqW    :: Wire g w -> Wire g w -> Gate g 1                -- equality → 1 bit
  Ult    :: Wire g w -> Wire g w -> Gate g 1                -- unsigned lt → 1 bit
  Add    :: Wire g w -> Wire g w -> Gate g w
  Sub    :: Wire g w -> Wire g w -> Gate g w
  Mul    :: Wire g w -> Wire g w -> Gate g w
  Reg    :: Wire g w -> Gate g w
```

### Statically-checked bit slices

`Slice` carries `Fits lo w` and `Fits hi w` constraints (from
`Dsss.Circuit.TypeNat`):

```haskell
type family Fits (i :: Nat) (n :: Nat) :: Constraint where
  Fits i n =
    Assert (i <=? (n - 1))
      ( 'Text "Port index " ':<>: 'ShowType i
      ':<>: 'Text " is outside width " ':<>: 'ShowType n
      )
```

Attempting to take a slice of bits 30–63 from a 32-bit wire (valid) compiles.
Attempting bits 0–63 from a 32-bit wire is a compile error:

```
Port index 63 is outside width 32
```

### Width-preserving helpers

```haskell
type family SameWidth (a :: Nat) (b :: Nat) :: Constraint where
  SameWidth n n = ()
  SameWidth a b = TypeError ('Text "Wire-width mismatch: " ...)

type family NonZero (n :: Nat) :: Constraint where
  NonZero 0 = TypeError ('Text "Circuit width must be non-zero")
  NonZero _ = ()
```

Use `SameWidth` in your own functions when you need to assert that two
independently-typed wires have equal width without funnelling them through a
constructor.

---

## Worked Example: 4-Bit Ripple Carry Adder

A ripple carry adder computes `A + B + Cin` one bit at a time, propagating the
carry.  We build it by composing individual full adders.

### Full adder (one bit)

A single full adder takes three inputs (A, B, Cin) and produces two outputs (Sum,
Cout).  We encode both on a 2-bit output bus:

```haskell
-- Full adder: 3 inputs → 2 outputs (bit 1 = Cout, bit 0 = Sum)
--
--   Sum  = A XOR B XOR Cin
--   Cout = (A AND B) OR (Cin AND (A XOR B))
--
-- We represent it as a 3→2 circuit, where the 3-bit input is packed as
-- [A, B, Cin] and the 2-bit output is [Cout, Sum].
fullAdder :: Circuit 3 2
fullAdder = undefined  -- implementation below in the lowering pass
            -- The DSL GADT declares the interface; the body is built
            -- via Gate combinators in the Builder monad.
```

In the `Gate` world (after lowering), a full adder is:

```haskell
buildFullAdder
  :: Wire g 1   -- A
  -> Wire g 1   -- B
  -> Wire g 1   -- Cin
  -> BuildM g (Wire g 1, Wire g 1)   -- (Sum, Cout)
buildFullAdder a b cin = do
  ab   <- emit (Xor a b)           -- A XOR B
  sum_ <- emit (Xor ab cin)        -- (A XOR B) XOR Cin
  t1   <- emit (And a b)           -- A AND B
  t2   <- emit (And cin ab)        -- Cin AND (A XOR B)
  cout <- emit (Or t1 t2)          -- Cout
  pure (sum_, cout)
```

### 4-bit ripple carry adder

Chain four full adders, feeding each stage's `Cout` as the next stage's `Cin`.
The total interface is `Circuit (8 + 1) (4 + 1)` — 8 data bits plus carry-in,
producing 4 sum bits plus carry-out:

```haskell
-- rippleCarry4 : 9 → 5
-- Inputs  [a3,a2,a1,a0, b3,b2,b1,b0, cin]  (9 bits)
-- Outputs [cout, s3, s2, s1, s0]            (5 bits)
rippleCarry4 :: Circuit 9 5
rippleCarry4 = undefined   -- assembled in BuildM via four buildFullAdder calls
```

The circuit type `Circuit 9 5` is verified at compile time.  If you accidentally
wire stage 2's `Sum` into stage 3's `Cin` instead of stage 2's `Cout`, the bus
widths still match (both are 1), but the logical error would be caught by
property tests — there is no substitute for a correct functional spec.

### Width invariant in the lowering pass

When `rippleCarry4` is lowered via `Dsss.Circuit.Lower.Pass.lower`, the pass
emits a `LowerCert` for every node.  The `certWidth` field carries the natural
number reflecting the GADT type index `w`:

```haskell
data LowerCert = LowerCert
  { certNode        :: !WordId
  , certSource      :: !NodeId
  , certSourceType  :: !TypeFingerprint   -- e.g. "Circuit 9 5"
  , certRule        :: !LowerRule
  , certWidth       :: !Natural           -- always == natVal (Proxy @w)
  , certObligations :: ![ObligationId]
  , ...
  }
```

Invariant I1 (`lower : Circuit g w -> LoweredWord g w`) guarantees that
`certWidth` equals the type-level `w` for every emitted certificate.  If it
doesn't, `reifyWidth` throws `ZeroWidthCircuit` before the certificate is
emitted.

---

## What Happens When Widths Don't Match

This is the full story, including the compile-time error, the type family
mechanics, and how to read the diagnostic.

### Scenario: connecting a 64-bit output to a 32-bit input

```haskell
badCircuit :: Circuit 128 32
badCircuit = Xor :>>>: Not   -- Xor : 128→64, Not : 64→64, but we said →32
```

GHC evaluates `CheckWire 64 64 ~ 64` for the `Xor :>>>: Not` step — that
succeeds.  Then it tries to unify the result `Circuit 128 64` with the declared
type `Circuit 128 32`, which fails:

```
Couldn't match type '64' with '32'
Expected type: Circuit 128 32
  Actual type: Circuit 128 64
```

### Scenario: mismatched intermediate wire

```haskell
badPipe :: Circuit 64 64
badPipe = Not :>>>: Split   -- Not : 64→64, Split : 64→128, result is 64→128 ≠ 64→64
```

GHC evaluates `CheckWire 128 64`:

```
Circuit Topology Error: Wiring Invariant Violation
=================================================
Upstream output bus width:   128
Downstream input bus width:  64
Cannot safely bridge 128 wires to 64 terminals.
```

The message names the offending widths precisely.  Read it as: "the component on
the left emits 128 wires; the component on the right only has 64 input
terminals."

### What the error does NOT mean

- It does not mean a runtime buffer overrun.
- It does not mean a misaligned memory access.
- It means you have described a circuit whose topology is geometrically
  impossible.  Fix the type, or insert an adapter (`Join`, `Split`, `Slice`,
  `Concat`) to reconcile the widths.

---

## TypeNat Utilities Reference

All utilities live in `src/Dsss/Circuit/TypeNat.hs`.

| Type synonym | Value |
|---|---|
| `One` | 1 |
| `Two` | 2 |
| `Byte` | 8 |
| `Word` | 32 |
| `Lane` | 64 |

| Type family | Purpose |
|---|---|
| `Assert p msg` | Constraint: if `p ~ 'False`, emit `TypeError msg` |
| `NonZero n` | Constraint: fails at compile time if `n = 0` |
| `Fits i n` | Constraint: `i <= n-1` — for valid port indices and slice bounds |
| `SameWidth a b` | Constraint: `a = b` — for width equality assertions |

Runtime helper:

```haskell
widthVal :: forall n. KnownNat n => Int
widthVal = fromInteger (natVal (Proxy @n))
```

Use `widthVal` in the `BuildM` monad to allocate correctly-sized buffers.

---

## Further Reading

- `src/Dsss/Circuit/Gate.hs` — full gate vocabulary and `ValidSlice` constraint
- `src/Dsss/Circuit/Lower/Pass.hs` — how circuits become word-level SSA graphs
- `spec/LOWERING_SPEC.md` — formal lowering contract, width equations per
  constructor, structural rewrites, graph strata
- `docs/ZK_PIPELINE.md` — how the lowered circuit feeds the Circom ZK pipeline
